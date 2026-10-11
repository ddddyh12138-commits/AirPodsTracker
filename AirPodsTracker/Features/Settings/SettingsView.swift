import SwiftUI
import UniformTypeIdentifiers
import UIKit
import TrackerCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("reviewRemindersEnabled") private var reviewRemindersEnabled = false
    @ObservedObject private var notifications = NotificationService.shared
    @State private var showsSetup = false
    @State private var showsImporter = false
    @State private var isReadingBackup = false
    @State private var requestingNotifications = false
    @State private var notificationsAllowed = false
    @State private var errorMessage: String?
    @State private var restoreError: String?
    @State private var export: SettingsExport?
    @State private var backup: SettingsBackupPreview?

    var body: some View {
        NavigationStack {
            Form {
                Section("设备与自动记录") {
                    if store.state.devices.count > 1 {
                        Picker("当前设备", selection: $store.selectedDeviceID) {
                            ForEach(store.state.devices) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if let device = store.device {
                        LabeledContent("昵称", value: device.name)
                        LabeledContent("型号", value: device.model ?? "尚不确定")
                    }
                    Button(store.device == nil ? "建立设备与设置自动记录" : "编辑设备与自动化自检", systemImage: "bolt.circle") { showsSetup = true }
                }
                Section("外观") {
                    Picker("配色", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("深色").tag("dark")
                        Text("浅色").tag("light")
                    }
                    Text("动态效果跟随系统的「减弱动态效果」设置。").font(.footnote).foregroundStyle(.secondary)
                }
                reminderSection
                Section {
                    Button("导出完整备份（JSON）", systemImage: "square.and.arrow.up") { exportFile(csv: false) }
                    Button("导出连接记录（CSV）", systemImage: "tablecells") { exportFile(csv: true) }
                    Button("从 JSON 备份恢复", systemImage: "square.and.arrow.down") { showsImporter = true }
                        .disabled(isReadingBackup)
                    if isReadingBackup { ProgressView("正在读取备份…") }
                } header: {
                    Text("数据")
                } footer: {
                    Text("JSON 包含设备、事件、修正、电量、充电观察和动作回执，可用于恢复。CSV 适合查看和分析，不能用于恢复。")
                }
                Section("电量与隐私") {
                    Text("电量来自手动确认或你选择的截图，不是持续更新的实时电量。截图仅在本机临时处理，不保留原图。")
                    Text("记录保存在本机，无需账号。导出后由你在系统分享面板选择去向，文件会包含设备名称和记录时间。")
                    Text("连接记录不等于佩戴、播放或电池健康。没有结束证据时，不会把经过的时间计入已确认时长。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(APStyle.background)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showsSetup) { AutomationSetupView().environmentObject(store) }
            .sheet(item: $export) { ShareSheet(items: [$0.url]) }
            .sheet(item: $backup) { preview in backupSheet(preview) }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                readBackup(result)
            }
            .alert("操作未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .task { notificationsAllowed = await notifications.authorizationAllowed() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { notificationsAllowed = await notifications.authorizationAllowed() } }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("记录核对提醒", isOn: Binding(get: { reviewRemindersEnabled }, set: setReminders))
                .disabled(requestingNotifications)
            if requestingNotifications { ProgressView("正在请求通知权限…") }
            if reviewRemindersEnabled && !notificationsAllowed {
                Text("系统通知未开启，暂时无法发送提醒。").foregroundStyle(APStyle.warning)
                Link("前往系统设置", destination: URL(string: UIApplication.openSettingsURLString)!)
            }
            if let message = notifications.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("可选提醒")
        } footer: {
            Text("默认关闭。开启后，新收到的连接记录会在 12 小时 1 分钟后提醒核对；收到该设备的断开记录时取消。系统发出通知前不一定能再次检查数据，因此提醒只表示可能缺少结束记录，不代表你持续佩戴了耳机。")
        }
    }

    private func setReminders(_ enabled: Bool) {
        reviewRemindersEnabled = enabled
        if !enabled { notifications.cancelPending(); return }
        requestingNotifications = true
        Task { @MainActor in
            notificationsAllowed = await notifications.requestAuthorization()
            requestingNotifications = false
        }
    }

    private func exportFile(csv: Bool) {
        do {
            let url = try (csv ? store.exportCSV() : store.exportBackup())
            export = SettingsExport(url: url)
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func readBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            isReadingBackup = true
            Task { @MainActor in
                defer { isReadingBackup = false }
                do {
                    let loaded = try await Task.detached(priority: .userInitiated) {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let state = try JSONDecoder().decode(TrackerState.self, from: data)
                        guard state.schemaVersion == 1 else { throw TrackerError("此备份的格式版本不受支持，请保留原文件。") }
                        return SettingsLoadedBackup(data: data, state: state)
                    }.value
                    restoreError = nil
                    backup = SettingsBackupPreview(data: loaded.data, state: loaded.state,
                                                   conflicts: conflictCount(in: loaded.state, local: store.state))
                } catch { errorMessage = "无法读取备份：\(error.localizedDescription)" }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func backupSheet(_ preview: SettingsBackupPreview) -> some View {
        NavigationStack {
            Form {
                Section("备份内容") {
                    countRow("设备", preview.state.devices.count)
                    countRow("原始连接事件", preview.state.events.count)
                    countRow("记录修正", preview.state.corrections.count)
                    countRow("电量快照", preview.state.batteries.count)
                    countRow("充电观察", preview.state.observations.count)
                    countRow("充电动作回执", preview.state.receipts.count)
                }
                Section("合并方式") {
                    Text("按记录 ID 合并；相同内容跳过，相同 ID 但内容不同的记录保留本机版本。")
                    countRow("同 ID 内容冲突", preview.conflicts)
                    Text("确认后会完整校验并一次性保存；校验或保存失败时，原有数据保持不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("确认恢复") {
                        do {
                            try store.importBackup(data: preview.data)
                            backup = nil
                        } catch {
                            restoreError = "恢复失败：\(error.localizedDescription)"
                        }
                    }.buttonStyle(.borderedProminent)
                }
                if let restoreError {
                    Section { Text(restoreError).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(APStyle.background)
            .navigationTitle("恢复前核对")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { backup = nil } } }
        }
    }

    private func countRow(_ title: String, _ value: Int) -> some View {
        LabeledContent(title) { Text(value.formatted()).monospacedDigit() }
    }

    private func conflictCount(in incoming: TrackerState, local: TrackerState) -> Int {
        conflicts(incoming.devices, local.devices) + conflicts(incoming.events, local.events)
        + conflicts(incoming.corrections, local.corrections) + conflicts(incoming.batteries, local.batteries)
        + conflicts(incoming.observations, local.observations) + conflicts(incoming.receipts, local.receipts)
    }

    private func conflicts<T: Identifiable & Equatable>(_ incoming: [T], _ local: [T]) -> Int where T.ID: Hashable {
        let current = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return incoming.filter { item in current[item.id].map { $0 != item } ?? false }.count
    }
}

private struct SettingsExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SettingsLoadedBackup: Sendable {
    let data: Data
    let state: TrackerState
}

private struct SettingsBackupPreview: Identifiable {
    let id = UUID()
    let data: Data
    let state: TrackerState
    let conflicts: Int
}
