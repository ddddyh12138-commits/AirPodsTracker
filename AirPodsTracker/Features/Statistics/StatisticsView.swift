import SwiftUI
import Charts
import TrackerCore

private struct UIHourValue: Identifiable {
    var id: Int { hour }
    let hour: Int
    let duration: TimeInterval
}

@MainActor
struct StatisticsView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var days = 7
    @State private var selectedDate: Date?
    @State private var showTable = false
    @State private var completeOnly = false
    @State private var definition = false
    private var calendar: Calendar { .current }
    private var range: DateInterval {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        return DateInterval(start: calendar.date(byAdding: .day, value: -days, to: tomorrow)!, end: tomorrow)
    }
    private var daily: [DayDuration] { IntervalMath.dailyDurations(sessions: store.sessions, in: range, calendar: calendar) }
    private var total: TimeInterval { IntervalMath.confirmedDuration(sessions: store.sessions, in: range) }
    private var longest: TimeInterval {
        store.sessions.compactMap { session -> TimeInterval? in
            guard session.status == .confirmed, let start = session.start, let end = session.end else { return nil }
            let clippedStart = max(start, range.start), clippedEnd = min(end, range.end)
            return clippedEnd > clippedStart ? clippedEnd.timeIntervalSince(clippedStart) : nil
        }.max() ?? 0
    }
    private var chosenDay: DayDuration? { selectedDate.flatMap { selected in daily.first { calendar.isDate($0.day, inSameDayAs: selected) } } }
    private var hourly: [UIHourValue] {
        var values = Array(repeating: TimeInterval(0), count: 24)
        var cursor = range.start
        // Calendar hour intervals preserve repeated/skipped local hours during DST changes.
        while cursor < range.end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor), hour.end > cursor else { break }
            let clipped = DateInterval(start: max(cursor, range.start), end: min(hour.end, range.end))
            values[calendar.component(.hour, from: cursor)] += IntervalMath.confirmedDuration(sessions: store.sessions, in: clipped)
            cursor = hour.end
        }
        return (0..<24).map { UIHourValue(hour: $0, duration: values[$0]) }
    }
    private var observations: [ChargeObservation] {
        store.state.observations.filter { observation in
            guard observation.deviceID == store.device?.id, observation.startAt < range.end, (observation.endAt ?? Date()) > range.start else { return false }
            return !completeOnly || summary(observation).conditionLabels == ["起止齐全"]
        }.sorted { $0.startAt > $1.startAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("统计期间", selection: $days) { Text("7 天").tag(7); Text("30 天").tag(30) }.pickerStyle(.segmented)
                    .onChange(of: days) { _, _ in selectedDate = nil }
                Button { definition = true } label: { Label("统计口径：已记录连接", systemImage: "info.circle").font(.subheadline).frame(minHeight: 44) }
                VStack(alignment: .leading, spacing: 16) {
                    Text(UIFormat.duration(total)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) { metrics }
                        VStack(alignment: .leading, spacing: 12) { metrics }
                    }
                    Text("平均每日 \(UIFormat.duration(total / Double(days))) · 按整个所选期间平均，包含无记录日期")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("本期最长单段 \(UIFormat.duration(longest))").font(.subheadline).foregroundStyle(.secondary)
                }.apCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text("每日已记录连接").font(.headline)
                    if total == 0 {
                        EmptyStateView(title: "还没有可计入的连接记录", detail: "未闭合、待核对和已排除的记录不会进入图表。这不表示期间没有使用耳机。", symbol: "chart.bar")
                    } else {
                        Chart(daily) { item in
                            BarMark(x: .value("日期", item.day, unit: .day), y: .value("小时", item.duration / 3600))
                                .foregroundStyle(APStyle.ring).cornerRadius(4)
                                .accessibilityLabel(item.day.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue(UIFormat.duration(item.duration))
                            if let chosenDay, chosenDay.day == item.day {
                                RuleMark(x: .value("选中日期", item.day, unit: .day)).foregroundStyle(APStyle.accent.opacity(0.7))
                            }
                        }.chartXSelection(value: $selectedDate).chartYAxisLabel("小时")
                            .chartXAxis { AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in AxisValueLabel(format: .dateTime.month().day()) } }
                            .frame(height: 220)
                        Text("点按或拖动图表查看某一天，也可以展开下方表格。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let item = chosenDay, let interval = calendar.dateInterval(of: .day, for: item.day) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.day.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                            Text(item.duration == 0 ? "该日没有可计入的连接记录" : UIFormat.duration(item.duration))
                            Text("\(UISessionMetrics.count(store.sessions, in: interval)) 段 · \(UISessionMetrics.review(store.sessions, in: interval)) 条待核对").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("每日明细表") {
                        ForEach(daily) { item in
                            LabeledContent(item.day.formatted(date: .abbreviated, time: .omitted), value: UIFormat.duration(item.duration)).font(.subheadline).padding(.vertical, 6)
                        }
                    }
                }.apCard()
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("分时分布").font(.headline)
                        Spacer()
                        Button(showTable ? "显示图表" : "查看表格") { showTable.toggle() }.font(.subheadline).frame(minHeight: 44)
                    }
                    if showTable {
                        ForEach(hourly) { item in LabeledContent(String(format: "%02d:00–%02d:00", item.hour, item.hour + 1), value: UIFormat.duration(item.duration)).font(.subheadline) }
                    } else if total > 0 {
                        Chart(hourly) { item in
                            BarMark(x: .value("时段", item.hour), y: .value("分钟", item.duration / 60))
                                .foregroundStyle(APStyle.accent)
                                .accessibilityLabel("\(item.hour)点到\(item.hour + 1)点")
                                .accessibilityValue(UIFormat.duration(item.duration))
                        }.chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) }
                            .chartYAxisLabel("分钟").frame(height: 170)
                    } else { Text("有已确认记录后，将按本地小时展示实际交集。").foregroundStyle(.secondary) }
                    Text("按当前时区分组，跨日区间拆分到实际日期与小时。").font(.footnote).foregroundStyle(.secondary)
                }.apCard()
                VStack(alignment: .leading, spacing: 16) {
                    Text("充电观察对比").font(.headline)
                    Toggle("仅显示起止电量齐全、无补电且无待核对的观察", isOn: $completeOnly).font(.subheadline)
                    if observations.isEmpty { Text("本期没有符合条件的充电观察。").foregroundStyle(.secondary) }
                    ForEach(observations) { observation in
                        NavigationLink { ObservationShareCard(observation: observation) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("\(observation.startAt.formatted(date: .abbreviated, time: .omitted)) — \(observation.endAt?.formatted(date: .abbreviated, time: .omitted) ?? "进行中")")
                                Text(UIFormat.duration(summary(observation).confirmedDuration)).font(.title3.monospacedDigit())
                                Text(summary(observation).conditionLabels.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    Text("展示完整观察期间的记录，不用连接时长推断电池健康。").font(.footnote).foregroundStyle(.secondary)
                }.apCard()
            }.padding(20)
        }.apPage().navigationTitle("统计")
            .alert("统计口径", isPresented: $definition) { Button("知道了", role: .cancel) {} } message: {
                Text("仅计算已确认、未排除的闭合连接区间，并对重叠时间取并集。跨日按 Calendar 日边界拆分，等待断开及待核对的跨度不计入。连接不等于佩戴、播放或实际耗电。")
            }
    }
    @ViewBuilder private var metrics: some View {
        UIMetric(label: "连接记录", value: "\(UISessionMetrics.count(store.sessions, in: range)) 段")
        UIMetric(label: "待核对", value: "\(UISessionMetrics.review(store.sessions, in: range)) 条")
    }
    private func summary(_ observation: ChargeObservation) -> ObservationSummary {
        IntervalMath.observationSummary(observation: observation, sessions: store.sessions, batteries: store.state.batteries, asOf: Date())
    }
}
