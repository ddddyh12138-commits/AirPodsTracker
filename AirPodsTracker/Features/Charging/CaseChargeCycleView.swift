import SwiftUI
import TrackerCore

private struct UIChargePresentation: Identifiable {
    var id: String { action.rawValue }
    let action: ChargeAction
}

@MainActor
struct CaseChargeCycleView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var action: UIChargePresentation?
    @State private var battery = false
    @State private var report: ChargeObservation?
    @State private var pendingReport: ChargeObservation?
    @State private var deleting: ChargeObservation?
    @State private var editing: ChargeObservation?
    private var caseReading: UIBatteryReading? { UIBatteryReading.latest(store.state.batteries, deviceID: store.device?.id, value: \.caseLevel) }
    private var history: [ChargeObservation] { store.state.observations.filter { $0.deviceID == store.device?.id && $0.endAt != nil }.sorted { $0.startAt > $1.startAt } }
    private var canUndo: Bool {
        guard let receipt = store.state.receipts.last(where: { $0.deviceID == store.device?.id }) else { return false }
        return receipt.status == .applied && receipt.undoState != nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 16) {
                    BatteryVessel(level: caseReading?.value)
                    if let reading = caseReading {
                        Text("历史读数 · \(reading.snapshot.measuredAt.map(UIFormat.date) ?? "读数时间未知")")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text(UIFormat.source(reading.snapshot.source)).font(.footnote).foregroundStyle(.secondary)
                        if reading.value < 20 { Text("最近记录低于 20%").font(.subheadline).foregroundStyle(APStyle.warning) }
                    } else { Text("记录盒子电量后，水位会按真实百分比显示。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    Button("记录电量") { battery = true }.frame(minHeight: 44).disabled(store.device == nil)
                }.apCard()
                if let observation = store.activeObservation {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("当前充电观察").font(.headline)
                        Text("\(UIFormat.date(observation.startAt)) 至今").font(.subheadline).foregroundStyle(.secondary)
                        ObservationMetricsView(observation: observation)
                        Button("盒子已充满") { action = UIChargePresentation(action: .startFull) }.frame(maxWidth: .infinity, minHeight: 44)
                        Button("记录补电并开始新观察") { action = UIChargePresentation(action: .topUpAndRestart) }.buttonStyle(APPrimaryButtonStyle())
                        HStack {
                            Button("结束观察") { action = UIChargePresentation(action: .end) }.frame(minHeight: 44)
                            Spacer()
                            Button("查看报告") { report = observation }.frame(minHeight: 44)
                        }
                        Button("编辑观察") { editing = observation }.frame(minHeight: 44)
                    }.apCard()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("开始一次充电观察").font(.headline)
                        Text("记录一次充电后的连接情况；提前补电、缺少电量读数都可以如实保留。").font(.subheadline).foregroundStyle(.secondary)
                        Button("盒子已充满") { action = UIChargePresentation(action: .startFull) }.buttonStyle(APPrimaryButtonStyle())
                        Button("从选定时间开始观察") { action = UIChargePresentation(action: .startNow) }.frame(maxWidth: .infinity, minHeight: 44)
                    }.apCard().disabled(store.device == nil)
                }
                if canUndo {
                    Button { store.run { try store.undoLastCharge() } } label: { Label("撤销最新充电操作", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity, minHeight: 44) }
                        .apCard()
                }
                BatteryReadingsView()
                VStack(alignment: .leading, spacing: 16) {
                    Text("历史观察").font(.headline)
                    if history.isEmpty { Text("结束一次观察后，报告会保留在这里。").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(history) { observation in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { report = observation } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(observation.startAt.formatted(date: .abbreviated, time: .omitted)) — \(observation.endAt?.formatted(date: .abbreviated, time: .omitted) ?? "进行中")").font(.headline)
                                    Text(UIFormat.duration(summary(observation).confirmedDuration)).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                                    Text(summary(observation).conditionLabels.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                                    Text("查看与分享报告 ›").font(.subheadline).foregroundStyle(APStyle.accent)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.buttonStyle(.plain)
                            HStack {
                                Button("编辑观察") { editing = observation }.font(.subheadline).frame(minHeight: 44)
                                Spacer()
                                Button("删除观察", role: .destructive) { deleting = observation }.font(.subheadline).frame(minHeight: 44)
                            }
                            Divider()
                        }
                    }
                }.apCard()
                Text("观察报告统计连接记录，不估算电池容量、健康度或剩余使用时间。").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.apPage().navigationTitle("充电盒")
            .sheet(isPresented: $battery) { BatteryInputSheet() }
            .sheet(item: $editing) { observation in ObservationEditSheet(observation: observation) }
            .sheet(item: $action, onDismiss: { if let pendingReport { report = pendingReport; self.pendingReport = nil } }) { item in
                ObservationEditor(action: item.action) { observation in pendingReport = observation }
            }
            .sheet(item: $report) { observation in NavigationStack { ObservationShareCard(observation: observation, showsDone: true) } }
            .confirmationDialog("删除这次观察？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除观察", role: .destructive) {
                    guard let deleting else { return }
                    store.run { try store.deleteObservation(deleting) }
                    self.deleting = nil
                }
            } message: { Text("仅删除观察，连接历史与电量快照仍然保留。") }
    }
    private func summary(_ observation: ChargeObservation) -> ObservationSummary {
        IntervalMath.observationSummary(observation: observation, sessions: store.sessions, batteries: store.state.batteries, asOf: Date())
    }
}

@MainActor
struct ObservationMetricsView: View {
    @EnvironmentObject private var store: TrackerStore
    let observation: ChargeObservation
    private var summary: ObservationSummary { IntervalMath.observationSummary(observation: observation, sessions: store.sessions, batteries: store.state.batteries, asOf: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIFormat.duration(summary.confirmedDuration)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            Text("已记录连接 · \(summary.sessionCount) 段 · \(summary.needsReviewCount) 条待核对").font(.subheadline).foregroundStyle(.secondary)
            Text(summary.conditionLabels.joined(separator: " · ")).font(.footnote).foregroundStyle(summary.needsReviewCount > 0 ? APStyle.warning : .secondary)
        }.accessibilityElement(children: .combine)
    }
}
