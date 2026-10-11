import SwiftUI
import TrackerCore

@MainActor
struct SessionHistoryView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var filter = 0
    @State private var manual = false
    @State private var editing: UsageSession?
    @State private var staleCorrection: SessionCorrection?
    private var filtered: [UsageSession] {
        store.sessions.filter { filter == 1 ? $0.status == .needsReview : filter == 2 ? $0.status == .excluded : true }
            .sorted { ($0.start ?? $0.end ?? .distantPast) > ($1.start ?? $1.end ?? .distantPast) }
    }
    private var days: [Date] { Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.start ?? $0.end ?? .distantPast) })).sorted(by: >) }
    var body: some View {
        List {
            Section {
                Picker("筛选记录", selection: $filter) {
                    Text("全部").tag(0)
                    Text("待核对 \(store.reviewCount)").tag(1)
                    Text("已排除").tag(2)
                }.pickerStyle(.segmented)
                Text("设备：\(store.device?.name ?? "尚未建立设备")").font(.footnote).foregroundStyle(.secondary)
            }.listRowBackground(APStyle.surface)
            if filter != 2 && !store.reduction.unresolvedCorrections.isEmpty {
                Section("需要核对的旧修正") {
                    Text("迟到的原始事件改变了配对，旧修正暂未计入。可编辑对应的新记录，或撤销旧修正后重新核对。").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(store.reduction.unresolvedCorrections) { correction in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("修正于 \(UIFormat.date(correction.updatedAt))").font(.headline)
                            Text("\(correction.startOverride.map(UIFormat.date) ?? "未修改开始") → \(correction.endOverride.map(UIFormat.date) ?? "未修改结束")").font(.subheadline)
                            if correction.excluded { Text("这条旧修正曾排除记录").font(.footnote).foregroundStyle(APStyle.warning) }
                            Button("撤销这条旧修正") { staleCorrection = correction }.frame(minHeight: 44)
                        }
                    }
                }.listRowBackground(APStyle.surface)
            }
            if filtered.isEmpty {
                EmptyStateView(title: filter == 1 ? "没有待核对记录" : filter == 2 ? "没有已排除记录" : "等待第一段记录", detail: filter == 0 ? "连接和断开记录到达后会自动配对，也可以手动补录。" : "记录会按所选状态出现在这里。", symbol: "clock.arrow.circlepath")
                    .listRowBackground(Color.clear)
            }
            ForEach(days, id: \.self) { day in
                Section {
                    ForEach(filtered.filter { Calendar.current.isDate($0.start ?? $0.end ?? .distantPast, inSameDayAs: day) }) { session in
                        NavigationLink { SessionDetailView(session: session) } label: { SessionRow(session: session) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(session.status == .excluded ? "恢复" : "排除") { store.run { try store.setExcluded(session, excluded: session.status != .excluded) } }.tint(.orange)
                                Button("编辑") { editing = session }.tint(.blue)
                            }.listRowBackground(APStyle.surface)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.formatted(date: .abbreviated, time: .omitted))
                        if let interval = Calendar.current.dateInterval(of: .day, for: day) {
                            Text("已记录连接 \(UIFormat.duration(IntervalMath.confirmedDuration(sessions: store.sessions, in: interval)))")
                        }
                    }
                }
            }
        }.scrollContentBackground(.hidden).apPage().navigationTitle("记录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { manual = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("补录连接记录").disabled(store.device == nil) } }
            .sheet(isPresented: $manual) { SessionEditor(session: nil) }
            .sheet(item: $editing) { SessionEditor(session: $0) }
            .confirmationDialog("撤销旧修正？", isPresented: Binding(get: { staleCorrection != nil }, set: { if !$0 { staleCorrection = nil } }), titleVisibility: .visible) {
                Button("撤销旧修正", role: .destructive) {
                    guard let staleCorrection else { return }
                    store.run { try store.dismissStaleCorrection(staleCorrection) }
                    self.staleCorrection = nil
                }
            } message: { Text("原始事件保留，按最新事件重新配对。若仍有缺失，请打开对应记录补全。") }
    }
}

