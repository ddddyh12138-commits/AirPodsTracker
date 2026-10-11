import SwiftUI
import TrackerCore

@MainActor
struct DashboardView: View {
    @EnvironmentObject private var store: TrackerStore
    @Binding var selectedTab: Int
    @State private var settings = false
    @State private var setup = false
    @State private var manual = false
    @State private var concise = false
    private var lastSession: UsageSession? { store.sessions.filter { $0.status != .excluded }.max { ($0.start ?? $0.end ?? .distantPast) < ($1.start ?? $1.end ?? .distantPast) } }
    private var lastComplete: UsageSession? { store.sessions.filter { $0.status == .confirmed }.max { ($0.end ?? .distantPast) < ($1.end ?? .distantPast) } }
    private var latestEvent: ConnectionEvent? { store.state.events.filter { $0.deviceID == store.device?.id }.max { $0.observedAt < $1.observedAt } }
    private var hasAutomationEvidence: Bool {
        let events = store.state.events.filter { $0.deviceID == store.device?.id && $0.source == .shortcut }
        return events.contains { $0.kind == .start } && events.contains { $0.kind == .end }
    }
    private var today: DateInterval { Calendar.current.dateInterval(of: .day, for: Date())! }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.device?.name ?? "我的耳机").font(.title2.bold())
                    if let event = latestEvent {
                        RecordStatusCapsule(title: "最近收到\(event.kind == .start ? "连接" : "断开") · \(UIFormat.date(event.observedAt))")
                    } else { Text("还没有收到连接记录").foregroundStyle(.secondary) }
                }
                if !hasAutomationEvidence {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("完成两步设置，开始自动记录", systemImage: "bolt.badge.clock").font(.headline)
                        Text("首次设置连接与断开自动化；正常记录会自动配对。").font(.subheadline).foregroundStyle(.secondary)
                        Button("设置自动记录") { setup = true }.buttonStyle(APPrimaryButtonStyle())
                    }.apCard()
                }
                VStack(spacing: 20) {
                    if concise {
                        UIMetric(label: "今日已记录连接", value: UIFormat.duration(store.todayDuration))
                    } else {
                        DualDurationRing(title: ringTitle, value: ringValue, detail: ringDetail, awaitingEnd: lastSession?.status == .awaitingEnd)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) { totals }
                        VStack(alignment: .leading, spacing: 16) { totals }
                    }
                    HStack {
                        Button("查看记录") { selectedTab = 1 }.frame(minHeight: 44)
                        Spacer()
                        Button(concise ? "显示双环" : "简洁视图") { concise.toggle() }.frame(minHeight: 44)
                    }.font(.subheadline.weight(.medium))
                }.apCard()
                HStack(spacing: 12) {
                    UIMetric(label: "今日连接", value: "\(UISessionMetrics.count(store.sessions, in: today)) 段")
                    Button { selectedTab = 1 } label: {
                        UIMetric(label: "待核对", value: "\(store.reviewCount) 条 ›")
                    }.buttonStyle(.plain).foregroundStyle(store.reviewCount > 0 ? APStyle.warning : .primary).frame(minHeight: 44)
                }.apCard()
                if let lastSession, lastSession.status == .needsReview {
                    NavigationLink { SessionDetailView(session: lastSession) } label: {
                        Label("核对这段记录", systemImage: "exclamationmark.circle").frame(maxWidth: .infinity, minHeight: 44)
                    }.foregroundStyle(APStyle.warning).apCard()
                }
                BatteryReadingsView()
                if let observation = store.activeObservation {
                    Button { selectedTab = 3 } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("当前充电观察", systemImage: "battery.100.bolt").font(.headline)
                            Text("\(UIFormat.date(observation.startAt)) 开始").font(.subheadline).foregroundStyle(.secondary)
                            Text("查看观察 ›").font(.subheadline)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).apCard()
                }
                VStack(spacing: 10) {
                    Button("补录连接记录") { manual = true }.buttonStyle(APPrimaryButtonStyle()).disabled(store.device == nil)
                    Button("记录充电") { selectedTab = 3 }.frame(maxWidth: .infinity, minHeight: 44)
                }
                Text("连接记录不等于佩戴或播放时长。电量是历史快照。").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.apPage().navigationTitle("总览")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }.accessibilityLabel("设置") } }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $setup) { AutomationSetupView() }
            .sheet(isPresented: $manual) { SessionEditor(session: nil) }
    }
    @ViewBuilder private var totals: some View {
        UIMetric(label: "今日已记录连接", value: UIFormat.duration(store.todayDuration))
        UIMetric(label: "本次观察已记录连接", value: store.activeObservation.map { UIFormat.duration(IntervalMath.confirmedDuration(sessions: store.sessions, in: UISessionMetrics.range($0))) } ?? "尚未开始")
    }
    private var ringTitle: String {
        if lastSession?.status == .awaitingEnd { return "开始已记录" }
        return lastComplete == nil ? "连接记录" : "上次完整连接段"
    }
    private var ringValue: String {
        if lastSession?.status == .awaitingEnd { return "等待断开记录" }
        if let session = lastComplete, let start = session.start, let end = session.end { return UIFormat.duration(end.timeIntervalSince(start)) }
        return "等待第一段记录"
    }
    private var ringDetail: String {
        if lastSession?.status == .awaitingEnd { return "开始时间 \(UIFormat.time(lastSession?.start)) · 断开记录到达后自动计入" }
        return lastComplete == nil ? "完成一次连接与断开后，时长会显示在这里。" : "只累计已确认的闭合连接区间。"
    }
}

