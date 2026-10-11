import SwiftUI
import TrackerCore

@MainActor
struct AutomationSetupView: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = 0
    @State private var name = ""
    @State private var model = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(step + 1) 步，共 3 步").font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: Double(step + 1), total: 3)
                }.padding()
                Form {
                    switch step {
                    case 0: introduction
                    case 1: deviceForm
                    default: automationSteps
                    }
                }
                .scrollContentBackground(.hidden)
                .background(APStyle.background)
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("上一步") { step -= 1 }.buttonStyle(.bordered)
                    }
                    Button(step == 2 ? "完成" : (step == 1 ? "保存设备并继续" : "开始设置")) {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(step == 1 && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding()
            }
            .navigationTitle("设置自动记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍后设置") { dismiss() } }
            }
            .onAppear { loadDevice() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { store.reload() } }
            .alert("设备未保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var introduction: some View {
        Group {
            Section {
                Label("首次设置两条自动化", systemImage: "bolt.circle.fill").font(.headline)
                Text("连接时记开始，断开时记结束。设置后日常无需手填，完整记录会自动计入统计。")
            }
            Section("记录的含义") {
                Text("记录反映快捷指令动作的执行时间，不代表实际佩戴、播放或电量。")
                Text("系统状态可能影响自动化执行。若漏了一端，App 会保留已收到的信息，并提示核对。")
            }
            Section("电量单独记录") {
                Text("电量可以手填或从截图提取。连接动作不会读取 AirPods 的实时电量，也不会凭连接时长推算电量。")
            }
        }
    }

    private var deviceForm: some View {
        Group {
            if store.state.devices.count > 1 {
                Section("当前设备") {
                    Picker("设备", selection: $store.selectedDeviceID) {
                        ForEach(store.state.devices) { device in Text(device.name).tag(Optional(device.id)) }
                    }.onChange(of: store.selectedDeviceID) { _, _ in loadDevice() }
                }
            }
            Section {
                TextField("例如：我的 AirPods", text: $name)
                    .textInputAutocapitalization(.never)
                TextField("型号（可不填）", text: $model)
            } header: {
                Text("给耳机起个名字")
            } footer: {
                Text("不知道型号也可以使用。不需要序列号或蓝牙地址。这里的设备名称将在本 App 的快捷指令动作中供你选择。")
            }
            Section {
                Text("下一步请在系统快捷指令中选择实际蓝牙耳机，并让两个动作都使用这里的同一设备。")
            }
        }
    }

    private var automationSteps: some View {
        Group {
            Section("1 · 连接时记开始") {
                Text("打开「快捷指令」→「自动化」→ 新建「蓝牙」自动化。")
                Text("选择你的耳机和「连接时」，选择「立即运行」。")
                Text("添加本 App 的「记录耳机连接」动作，将设备设为「\(store.device?.name ?? name)」，保存。")
            }
            Section {
                Text("再创建一条同一耳机的「断开时」蓝牙自动化，选择「立即运行」。")
                Text("添加本 App 的「记录耳机断开」动作，选择同一个设备，保存。")
            } header: {
                Text("2 · 断开时记结束")
            } footer: {
                Text("个人自动化必须由你在系统中建立，App 无法替你安装。不同 iOS 版本的文案可能略有差别，请以手机界面为准。")
            }
            Section {
                Text("先实际连接耳机，再实际断开一次，然后回到此页核对时间。")
                eventStatus(kind: .start, title: "连接动作")
                eventStatus(kind: .end, title: "断开动作")
                Button("刷新接收记录", systemImage: "arrow.clockwise") { store.reload() }
            } header: {
                Text("3 · 实际连接、断开后核对")
            } footer: {
                Text("「动作收到」只确认数据已保存。App 无法检查自动化是否已设置，也无法区分蓝牙触发和你手动运行动作；请用刚才实际连接、断开的时间来核对。")
            }
            Section("之后怎样使用") {
                Text("正常的开始、结束记录会自动配对。没有结束时先显示「等待断开记录」；超过 12 小时仍缺结束，才提示核对。")
                Text("完成此页不会宣称蓝牙自动化已验证。锁屏、后台与强制退出后的执行情况，需要在你的 iPhone 上实际确认。")
            }
        }
    }

    private func eventStatus(kind: EventKind, title: String) -> some View {
        let event = store.state.events.filter {
            $0.deviceID == store.device?.id && $0.source == .shortcut && $0.kind == kind
        }.max { $0.observedAt < $1.observedAt }
        return VStack(alignment: .leading, spacing: 6) {
            Label(event == nil ? "\(title)尚未收到" : "\(title)收到", systemImage: event == nil ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(event == nil ? Color.secondary : APStyle.accent)
            if let event {
                Text(event.observedAt.formatted(date: .abbreviated, time: .standard)).font(.footnote)
                Text("时间来自自动化动作执行").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }

    private func loadDevice() {
        name = store.device?.name ?? ""
        model = store.device?.model ?? ""
    }

    private func advance() {
        if step == 2 { dismiss(); return }
        if step == 1 {
            do {
                let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.device == nil {
                    try store.addDevice(name: name, model: cleanModel.isEmpty ? nil : cleanModel)
                } else {
                    try store.updateDevice(name: name, model: cleanModel.isEmpty ? nil : cleanModel)
                }
            } catch { errorMessage = error.localizedDescription; return }
        }
        step += 1
    }
}