@MainActor
struct SessionRow: View {
    let session: UsageSession
    private var duration: TimeInterval? {
        guard session.status == .confirmed, let start = session.start, let end = session.end else { return nil }
        return end.timeIntervalSince(start)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 5) {
                Circle().fill(session.status == .needsReview ? APStyle.warning : APStyle.accent).frame(width: 8, height: 8)
                Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
            }.frame(width: 10).padding(.vertical, 7)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(UIFormat.time(session.start)) — \(UIFormat.time(session.end))").font(.headline.monospacedDigit())
                HStack {
                    Text(duration.map(UIFormat.duration) ?? UIFormat.status(session.status))
                        .foregroundStyle(session.status == .needsReview ? APStyle.warning : .primary)
                    Spacer()
                    Text(UIFormat.source(session.source)).foregroundStyle(.secondary)
                }.font(.subheadline)
                if let duration {
                    // A fixed four-hour display scale compares actual durations; no invented waveform.
                    GeometryReader { proxy in
                        Capsule().fill(APStyle.ring).frame(width: proxy.size.width * min(1, duration / (4 * 3600)), height: 4)
                    }.frame(height: 4).accessibilityHidden(true)
                }
                if let tag = session.tag, !tag.isEmpty { Text(tag).font(.footnote).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

@MainActor
struct SessionDetailView: View {
    @EnvironmentObject private var store: TrackerStore
    let session: UsageSession
    @State private var editing = false
    @State private var splitting = false
    @State private var confirmExclusion = false
    private var current: UsageSession { store.sessions.first { $0.id == session.id } ?? session }
    private var events: [ConnectionEvent] { store.state.events.filter { current.anchorEventIDs.contains($0.id) }.sorted { $0.observedAt < $1.observedAt } }
    private var snapshots: [BatterySnapshot] {
        guard let start = current.start, let end = current.end else { return [] }
        return store.state.batteries.filter { snapshot in
            guard snapshot.deviceID == current.deviceID, let time = snapshot.measuredAt else { return false }
            return time >= start && time <= end
        }.sorted { ($0.measuredAt ?? .distantPast) < ($1.measuredAt ?? .distantPast) }
    }
    var body: some View {
        List {
            Section("连接区间") {
                LabeledContent("开始", value: current.start.map(UIFormat.date) ?? "未知，需要补开始")
                LabeledContent("结束", value: current.end.map(UIFormat.date) ?? "未知")
                LabeledContent("状态", value: UIFormat.status(current.status))
                if current.status == .confirmed, let start = current.start, let end = current.end {
                    LabeledContent("已记录连接", value: UIFormat.duration(end.timeIntervalSince(start)))
                }
                if current.status == .awaitingEnd { Text("开始已记录，等待断开记录。正常等待无需逐条确认，当前跨度不计入统计。").foregroundStyle(.secondary) }
                if let issue = current.issue { Text(issue).foregroundStyle(APStyle.warning) }
                if let tag = current.tag { LabeledContent("手动标签", value: tag) }
                if let note = current.note, !note.isEmpty { Text(note) }
            }
            Section("原始事件") {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.kind == .start ? "收到连接" : "收到断开").font(.headline)
                        Text("\(UIFormat.source(event.source)) · \(UIFormat.date(event.observedAt))")
                        Text("保存于 \(UIFormat.date(event.savedAt))").font(.footnote).foregroundStyle(.secondary)
                        if event.source == .shortcut { Text("事件时间来自自动化动作执行。").font(.footnote).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
            }
            if !store.state.corrections.filter({ $0.deviceID == current.deviceID && !$0.anchorEventIDs.filter(current.anchorEventIDs.contains).isEmpty }).isEmpty {
                Section("用户修正") {
                    ForEach(store.state.corrections.filter { $0.deviceID == current.deviceID && !$0.anchorEventIDs.filter(current.anchorEventIDs.contains).isEmpty }) { correction in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("修正于 \(UIFormat.date(correction.updatedAt))")
                            Text(correction.excluded ? "已排除，原始事件保留" : "以用户确认的边界与标签为准").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("期间电量快照") {
                if snapshots.isEmpty { Text("这段记录没有可定位时间的电量快照。").foregroundStyle(.secondary) }
                ForEach(snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.measuredAt.map(UIFormat.date) ?? "读数时间未知")
                        Text("左 \(UIFormat.percent(snapshot.left)) · 右 \(UIFormat.percent(snapshot.right)) · 盒 \(UIFormat.percent(snapshot.caseLevel))")
                        Text(UIFormat.source(snapshot.source)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(current.status == .needsReview ? "补全 / 核对记录" : "编辑记录") { editing = true }.frame(minHeight: 44)
                if current.start != nil && current.end != nil && current.status != .excluded {
                    Button("拆分这段记录") { splitting = true }.frame(minHeight: 44)
                }
                Button(current.status == .excluded ? "恢复到记录中" : "排除这段记录", role: current.status == .excluded ? nil : .destructive) {
                    if current.status == .excluded { store.run { try store.setExcluded(current, excluded: false) } }
                    else { confirmExclusion = true }
                }.frame(minHeight: 44)
            } footer: { Text("排除会移出统计，原始历史仍保留，可随时恢复。拆分会保留原段并将其排除，生成两段手动记录。") }
        }.navigationTitle("记录详情").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $editing) { SessionEditor(session: current) }
            .sheet(isPresented: $splitting) { SessionSplitSheet(session: current) }
            .confirmationDialog("排除这段记录？", isPresented: $confirmExclusion, titleVisibility: .visible) {
                Button("排除记录", role: .destructive) { store.run { try store.setExcluded(current, excluded: true) } }
            } message: { Text("不再计入统计，仍可从“已排除”恢复。") }
    }
}
