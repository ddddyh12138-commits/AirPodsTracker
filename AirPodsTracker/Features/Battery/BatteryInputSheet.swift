import SwiftUI
import UIKit
import TrackerCore

@MainActor
struct BatteryInputSheet: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var left: String
    @State private var right: String
    @State private var caseLevel: String
    @State private var measuredAt: Date
    @State private var timeKnown: Bool
    @State private var error: String?
    let source: BatterySource
    init(initialLeft: Int? = nil, initialRight: Int? = nil, initialCase: Int? = nil, initialMeasuredAt: Date? = Date(), source: BatterySource = .manual) {
        _left = State(initialValue: initialLeft.map(String.init) ?? "")
        _right = State(initialValue: initialRight.map(String.init) ?? "")
        _caseLevel = State(initialValue: initialCase.map(String.init) ?? "")
        _measuredAt = State(initialValue: initialMeasuredAt ?? Date())
        _timeKnown = State(initialValue: initialMeasuredAt != nil)
        self.source = source
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if source == .screenshot { Text("请对照原图确认数字与部件。识别建议可以修改，无法确定的部件请留空。").foregroundStyle(.secondary) }
                    field("左耳", text: $left)
                    field("右耳", text: $right)
                    field("充电盒", text: $caseLevel)
                } header: { Text("电量百分比") } footer: { Text("填写 0–100 的整数；至少填写一个部件。空白表示未知。") }
                Section("读数时间") {
                    Toggle("知道读数时间", isOn: $timeKnown)
                    if timeKnown { DatePicker("时间", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute]) }
                    Text(timeKnown ? "请填写电量被读取时的时间，旧截图请使用截图对应时间。" : "保存后保留“读数时间未知”；保存时间不会代替读数时间。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section { LabeledContent("来源", value: UIFormat.source(source)) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("确认并保存", action: save).frame(maxWidth: .infinity, minHeight: 44).disabled(store.device == nil) }
            }.navigationTitle(source == .screenshot ? "确认电量" : "记录电量")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.frame(minHeight: 44) } }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("未知", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityLabel("\(title)电量百分比")
            Text("%").foregroundStyle(.secondary)
        }.frame(minHeight: 44)
    }
    private func parse(_ raw: String, title: String) throws -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard let number = Int(value), (0...100).contains(number) else { throw TrackerError("\(title)需要填写 0–100 的整数。") }
        return number
    }
    private func save() {
        do {
            try store.recordBattery(left: parse(left, title: "左耳"), right: parse(right, title: "右耳"), caseLevel: parse(caseLevel, title: "充电盒"), measuredAt: timeKnown ? measuredAt : nil, source: source)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch { self.error = "本次记录未保存：\(error.localizedDescription)" }
    }
}
