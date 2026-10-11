import Foundation
import Combine
import TrackerCore

@MainActor
final class TrackerStore: ObservableObject {
    static let shared = TrackerStore()
    @Published private(set) var state = TrackerState()
    @Published var errorMessage: String?
    @Published private(set) var storageFailure: String?
    @Published private(set) var now = Date()
    @Published var selectedDeviceID: UUID? {
        didSet { defaults.set(selectedDeviceID?.uuidString, forKey: "selectedDeviceID") }
    }
    private var persistence: TrackerPersistence?
    private let defaults: UserDefaults

    init(persistence: TrackerPersistence? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedDeviceID = defaults.string(forKey: "selectedDeviceID").flatMap(UUID.init(uuidString:))
        self.persistence = persistence
        reload()
    }

    var device: TrackedDevice? { state.devices.first { $0.id == selectedDeviceID } ?? state.devices.first }
    var reduction: SessionReduction {
        SessionReducer.reduce(events: state.events.filter { $0.deviceID == device?.id },
                              corrections: state.corrections.filter { $0.deviceID == device?.id }, asOf: now)
    }
    var sessions: [UsageSession] { reduction.sessions }
    var reviewCount: Int {
        let result = reduction
        let unresolvedWithoutRow = result.unresolvedCorrections.filter { correction in
            !result.sessions.contains { $0.status == .needsReview && !Set($0.anchorEventIDs).isDisjoint(with: correction.anchorEventIDs) }
        }
        return result.sessions.filter { $0.status == .needsReview }.count + unresolvedWithoutRow.count
    }
    var activeObservation: ChargeObservation? {
        state.observations.filter { $0.deviceID == device?.id && $0.endAt == nil }.max { $0.startAt < $1.startAt }
    }
    var latestBattery: BatterySnapshot? {
        state.batteries.filter { $0.deviceID == device?.id && $0.userConfirmed }.max { $0.importedAt < $1.importedAt }
    }
    var todayDuration: TimeInterval {
        guard let range = Calendar.current.dateInterval(of: .day, for: Date()) else { return 0 }
        return IntervalMath.confirmedDuration(sessions: sessions, in: range)
    }

    func reload() {
        now = Date()
        do {
            if persistence == nil { persistence = try TrackerPersistence() }
            guard let persistence else { throw TrackerError("无法打开本地数据。") }
            let loaded = try persistence.load()
            state = loaded
            if !loaded.devices.contains(where: { $0.id == selectedDeviceID }) { selectedDeviceID = loaded.devices.first?.id }
            storageFailure = nil
        } catch {
            storageFailure = "本地数据暂时无法打开，原文件已保留。\n" + error.localizedDescription
        }
    }

    func run(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func mutate(_ body: (inout TrackerState) throws -> Void) throws {
        guard storageFailure == nil, let persistence else {
            throw TrackerError("数据尚未打开，本次记录未保存。请解锁后打开 App 重试。")
        }
        var next = state
        try body(&next)
        try persistence.save(next)
        state = next
        now = Date()
    }

    func refreshClock() { now = Date() }

    private func requiredDeviceID(_ explicit: UUID? = nil) throws -> UUID {
        guard let id = explicit ?? device?.id, state.devices.contains(where: { $0.id == id }) else {
            throw TrackerError("请先在 App 中建立耳机档案，再为快捷指令选择该设备。")
        }
        return id
    }

    func addDevice(name: String, model: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TrackerError("请填写耳机昵称。") }
        let newDevice = TrackedDevice(name: trimmed, model: model?.nilIfBlank)
        try mutate { $0.devices.append(newDevice) }
        selectedDeviceID = newDevice.id
    }

    func updateDevice(name: String, model: String?) throws {
        let id = try requiredDeviceID()
        guard let index = state.devices.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrackerError("请填写耳机昵称。")
        }
        try mutate { next in
            next.devices[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            next.devices[index].model = model?.nilIfBlank
        }
    }

    func recordConnection(kind: EventKind, deviceID: UUID? = nil, at: Date = Date()) throws {
        let id = try requiredDeviceID(deviceID)
        try mutate { try TrackerEngine.recordConnection(state: &$0, deviceID: id, kind: kind, at: at, id: UUID()) }
        if kind == .end { NotificationService.shared.cancelPending(deviceID: id) }
        else if defaults.bool(forKey: "reviewRemindersEnabled") {
            NotificationService.shared.scheduleReview(deviceID: id, start: at)
        }
    }

    func addManualSession(start: Date, end: Date, tag: String?, note: String?) throws {
        let id = try requiredDeviceID()
        try mutate { try TrackerEngine.addManualSession(state: &$0, deviceID: id, start: start, end: end, tag: tag, note: note, id: UUID()) }
    }

    func correctSession(_ session: UsageSession, start: Date, end: Date, tag: String?, note: String?, confirmLong: Bool = false) throws {
        let correction = SessionCorrection(id: session.id, anchorEventIDs: session.anchorEventIDs, deviceID: session.deviceID,
                                          startOverride: start, endOverride: end, excluded: false,
                                          longSpanConfirmed: confirmLong, tag: tag, note: note)
        let stale = reduction.unresolvedCorrections.filter { !Set($0.anchorEventIDs).isDisjoint(with: session.anchorEventIDs) }
        try mutate { next in
            for old in stale { try TrackerEngine.removeCorrection(state: &next, id: old.id) }
            try TrackerEngine.saveCorrection(state: &next, correction: correction)
        }
    }

