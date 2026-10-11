import SwiftUI
import UIKit
import TrackerCore

@MainActor
struct ObservationEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let action: ChargeAction
    var onSaved: (ChargeObservation?) -> Void = { _ in }
    @State private var at = Date()
    @State private var reason = "主动结束"
    @State private var note = ""
    @State private var confirmedFull = false
    @State private var error: String?
    private var title: String {
        switch action { case .startFull: return "盒子已充满"; case .startNow: return "开始观察"; case .topUpAndRestart: return "记录补电"; case .end: return "结束观察" }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("时间") { DatePicker("操作时间", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                if action == .startFull {
                    Section {
                        Toggle("我已确认盒子电量为 100%", isOn: $confirmedFull)
                        Text("保存会建立盒子 100% 的手动快照，左右耳电量保持未知。").font(.footnote).foregroundStyle(.secondary)
                        if store.activeObservation != nil { Text("当前观察会在此结束，并从已充满的盒子开始新观察。").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if action == .end {
                    Section("结束原因") {
                        Picker("原因", selection: $reason) {
                            ForEach(["主动结束", "盒子没电", "记录中断", "其他"], id: \.self) { Text($0).tag($0) }
                        }
                        if reason == "盒子没电" { Text("选择此项表示你确认盒子电量为 0%，会同时建立手动快照。").font(.footnote).foregroundStyle(APStyle.warning) }
                        if reason == "其他" { TextField("请填写原因", text: $note, axis: .vertical) }
                    }
                } else if action == .topUpAndRestart {
                    Section {
                        Text("在这个时刻结束当前观察，并开始新观察。不会把补电后的电量自动写成 100%。")
                        TextField("补电与使用条件（可选）", text: $note, axis: .vertical)
                    }
                } else {
                    Section("开始原因") {
                        Text(action == .startFull ? "从已确认充满的盒子开始" : "从选定时间开始记录；起点电量可以未知")
                    }
                }
                if let observation = store.activeObservation {
                    Section("当前观察") {
                        LabeledContent("开始", value: UIFormat.date(observation.startAt))
                        ObservationMetricsView(observation: observation)
                        Text("允许保留缺测与待核对记录结束观察，报告会显示这些条件。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("确认保存", action: save).frame(maxWidth: .infinity, minHeight: 44).disabled((action == .startFull && !confirmedFull) || (action == .end && reason == "其他" && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.frame(minHeight: 44) } }
        }
    }
    private func save() {
        let endingID = store.activeObservation?.id
        do {
            let finalReason: String? = action == .end ? (reason == "其他" ? note : reason) : (note.isEmpty ? nil : note)
            if action == .startFull { try store.markCaseFull(at: at) }
            else { try store.charge(action, at: at, reason: finalReason) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            let ended = endingID.flatMap { id in store.state.observations.first { $0.id == id && $0.endAt != nil } }
            onSaved(ended)
            dismiss()
        } catch { self.error = "本次操作未保存：\(error.localizedDescription)" }
    }
}
