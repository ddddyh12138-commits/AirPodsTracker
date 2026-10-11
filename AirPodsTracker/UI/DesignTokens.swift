import SwiftUI
import UIKit
import TrackerCore

enum APStyle {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.051, green: 0.071, blue: 0.098, alpha: 1) : UIColor(red: 0.957, green: 0.965, blue: 0.980, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.129, blue: 0.176, alpha: 1) : .white })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.475, green: 0.682, blue: 1, alpha: 1) : UIColor(red: 0.094, green: 0.373, blue: 0.784, alpha: 1) })
    static let warning = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.773, blue: 0.451, alpha: 1) : UIColor(red: 0.573, green: 0.318, blue: 0, alpha: 1) })
    static let blue = Color(red: 0.094, green: 0.373, blue: 0.784)
    static let ring = LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct APCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(APStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }
}

extension View {
    func apCard() -> some View { modifier(APCard()) }
    func apPage() -> some View { background(APStyle.background.ignoresSafeArea()) }
}

struct APPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white).background(APStyle.blue.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

enum UIFormat {
    static func duration(_ value: TimeInterval) -> String {
        let minutes = max(0, Int(value / 60))
        if value > 0 && minutes == 0 { return "不足 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(minutes % 60) 分"
    }
    static func date(_ value: Date) -> String { value.formatted(date: .abbreviated, time: .shortened) }
    static func time(_ value: Date?) -> String { value?.formatted(date: .omitted, time: .shortened) ?? "未知" }
    static func source(_ value: BatterySource) -> String {
        switch value { case .manual: return "手动记录"; case .screenshot: return "截图确认"; case .companion: return "外部来源" }
    }
    static func source(_ value: EventSource) -> String { value == .shortcut ? "自动化" : "手动记录" }
    static func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
    static func status(_ status: SessionStatus) -> String {
        switch status { case .confirmed: return "已计入"; case .awaitingEnd: return "等待断开"; case .needsReview: return "待核对"; case .excluded: return "已排除" }
    }
}

enum UISessionMetrics {
    static func includes(_ session: UsageSession, in range: DateInterval) -> Bool {
        if let start = session.start, let end = session.end, end > start { return start < range.end && end > range.start }
        guard let known = session.start ?? session.end else { return false }
        return known >= range.start && known < range.end
    }
    static func count(_ sessions: [UsageSession], in range: DateInterval) -> Int {
        sessions.filter { $0.status == .confirmed && includes($0, in: range) }.count
    }
    static func review(_ sessions: [UsageSession], in range: DateInterval) -> Int {
        sessions.filter { $0.status == .needsReview && includes($0, in: range) }.count
    }
    static func range(_ observation: ChargeObservation, now: Date = Date()) -> DateInterval {
        DateInterval(start: observation.startAt, end: max(observation.startAt, observation.endAt ?? now))
    }
}

struct UIBatteryReading {
    let value: Int
    let snapshot: BatterySnapshot
    static func latest(_ snapshots: [BatterySnapshot], deviceID: UUID?, value: KeyPath<BatterySnapshot, Int?>) -> UIBatteryReading? {
        // Order by the recorded entry, while preserving the original reading time visibly.
        snapshots.filter { $0.deviceID == deviceID && $0.userConfirmed && $0[keyPath: value] != nil }
            .max(by: { $0.importedAt < $1.importedAt })
            .flatMap { snapshot in snapshot[keyPath: value].map { UIBatteryReading(value: $0, snapshot: snapshot) } }
    }
}

@MainActor
struct EmptyStateView: View {
    let title: String
    let detail: String
    var symbol: String = "waveform.path"
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(APStyle.accent).accessibilityHidden(true)
            Text(title).font(.title3.bold())
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }
}

@MainActor
struct RecordStatusCapsule: View {
    let title: String
    var warning = false
    var body: some View {
        Label(title, systemImage: warning ? "exclamationmark.circle" : "checkmark.circle")
            .font(.subheadline.weight(.medium)).foregroundStyle(warning ? APStyle.warning : APStyle.accent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background((warning ? APStyle.warning : APStyle.accent).opacity(0.12), in: Capsule())
    }
}

@MainActor
struct UIMetric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