    func setExcluded(_ session: UsageSession, excluded: Bool) throws {
        var correction = state.corrections.first { $0.id == session.id && Set($0.anchorEventIDs) == Set(session.anchorEventIDs) }
            ?? SessionCorrection(id: session.id, anchorEventIDs: session.anchorEventIDs, deviceID: session.deviceID)
        correction.excluded = excluded
        correction.updatedAt = Date()
        let stale = reduction.unresolvedCorrections.filter { !Set($0.anchorEventIDs).isDisjoint(with: session.anchorEventIDs) }
        try mutate { next in
            for old in stale { try TrackerEngine.removeCorrection(state: &next, id: old.id) }
            try TrackerEngine.saveCorrection(state: &next, correction: correction)
        }
    }

    func dismissStaleCorrection(_ correction: SessionCorrection) throws {
        try mutate { try TrackerEngine.removeCorrection(state: &$0, id: correction.id) }
    }

    func splitSession(_ session: UsageSession, at: Date) throws {
        try mutate { try TrackerEngine.splitSession(state: &$0, sessionID: session.id, at: at, asOf: Date()) }
    }

    func recordBattery(left: Int?, right: Int?, caseLevel: Int?, measuredAt: Date?, source: BatterySource) throws {
        try recordBattery(deviceID: requiredDeviceID(), left: left, right: right, caseLevel: caseLevel,
                          measuredAt: measuredAt, source: source)
    }

    func recordBattery(deviceID: UUID, left: Int?, right: Int?, caseLevel: Int?, measuredAt: Date?, source: BatterySource) throws {
        let id = try requiredDeviceID(deviceID)
        let snapshot = BatterySnapshot(deviceID: id, left: left, right: right, caseLevel: caseLevel,
                                       measuredAt: measuredAt, source: source)
        try mutate { try TrackerEngine.saveBattery(state: &$0, snapshot: snapshot) }
    }

    func charge(_ action: ChargeAction, at: Date = Date(), reason: String? = nil) throws {
        try charge(action, deviceID: requiredDeviceID(), at: at, reason: reason)
    }

    func markCaseFull(at: Date = Date()) throws {
        let restart = activeObservation != nil
        try charge(restart ? .topUpAndRestart : .startFull, deviceID: requiredDeviceID(), at: at,
                   reason: restart ? "盒子充满后重新观察" : nil, fullOnRestart: restart)
    }

    func charge(_ action: ChargeAction, deviceID: UUID, at: Date, reason: String?, fullOnRestart: Bool = false) throws {
        let id = try requiredDeviceID(deviceID)
        try mutate { _ = try TrackerEngine.charge(state: &$0, deviceID: id, action: action, at: at, reason: reason, requestID: UUID(), fullOnRestart: fullOnRestart) }
    }

    func deleteObservation(_ observation: ChargeObservation) throws {
        try mutate { try TrackerEngine.deleteObservation(state: &$0, id: observation.id) }
    }

    func updateObservation(_ observation: ChargeObservation) throws {
        try mutate { try TrackerEngine.updateObservation(state: &$0, observation: observation, expectedRevision: observation.revision) }
    }

    func undoLastCharge() throws {
        let id = try requiredDeviceID()
        guard let receipt = state.receipts.last(where: { $0.deviceID == id }) else {
            throw TrackerError("还没有可以撤销的充电操作。")
        }
        try mutate { try TrackerEngine.undoCharge(state: &$0, requestID: receipt.id) }
    }

    func importBackup(data: Data) throws {
        guard data.count <= 25 * 1024 * 1024 else { throw TrackerError("备份超过 25 MB，请检查文件是否正确。") }
        let incoming = try JSONDecoder().decode(TrackerState.self, from: data)
        let merged = try TrackerEngine.merge(local: state, incoming: incoming)
        try mutate { $0 = merged }
        if device == nil { selectedDeviceID = state.devices.first?.id }
    }

    func exportBackup() throws -> URL {
        guard storageFailure == nil else { throw TrackerError("请先恢复对本地数据的访问。") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportFile(data: encoder.encode(state), name: "AirPodsTracker-backup.json")
    }

    func exportCSV() throws -> URL {
        guard storageFailure == nil else { throw TrackerError("请先恢复对本地数据的访问。") }
        let allSessions = SessionReducer.reduce(events: state.events, corrections: state.corrections, asOf: Date()).sessions
        var rows = ["id,device,start,end,durationSeconds,status,source,timeZone"]
        let formatter = ISO8601DateFormatter()
        for session in allSessions {
            let name = state.devices.first { $0.id == session.deviceID }?.name ?? ""
            let duration = session.status == .confirmed ? session.end.flatMap { end in session.start.map { String(end.timeIntervalSince($0)) } } ?? "" : ""
            let row = [session.id.uuidString, name, session.start.map(formatter.string(from:)) ?? "", session.end.map(formatter.string(from:)) ?? "", duration, session.status.rawValue, session.source.rawValue, TimeZone.current.identifier]
            rows.append(row.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ","))
        }
        return try exportFile(data: Data(("\u{FEFF}" + rows.joined(separator: "\r\n")).utf8), name: "AirPodsTracker-records.csv")
    }

    private func exportFile(data: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
