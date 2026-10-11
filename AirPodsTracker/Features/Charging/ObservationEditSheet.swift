import SwiftUI
import UIKit
import TrackerCore

@MainActor
struct ObservationEditSheet: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let observation: ChargeObservation
    @State private var start: Date
    @State private var end: Date
    @State private var ended: Bool
    @State private var reason: String
    @State private var note: String
    @State private var errorMessage: String?

    init(observation: ChargeObservation) {
        self.observation = observation
        _start = State(initialValue: observation.startAt)
        _end = State(initialValue: observation.endAt ?? Date())
        _ended = State(initialValue: observation.endAt != nil)
        _reason = State(initialValue: observation.endReason ?? "手动结束")
        _note = State(initialValue: observation.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("观察边界") {
                    DatePicker("开始", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Toggle("观察已结束", isOn: $ended)
                    if ended {
                        DatePicker("结束", selection: $end, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        TextField("结束原因", text: $reason)
                    }
                }
                Section("备注") { TextField("使用条件与说明（可选）", text: $note, axis: .vertical) }
                Section {
                    Text("调整观察只改变连接记录的归属，原始连接事件和电量读数保留。修改时间不会改变已有电量快照的读数时间；重新设为未结束后，原结束快照仅保留为历史记录。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                Section { Button("保存修改", action: save).frame(maxWidth: .infinity, minHeight: 44) }
            }
            .navigationTitle("编辑充电观察").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        var edited = observation
        edited.startAt = start
        edited.endAt = ended ? end : nil
        edited.endReason = ended ? reason.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if !ended { edited.endSnapshotID = nil }
        edited.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        do {
            try store.updateObservation(edited)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { errorMessage = "修改未保存：\(error.localizedDescription)" }
    }
}
