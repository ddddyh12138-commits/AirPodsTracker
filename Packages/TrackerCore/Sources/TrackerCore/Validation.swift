import Foundation

extension TrackerEngine {
    public static func validate(_ state: TrackerState) throws {
        guard state.schemaVersion == 1 else { throw TrackerError("备份版本不受支持，请先更新 App；原数据未覆盖") }
        try unique(state.devices.map(\.id), name: "设备")
        try unique(state.events.map(\.id), name: "原始事件")
        try unique(state.corrections.map(\.id), name: "更正")
        try unique(state.batteries.map(\.id), name: "电量")
        try unique(state.observations.map(\.id), name: "充电观察")
        try unique(state.receipts.map(\.id), name: "充电操作")
        let deviceIDs = Set(state.devices.map(\.id))
        let eventByID = Dictionary(uniqueKeysWithValues: state.events.map { ($0.id, $0) })
        let batteryByID = Dictionary(uniqueKeysWithValues: state.batteries.map { ($0.id, $0) })
        let observationByID = Dictionary(uniqueKeysWithValues: state.observations.map { ($0.id, $0) })
        for device in state.devices {
            guard !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrackerError("设备名称不能为空") }
            try requireDate(device.createdAt)
        }
        for event in state.events {
            guard deviceIDs.contains(event.deviceID) else { throw TrackerError("原始事件引用的设备不存在，无法恢复") }
            try requireDate(event.observedAt); try requireDate(event.savedAt)
            guard TimeZone(identifier: event.timeZoneID) != nil else { throw TrackerError("事件包含无法识别的时区") }
            guard (event.source == .manual) == (event.manualSessionID != nil) else { throw TrackerError("手动记录必须有独立的配对编号；自动记录不能混入手动配对") }
        }
        let manual = Dictionary(grouping: state.events.filter { $0.source == .manual }, by: { $0.manualSessionID! })
        for (id, pair) in manual {
            guard eventByID[id] == nil else { throw TrackerError("手动段编号与原始事件编号冲突") }
            guard pair.count == 2, Set(pair.map(\.deviceID)).count == 1, let start = pair.first(where: { $0.kind == .start }), let end = pair.first(where: { $0.kind == .end }) else { throw TrackerError("手动记录缺少明确的一对开始和结束") }
            try requireRange(start.observedAt, end.observedAt)
        }
        for correction in state.corrections {
            guard deviceIDs.contains(correction.deviceID), !correction.anchorEventIDs.isEmpty, Set(correction.anchorEventIDs).count == correction.anchorEventIDs.count else { throw TrackerError("更正的设备或原始端点无效") }
            guard correction.anchorEventIDs.allSatisfy({ eventByID[$0]?.deviceID == correction.deviceID }) else { throw TrackerError("更正引用的原始端点不存在或属于其他设备") }
            guard correction.anchorEventIDs.contains(correction.id) || manual[correction.id]?.first?.deviceID == correction.deviceID else { throw TrackerError("更正与原始记录编号不匹配") }
            try requireDate(correction.updatedAt)
            if let start = correction.startOverride { try requireDate(start) }
            if let end = correction.endOverride { try requireDate(end) }
            if let start = correction.startOverride, let end = correction.endOverride, !correction.excluded { try requireRange(start, end) }
        }
        for snapshot in state.batteries {
            guard deviceIDs.contains(snapshot.deviceID) else { throw TrackerError("电量记录引用的设备不存在") }
            try validateBattery(snapshot)
        }
        for observation in state.observations {
            guard deviceIDs.contains(observation.deviceID) else { throw TrackerError("充电观察引用的设备不存在") }
            guard observation.revision > 0, !observation.startReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrackerError("充电观察的版本或起点原因无效") }
            try requireDate(observation.startAt)
            if let end = observation.endAt {
                try requireRange(observation.startAt, end)
                guard let reason = observation.endReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TrackerError("已结束的观察缺少结束原因") }
            } else if observation.endReason != nil || observation.endSnapshotID != nil { throw TrackerError("未结束的观察不能包含结束原因或结束电量") }
            for id in [observation.startSnapshotID, observation.endSnapshotID].compactMap({ $0 }) {
                guard batteryByID[id]?.deviceID == observation.deviceID else { throw TrackerError("观察引用的电量不存在或属于其他设备") }
            }
        }
        for deviceID in deviceIDs {
            let observations = state.observations.filter { $0.deviceID == deviceID }.sorted { $0.startAt < $1.startAt }
            for index in observations.indices where index > 0 {
                guard let previousEnd = observations[index - 1].endAt, previousEnd <= observations[index].startAt else { throw TrackerError("同一设备的充电观察不能重叠，也不能同时存在两个进行中的观察") }
            }
        }
        for receipt in state.receipts {
            guard deviceIDs.contains(receipt.deviceID), receipt.requestInput.deviceID == receipt.deviceID else { throw TrackerError("充电操作回执的设备无效") }
            try requireDate(receipt.savedAt); try requireDate(receipt.requestInput.at)
            if receipt.status == .applied {
                guard observationByID[receipt.observationID]?.deviceID == receipt.deviceID else { throw TrackerError("有效充电回执引用的观察不存在") }
            } else {
                guard receipt.undoState == nil else { throw TrackerError("已撤销或删除的回执不能带有可执行的撤销状态") }
            }
            if let undo = receipt.undoState {
                guard undo.expectedRevisions.allSatisfy({ observationByID[$0.key]?.deviceID == receipt.deviceID && $0.value > 0 }), undo.createdObservationIDs.allSatisfy({ observationByID[$0]?.deviceID == receipt.deviceID }), undo.createdSnapshotIDs.allSatisfy({ batteryByID[$0]?.deviceID == receipt.deviceID }), undo.previousObservations.allSatisfy({ $0.deviceID == receipt.deviceID }) else { throw TrackerError("充电撤销信息引用了缺失的记录") }
            }
        }
    }

    public static func merge(local: TrackerState, incoming: TrackerState) throws -> TrackerState {
        guard local.schemaVersion == 1 && incoming.schemaVersion == 1 else { throw TrackerError("备份版本不受支持；原数据未覆盖") }
        // Validate incoming ID uniqueness before merging so duplicates cannot be silently discarded.
        try unique(incoming.devices.map(\.id), name: "备份设备")
        try unique(incoming.events.map(\.id), name: "备份事件")
        try unique(incoming.corrections.map(\.id), name: "备份更正")
        try unique(incoming.batteries.map(\.id), name: "备份电量")
        try unique(incoming.observations.map(\.id), name: "备份观察")
        try unique(incoming.receipts.map(\.id), name: "备份回执")
        var merged = TrackerState(
            devices: retainingLocal(local.devices, incoming.devices),
            events: retainingLocal(local.events, incoming.events),
            corrections: retainingLocal(local.corrections, incoming.corrections),
            batteries: retainingLocal(local.batteries, incoming.batteries),
            observations: retainingLocal(local.observations, incoming.observations),
            receipts: retainingLocal(local.receipts, incoming.receipts)
        )
        // A locally deleted observation stays deleted when an older backup is merged.
        let deleted = Set(local.receipts.filter { $0.status == .deleted }.map(\.observationID))
        let undoneCreation = Set(local.receipts.filter { $0.status == .undone && ($0.requestInput.action == .startNow || $0.requestInput.action == .startFull || $0.requestInput.action == .topUpAndRestart) }.map(\.observationID))
        let absent = deleted.union(undoneCreation)
        merged.observations.removeAll { absent.contains($0.id) }
        let removedSnapshots = Set(local.receipts.filter { $0.status != .applied }.flatMap(\.removedSnapshotIDs))
        merged.batteries.removeAll { removedSnapshots.contains($0.id) }
        // Restore is a new transaction. Old undo buffers are never reactivated.
        for index in merged.receipts.indices {
            merged.receipts[index].undoState = nil
            if absent.contains(merged.receipts[index].observationID), merged.receipts[index].status == .applied { merged.receipts[index].status = .deleted }
        }
        try validate(merged)
        return merged
    }

    public static func mergeConflictCount(local: TrackerState, incoming: TrackerState) -> Int {
        conflicts(local.devices, incoming.devices) + conflicts(local.events, incoming.events) + conflicts(local.corrections, incoming.corrections) + conflicts(local.batteries, incoming.batteries) + conflicts(local.observations, incoming.observations) + conflicts(local.receipts, incoming.receipts)
    }

    private static func unique(_ ids: [UUID], name: String) throws {
        guard Set(ids).count == ids.count else { throw TrackerError("\(name)包含重复编号，未修改原数据") }
    }
    private static func retainingLocal<T: Identifiable>(_ local: [T], _ incoming: [T]) -> [T] where T.ID == UUID {
        let localIDs = Set(local.map(\.id))
        return local + incoming.filter { !localIDs.contains($0.id) }
    }
    private static func conflicts<T: Identifiable & Equatable>(_ local: [T], _ incoming: [T]) -> Int where T.ID == UUID {
        incoming.filter { item in local.contains { $0.id == item.id && $0 != item } }.count
    }
}
