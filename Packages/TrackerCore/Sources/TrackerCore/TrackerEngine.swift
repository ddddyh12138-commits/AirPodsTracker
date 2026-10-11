import Foundation

public enum TrackerEngine {
    public static func recordConnection(state: inout TrackerState, deviceID: UUID, kind: EventKind, at: Date, id: UUID) throws {
        try requireDevice(deviceID, in: state)
        try requireDate(at)
        if let existing = state.events.first(where: { $0.id == id }) {
            guard existing.deviceID == deviceID, existing.kind == kind, existing.observedAt == at, existing.source == .shortcut, existing.manualSessionID == nil else { throw TrackerError("这条记录的编号已存在，但内容不同；原记录已保留") }
            return
        }
        var candidate = state
        candidate.events.append(ConnectionEvent(id: id, deviceID: deviceID, kind: kind, observedAt: at))
        try validate(candidate)
        state = candidate
    }

    public static func addManualSession(state: inout TrackerState, deviceID: UUID, start: Date, end: Date, tag: String?, note: String?, id: UUID) throws {
        try requireDevice(deviceID, in: state)
        try requireRange(start, end)
        let existing = state.events.filter { $0.manualSessionID == id }
        if !existing.isEmpty {
            let correction = state.corrections.first { $0.id == id }
            guard existing.count == 2, existing.allSatisfy({ $0.deviceID == deviceID && $0.source == .manual }), existing.first(where: { $0.kind == .start })?.observedAt == start, existing.first(where: { $0.kind == .end })?.observedAt == end, correction?.tag == tag, correction?.note == note else { throw TrackerError("这段手动记录的编号已存在，但内容不同") }
            return
        }
        let reduction = SessionReducer.reduce(events: state.events, corrections: state.corrections, asOf: end)
        guard !reduction.sessions.contains(where: { overlaps($0, deviceID: deviceID, start: start, end: end) }) else { throw TrackerError("时间与已有记录重叠，请先编辑、拆分或排除已有记录") }
        var candidate = state
        appendManualSession(to: &candidate, deviceID: deviceID, start: start, end: end, tag: tag, note: note, id: id)
        try validate(candidate)
        state = candidate
    }

    public static func saveCorrection(state: inout TrackerState, correction: SessionCorrection) throws {
        try requireDevice(correction.deviceID, in: state)
        let reduction = SessionReducer.reduce(events: state.events, corrections: [], asOf: correction.updatedAt)
        guard reduction.sessions.contains(where: { $0.id == correction.id && $0.deviceID == correction.deviceID && Set($0.anchorEventIDs) == Set(correction.anchorEventIDs) }) else { throw TrackerError("原记录已发生变化，请刷新后核对新的端点") }
        var candidate = state
        candidate.corrections.removeAll { $0.id == correction.id }
        candidate.corrections.append(correction)
        try validate(candidate)
        let session = SessionReducer.reduce(events: candidate.events, corrections: candidate.corrections, asOf: correction.updatedAt).sessions.first { $0.id == correction.id }
        if !correction.excluded, let start = session?.start, let end = session?.end { try requireRange(start, end) }
        state = candidate
    }

    /// A stale correction may be deliberately discarded after the UI shows its original anchors.
    public static func removeCorrection(state: inout TrackerState, id: UUID) throws {
        guard state.corrections.contains(where: { $0.id == id }) else { throw TrackerError("没有找到这条更正") }
        state.corrections.removeAll { $0.id == id }
    }

    public static func saveBattery(state: inout TrackerState, snapshot: BatterySnapshot) throws {
        try requireDevice(snapshot.deviceID, in: state)
        try validateBattery(snapshot)
        if let existing = state.batteries.first(where: { $0.id == snapshot.id }) {
            guard existing == snapshot else { throw TrackerError("这条电量记录的编号已存在，但内容不同") }
            return
        }
        var candidate = state
        candidate.batteries.append(snapshot)
        try validate(candidate)
        state = candidate
    }

