import SwiftUI
import UIKit
import TrackerCore

@MainActor
struct SessionEditor: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let session: UsageSession?
    @State private var start: Date?
    @State private var end: Date?
    @State private var tag: String
    @State private var note: String
    @State private var confirmLong = false
    @State private var error: String?
    init(session: UsageSession?) {
        self.session = session
        _start = State(initialValue: session?.start)
        _end = State(initialValue: session?.end)
        _tag = State(initialValue: session?.tag ?? "")
        _note = State(initialValue: session?.note ?? "")
    }
    private var longSpan: Bool { if let start, let end { return end.timeIntervalSince(start) > 12 * 3600 }; return false }
    private var anchor: Date { session?.start ?? session?.end ?? Date() }
    private var neighbors: [UsageSession] {
        Array(store.sessions.filter { $0.id != session?.id && $0.status != .excluded }
            .sorted { abs(($0.start ?? $0.end ?? .distantPast).timeIntervalSince(anchor)) < abs(($1.start ?? $1.end ?? .distantPast).timeIntervalSince(anchor)) }.prefix(3))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OptionalBoundaryField(title: "开始时间", value: $start, suggestion: end)
                    OptionalBoundaryField(title: "结束时间", value: $end, suggestion: start)
                    if let start, let end {
                        if end > start { LabeledContent("区间跨度", value: UIFormat.duration(end.timeIntervalSince(start))) }
                        else { Text("结束时间必须晚于开始时间。").foregroundStyle(.red) }
                    }
                } header: { Text("确认连接边界") } footer: {
                    Text("未知端点不会自动填成现在。只填写你能确认的时间；保存后标记为手动记录或用户修正。")
                }
                if longSpan {
                    Section("长跨度核对") {
                        Text("这段超过 12 小时。请检查是否漏记断开或包含不相连的时段；有间断时应分段补录。").foregroundStyle(APStyle.warning)
                        Toggle("我已核对这段完整连接区间", isOn: $confirmLong)
                    }
                }
                Section("手动备注") {
                    Picker("活动标签", selection: $tag) {
                        Text("不设置").tag("")
                        ForEach(["通勤", "工作", "运动", "其他"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(3...6)
                }
                if !neighbors.isEmpty {
                    Section("相邻记录，供核对") {
                        ForEach(neighbors) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.start.map(UIFormat.date) ?? "开始未知") → \(item.end.map(UIFormat.date) ?? "结束未知")")
                                Text(UIFormat.status(item.status)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(start == nil || end == nil ? "请先选择开始和结束时间" : "保存记录", action: save)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(start == nil || end == nil || (start != nil && end != nil && end! <= start!) || (longSpan && !confirmLong))
                }
            }.navigationTitle(session == nil ? "补录连接" : "核对连接记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.frame(minHeight: 44) } }
        }
    }
    private func save() {
        guard let start, let end else { return }
        do {
            if let session { try store.correctSession(session, start: start, end: end, tag: tag.isEmpty ? nil : tag, note: note.isEmpty ? nil : note, confirmLong: confirmLong) }
            else { try store.addManualSession(start: start, end: end, tag: tag.isEmpty ? nil : tag, note: note.isEmpty ? nil : note) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = "本次记录未保存：\(error.localizedDescription)" }
    }
}

@MainActor
struct OptionalBoundaryField: View {
    let title: String
    @Binding var value: Date?
    var suggestion: Date?
    @State private var choosing = false
    @State private var draft = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title, value: value.map(UIFormat.date) ?? "尚未选择")
            HStack {
                Button(value == nil ? "选择时间" : "修改时间") {
                    draft = value ?? suggestion ?? Date()
                    choosing = true
                }.frame(minHeight: 44)
                Spacer()
                Button("设为现在") { value = Date() }.frame(minHeight: 44)
            }.buttonStyle(.borderless)
        }
        .sheet(isPresented: $choosing) {
            NavigationStack {
                Form {
                    DatePicker(title, selection: $draft, in: ...Date(), displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical)
                    Text("点击“确认选择”后才会填入表单。").font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { choosing = false }.frame(minHeight: 44) }
                        ToolbarItem(placement: .confirmationAction) { Button("确认选择") { value = draft; choosing = false }.frame(minHeight: 44) }
                    }
            }
        }
    }
}

@MainActor
struct SessionSplitSheet: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let session: UsageSession
    @State private var splitAt: Date
    @State private var error: String?
    init(session: UsageSession) {
        self.session = session
        let start = session.start ?? .distantPast
        let end = session.end ?? start
        _splitAt = State(initialValue: start.addingTimeInterval(end.timeIntervalSince(start) / 2))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("原始区间") {
                    LabeledContent("开始", value: session.start.map(UIFormat.date) ?? "未知")
                    LabeledContent("结束", value: session.end.map(UIFormat.date) ?? "未知")
                }
                if let start = session.start, let end = session.end, end > start {
                    Section {
                        DatePicker("拆分时刻", selection: $splitAt, in: start...end, displayedComponents: [.date, .hourAndMinute])
                        Text("拆分点必须严格位于开始和结束之间。原记录会保留并排除，两段会作为手动记录保存。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("确认拆分") {
                        do {
                            try store.splitSession(session, at: splitAt)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } catch { self.error = "拆分未保存：\(error.localizedDescription)" }
                    }.frame(maxWidth: .infinity, minHeight: 44).disabled(splitAt <= start || splitAt >= end)
                }
            }.navigationTitle("拆分记录").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.frame(minHeight: 44) } }
        }
    }
}