@MainActor
struct BatteryReadingsView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var manual = false
    @State private var screenshot = false
    @State private var selected: BatterySnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近电量记录").font(.headline)
            reading("左耳", keyPath: \.left)
            reading("右耳", keyPath: \.right)
            reading("充电盒", keyPath: \.caseLevel)
            Text("每个部件保留最近录入的读数及其原始时间，不代表实时电量。").font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("手动记录") { manual = true }.frame(minHeight: 44)
                Spacer()
                Button("截图识别") { screenshot = true }.frame(minHeight: 44)
            }.disabled(store.device == nil)
        }.apCard()
            .sheet(isPresented: $manual) { BatteryInputSheet() }
            .sheet(isPresented: $screenshot) { BatteryImportView() }
            .sheet(item: $selected) { snapshot in BatterySnapshotDetail(snapshot: snapshot) }
    }
    @ViewBuilder private func reading(_ title: String, keyPath: KeyPath<BatterySnapshot, Int?>) -> some View {
        if let reading = UIBatteryReading.latest(store.state.batteries, deviceID: store.device?.id, value: keyPath) {
            Button { selected = reading.snapshot } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(title); Spacer(); Text("\(reading.value)%").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit() }
                    Text("\(UIFormat.source(reading.snapshot.source)) · \(reading.snapshot.measuredAt.map(UIFormat.date) ?? "读数时间未知")")
                        .font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityHint("查看该快照的来源和保存时间")
        } else {
            HStack { Text(title); Spacer(); Text("—").font(.title3); Text("尚无读数").foregroundStyle(.secondary).font(.footnote) }
                .accessibilityElement(children: .combine)
        }
    }
}

@MainActor
struct BatterySnapshotDetail: View {
    let snapshot: BatterySnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("该次记录") {
                    LabeledContent("左耳", value: UIFormat.percent(snapshot.left))
                    LabeledContent("右耳", value: UIFormat.percent(snapshot.right))
                    LabeledContent("充电盒", value: UIFormat.percent(snapshot.caseLevel))
                }
                Section("来源与时间") {
                    LabeledContent("来源", value: UIFormat.source(snapshot.source))
                    LabeledContent("读数时间", value: snapshot.measuredAt.map(UIFormat.date) ?? "未知")
                    LabeledContent("保存时间", value: UIFormat.date(snapshot.importedAt))
                    Text("这是历史电量快照；未知值保留为空，不按 0% 处理。").foregroundStyle(.secondary)
                }
            }.navigationTitle("电量快照").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.frame(minHeight: 44) } }
        }
    }
}