    @discardableResult
    public static func charge(state: inout TrackerState, deviceID: UUID, action: ChargeAction, at: Date, reason: String?, requestID: UUID, fullOnRestart: Bool = false) throws -> UUID {
        try requireDevice(deviceID, in: state)
        try requireDate(at)
        let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = ChargeRequest(deviceID: deviceID, action: action, at: at, reason: normalizedReason, fullOnRestart: fullOnRestart)
        if let receipt = state.receipts.first(where: { $0.id == requestID }) {
            guard receipt.requestInput == request else { throw TrackerError("这个请求编号已用于不同内容，未修改原记录") }
            guard receipt.status == .applied else { throw TrackerError(receipt.status == .undone ? "原操作已撤销，请发起新的操作" : "原操作已删除，请发起新的操作") }
            return receipt.observationID
        }
        var candidate = state
        let activeIndex = candidate.observations.firstIndex { $0.deviceID == deviceID && $0.endAt == nil }
        var previous: [ChargeObservation] = []
        var newObservations: [UUID] = []
        var newSnapshots: [UUID] = []
        var revisions: [UUID: Int] = [:]
        let resultID: UUID
        switch action {
        case .startFull, .startNow:
            guard activeIndex == nil else { throw TrackerError("已有进行中的观察，请选择“补电并开始新观察”") }
            var snapshotID: UUID?
            if action == .startFull {
                let snapshot = BatterySnapshot(deviceID: deviceID, caseLevel: 100, measuredAt: at, importedAt: at)
                candidate.batteries.append(snapshot); newSnapshots.append(snapshot.id); snapshotID = snapshot.id
            }
            let observation = ChargeObservation(deviceID: deviceID, startAt: at, startReason: action == .startFull ? "盒子已充满" : "从现在观察", startSnapshotID: snapshotID)
            candidate.observations.append(observation); newObservations.append(observation.id); revisions[observation.id] = observation.revision
            resultID = observation.id
        case .topUpAndRestart:
            guard let index = activeIndex else { throw TrackerError("没有进行中的观察，请先开始观察") }
            try requireRange(candidate.observations[index].startAt, at)
            previous.append(candidate.observations[index])
            candidate.observations[index].endAt = at; candidate.observations[index].endReason = "补电"; candidate.observations[index].revision += 1
            revisions[candidate.observations[index].id] = candidate.observations[index].revision
            var snapshotID: UUID?
            if fullOnRestart {
                let snapshot = BatterySnapshot(deviceID: deviceID, caseLevel: 100, measuredAt: at, importedAt: at)
                candidate.batteries.append(snapshot); newSnapshots.append(snapshot.id); snapshotID = snapshot.id
            }
            let observation = ChargeObservation(deviceID: deviceID, startAt: at, startReason: fullOnRestart ? "补电至盒子充满" : "补电后重新观察", startSnapshotID: snapshotID, note: normalizedReason)
            candidate.observations.append(observation); newObservations.append(observation.id); revisions[observation.id] = observation.revision
            resultID = observation.id
        case .end:
            guard let index = activeIndex else { throw TrackerError("没有进行中的观察可以结束") }
            guard let endReason = normalizedReason, !endReason.isEmpty else { throw TrackerError("请选择结束原因") }
            try requireRange(candidate.observations[index].startAt, at)
            previous.append(candidate.observations[index])
            candidate.observations[index].endAt = at; candidate.observations[index].endReason = endReason; candidate.observations[index].revision += 1
            if endReason == "盒子没电" || endReason == "盒子没电了" {
                let snapshot = BatterySnapshot(deviceID: deviceID, caseLevel: 0, measuredAt: at, importedAt: at)
                candidate.batteries.append(snapshot); newSnapshots.append(snapshot.id); candidate.observations[index].endSnapshotID = snapshot.id
            }
            resultID = candidate.observations[index].id
            revisions[resultID] = candidate.observations[index].revision
        }
        let undo = ChargeUndoState(previousObservations: previous, createdObservationIDs: newObservations, createdSnapshotIDs: newSnapshots, expectedRevisions: revisions)
        candidate.receipts.append(ChargeActionReceipt(id: requestID, deviceID: deviceID, observationID: resultID, requestInput: request, savedAt: at, undoState: undo))
        try validate(candidate)
        state = candidate
        return resultID
    }

    public static func updateObservation(state: inout TrackerState, observation: ChargeObservation, expectedRevision: Int) throws {
        guard let index = state.observations.firstIndex(where: { $0.id == observation.id }) else { throw TrackerError("观察不存在，可能已被删除") }
        guard state.observations[index].revision == expectedRevision else { throw TrackerError("观察已被修改，请刷新后重试") }
        guard observation.deviceID == state.observations[index].deviceID else { throw TrackerError("不能更改观察所属设备") }
        var candidate = state
        var edited = observation
        edited.revision = expectedRevision + 1
        candidate.observations[index] = edited
        try validate(candidate)
        state = candidate
    }

    public static func deleteObservation(state: inout TrackerState, id: UUID) throws {
        guard state.observations.contains(where: { $0.id == id }) else { throw TrackerError("观察不存在，可能已被删除") }
        var candidate = state
        candidate.observations.removeAll { $0.id == id }
        for index in candidate.receipts.indices {
            if candidate.receipts[index].observationID == id {
                candidate.receipts[index].status = .deleted; candidate.receipts[index].undoState = nil
            } else if candidate.receipts[index].undoState?.expectedRevisions[id] != nil {
                candidate.receipts[index].undoState = nil
            }
        }
        try validate(candidate)
        state = candidate
    }

