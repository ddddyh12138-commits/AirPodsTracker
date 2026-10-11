import AppIntents
import Foundation
import TrackerCore

struct TrackedDeviceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "耳机档案"
    static var defaultQuery = TrackedDeviceQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct TrackedDeviceQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TrackedDeviceEntity] {
        await MainActor.run {
            TrackerStore.shared.state.devices.filter { identifiers.contains($0.id) }
                .map { TrackedDeviceEntity(id: $0.id, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [TrackedDeviceEntity] {
        await MainActor.run {
            TrackerStore.shared.state.devices.map { TrackedDeviceEntity(id: $0.id, name: $0.name) }
        }
    }
    func defaultResult() async -> TrackedDeviceEntity? {
        await MainActor.run { TrackerStore.shared.device.map { TrackedDeviceEntity(id: $0.id, name: $0.name) } }
    }
}

struct RecordConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "记录耳机连接"
    static var description = IntentDescription("用于蓝牙连接个人自动化。保存动作执行时间，无需打开 App。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "耳机") var device: TrackedDeviceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let observedAt = Date()
        try TrackerStore.shared.recordConnection(kind: .start, deviceID: device.id, at: observedAt)
        await NotificationService.shared.awaitPendingOperations()
        return .result(dialog: "开始时间已记录。")
    }
}

struct RecordDisconnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "记录耳机断开"
    static var description = IntentDescription("用于蓝牙断开个人自动化。保存结束边界并自动汇总完整记录。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "耳机") var device: TrackedDeviceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let observedAt = Date()
        try TrackerStore.shared.recordConnection(kind: .end, deviceID: device.id, at: observedAt)
        await NotificationService.shared.awaitPendingOperations()
        return .result(dialog: "断开时间已记录。")
    }
}

struct RecordBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = "记录耳机电量"
    static var description = IntentDescription("保存快捷指令提供的电量。此动作本身不能读取系统 AirPods 电量；未知部件请留空。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "耳机") var device: TrackedDeviceEntity
    @Parameter(title: "左耳百分比") var left: Int?
    @Parameter(title: "右耳百分比") var right: Int?
    @Parameter(title: "盒子百分比") var caseLevel: Int?
    @Parameter(title: "读数时间（未知则留空）") var measuredAt: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try TrackerStore.shared.recordBattery(deviceID: device.id, left: left, right: right,
                                             caseLevel: caseLevel, measuredAt: measuredAt, source: .companion)
        return .result(dialog: "电量快照已保存。")
    }
}

struct MarkCaseChargedIntent: AppIntent {
    static var title: LocalizedStringResource = "记录盒子充满"
    static var description = IntentDescription("由你确认盒子已经充满后使用，不会自动检测充电完成。")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "耳机") var device: TrackedDeviceEntity
    @Parameter(title: "允许结束旧观察并重开", default: false) var restartExisting: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TrackerStore.shared
        let hasActive = store.state.observations.contains { $0.deviceID == device.id && $0.endAt == nil }
        if hasActive && !restartExisting {
            throw TrackerError("已有充电观察。请在 App 记录补电，或明确启用“允许结束旧观察并重开”。")
        }
        let now = Date()
        try store.charge(hasActive ? .topUpAndRestart : .startFull, deviceID: device.id, at: now,
                         reason: hasActive ? "盒子充满后重新观察" : nil, fullOnRestart: hasActive)
        return .result(dialog: "充电记录已保存。")
    }
}

struct TrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordConnectionIntent(), phrases: ["用\(.applicationName)记录耳机连接"],
                    shortTitle: "记录连接", systemImageName: "headphones")
        AppShortcut(intent: RecordDisconnectionIntent(), phrases: ["用\(.applicationName)记录耳机断开"],
                    shortTitle: "记录断开", systemImageName: "pause.circle")
        AppShortcut(intent: RecordBatteryIntent(), phrases: ["用\(.applicationName)记录耳机电量"],
                    shortTitle: "记录电量", systemImageName: "battery.100")
        AppShortcut(intent: MarkCaseChargedIntent(), phrases: ["用\(.applicationName)记录盒子充满"],
                    shortTitle: "盒子充满", systemImageName: "battery.100.bolt")
    }
}