    public static func undoCharge(state: inout TrackerState, requestID: UUID) throws {
        guard let index = state.receipts.firstIndex(where: { $0.id == requestID }) else { throw TrackerError("找不到这次充电操作") }
        let receipt = state.receipts[index]
        guard state.receipts.last(where: { $0.deviceID == receipt.deviceID })?.id == requestID, receipt.status == .applied, let undo = receipt.undoState else { throw TrackerError("只能撤销本设备最新且未变更的操作；请使用观察编辑") }
        for (id, revision) in undo.expectedRevisions {
            guard state.observations.first(where: { $0.id == id })?.revision == revision else { throw TrackerError("相关观察已变更，无法安全撤销；请使用观察编辑") }
        }
        var candidate = state
        candidate.observations.removeAll { undo.createdObservationIDs.contains($0.id) }
        for previous in undo.previousObservations {
            candidate.observations.removeAll { $0.id == previous.id }
            candidate.observations.append(previous)
        }
        candidate.batteries.removeAll { undo.createdSnapshotIDs.contains($0.id) }
        candidate.receipts[index].removedSnapshotIDs = undo.createdSnapshotIDs
        candidate.receipts[index].status = .undone; candidate.receipts[index].undoState = nil
        try validate(candidate)
        state = candidate
    }

    public static func splitSession(state: inout TrackerState, sessionID: UUID, at: Date, asOf: Date) throws {
        let reduction = SessionReducer.reduce(events: state.events, corrections: state.corrections, asOf: asOf)
        guard let session = reduction.sessions.first(where: { $0.id == sessionID }), session.status != .excluded, let start = session.start, let end = session.end, start < at, at < end else { throw TrackerError("拆分需要明确的开始和结束，拆分时刻必须在两者之间") }
        guard !reduction.unresolvedCorrections.contains(where: { $0.deviceID == session.deviceID && !Set($0.anchorEventIDs).isDisjoint(with: session.anchorEventIDs) }) else { throw TrackerError("请先解决原记录的更正冲突，再拆分") }
        var candidate = state
        candidate.corrections.removeAll { $0.id == sessionID }
        candidate.corrections.append(SessionCorrection(id: session.id, anchorEventIDs: session.anchorEventIDs, deviceID: session.deviceID, excluded: true, tag: session.tag, note: session.note, updatedAt: asOf))
        appendManualSession(to: &candidate, deviceID: session.deviceID, start: start, end: at, tag: session.tag, note: session.note, id: UUID())
        appendManualSession(to: &candidate, deviceID: session.deviceID, start: at, end: end, tag: session.tag, note: session.note, id: UUID())
        try validate(candidate)
        state = candidate
    }

    private static func appendManualSession(to state: inout TrackerState, deviceID: UUID, start: Date, end: Date, tag: String?, note: String?, id: UUID) {
        let startEvent = ConnectionEvent(deviceID: deviceID, kind: .start, observedAt: start, source: .manual, manualSessionID: id)
        let endEvent = ConnectionEvent(deviceID: deviceID, kind: .end, observedAt: end, source: .manual, manualSessionID: id)
        state.events += [startEvent, endEvent]
        state.corrections.append(SessionCorrection(id: id, anchorEventIDs: [startEvent.id, endEvent.id], deviceID: deviceID, longSpanConfirmed: true, tag: tag, note: note))
    }

    private static func overlaps(_ session: UsageSession, deviceID: UUID, start: Date, end: Date) -> Bool {
        guard session.deviceID == deviceID, session.status != .excluded, let existingStart = session.start, let existingEnd = session.end else { return false }
        return existingStart < end && start < existingEnd
    }
    static func requireDevice(_ id: UUID, in state: TrackerState) throws {
        guard state.devices.contains(where: { $0.id == id }) else { throw TrackerError("找不到所选设备，请先在 App 中创建设备") }
    }
    static func requireDate(_ value: Date) throws {
        guard value.timeIntervalSince1970.isFinite else { throw TrackerError("记录时间无效") }
    }
    static func requireRange(_ start: Date, _ end: Date) throws {
        try requireDate(start); try requireDate(end)
        guard end > start else { throw TrackerError("结束时间必须晚于开始时间") }
    }
    static func validateBattery(_ snapshot: BatterySnapshot) throws {
        let levels = [snapshot.left, snapshot.right, snapshot.caseLevel].compactMap { $0 }
        guard !levels.isEmpty else { throw TrackerError("请至少填写一个部件的电量") }
        guard levels.allSatisfy({ (0...100).contains($0) }) else { throw TrackerError("电量必须是 0 至 100 的整数，未知请留空") }
        guard snapshot.userConfirmed else { throw TrackerError("请核对部件、电量与读数时间后再保存") }
        try requireDate(snapshot.importedAt)
        if let measuredAt = snapshot.measuredAt { try requireDate(measuredAt) }
    }
}
