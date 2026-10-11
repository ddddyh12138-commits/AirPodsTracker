import SwiftUI
import UIKit
import TrackerCore

@MainActor
struct ObservationShareCard: View {
    @EnvironmentObject private var store: TrackerStore
    @Environment(\.dismiss) private var dismiss
    let observation: ChargeObservation
    var showsDone = false
    @State private var showName = false
    @State private var showDates = false
    @State private var generated: UIImage?
    @State private var shareURL: URL?
    @State private var sharing = false
    @State private var error: String?
    private var current: ChargeObservation { store.state.observations.first { $0.id == observation.id } ?? observation }
    private var summary: ObservationSummary {
        IntervalMath.observationSummary(observation: current, sessions: store.sessions, batteries: store.state.batteries, asOf: Date())
    }
    private var deviceName: String { store.state.devices.first { $0.id == observation.deviceID }?.name ?? "我的耳机" }
    private var values: [TimeInterval] {
        IntervalMath.dailyDurations(sessions: store.sessions.filter { $0.deviceID == current.deviceID }, in: UISessionMetrics.range(current), calendar: .current).map(\.duration)
    }
    private var canvas: ObservationReportCanvas {
        ObservationReportCanvas(observation: current, summary: summary, deviceName: showName ? deviceName : nil, showDates: showDates, dailyValues: values)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(UIFormat.date(current.startAt)) — \(current.endAt.map(UIFormat.date) ?? "进行中")").font(.subheadline).foregroundStyle(.secondary)
                    ObservationMetricsView(observation: current)
                    LabeledContent("开始原因", value: current.startReason)
                    if let reason = current.endReason { LabeledContent("结束原因", value: reason) }
                    if let note = current.note, !note.isEmpty { Text(note).font(.subheadline) }
                    Text("起止读数：\(snapshotLabel(current.startSnapshotID)) → \(snapshotLabel(current.endSnapshotID))").font(.footnote).foregroundStyle(.secondary)
                }.apCard()
                VStack(alignment: .leading, spacing: 14) {
                    Text("分享内容").font(.headline)
                    Toggle("显示设备昵称", isOn: $showName)
                    Toggle("显示具体时间", isOn: $showDates)
                    Text("图片不会包含原始事件、手动备注或电量截图。").font(.footnote).foregroundStyle(.secondary)
                }.apCard()
                    .onChange(of: showName) { _, _ in generated = nil; shareURL = nil }
                    .onChange(of: showDates) { _, _ in generated = nil; shareURL = nil }
                GeometryReader { proxy in
                    canvas.scaleEffect(proxy.size.width / 360, anchor: .topLeading)
                }.aspectRatio(4.0 / 5.0, contentMode: .fit).accessibilityHidden(true)
                Text("预览 · 1080 × 1350 PNG").font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                Button { generateAndShare() } label: { Label("生成图片并分享", systemImage: "square.and.arrow.up") }.buttonStyle(APPrimaryButtonStyle())
                if let generated {
                    Image(uiImage: generated).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("已生成的分享图片")
                }
                Text("分享使用当前已保存的记录；它不是电池健康报告。").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.apPage().navigationTitle("观察报告").navigationBarTitleDisplayMode(.inline)
            .toolbar { if showsDone { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.frame(minHeight: 44) } } }
            .sheet(isPresented: $sharing) { if let shareURL { ShareSheet(items: [shareURL]) } }
    }
    private func snapshotLabel(_ id: UUID?) -> String {
        guard let id, let snapshot = store.state.batteries.first(where: { $0.id == id }) else { return "缺测" }
        return "盒子 \(UIFormat.percent(snapshot.caseLevel))"
    }
    @MainActor private func generateAndShare() {
        error = nil
        let renderer = ImageRenderer(content: canvas.environment(\.colorScheme, .dark).environment(\.dynamicTypeSize, .medium))
        renderer.scale = 3
        guard let image = renderer.uiImage, let png = image.pngData() else { error = "图片生成失败，请重试。"; return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("AirPodsTracker-\(UUID().uuidString).png")
            try png.write(to: url, options: .atomic)
            generated = image
            shareURL = url
            sharing = true
        } catch { self.error = "图片未能保存到临时目录：\(error.localizedDescription)" }
    }
}

@MainActor
private struct ObservationReportCanvas: View {
    let observation: ChargeObservation
    let summary: ObservationSummary
    let deviceName: String?
    let showDates: Bool
    let dailyValues: [TimeInterval]
    private var period: String {
        guard showDates else { return observation.endAt == nil ? "本次观察进行中" : "一次充电观察" }
        return "\(UIFormat.date(observation.startAt))\n\(observation.endAt.map(UIFormat.date) ?? "进行中")"
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.09, green: 0.15, blue: 0.24), Color(red: 0.035, green: 0.055, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let maxValue = dailyValues.max(), maxValue > 0 {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(dailyValues.suffix(30).enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.16)).frame(height: max(0, 110 * value / maxValue))
                    }
                }.frame(height: 110).padding(.horizontal, 28).padding(.bottom, 108)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "headphones").font(.system(size: 26)).foregroundStyle(Color(red: 0.47, green: 0.68, blue: 1))
                    Spacer()
                    Text("CONNECTION LOG").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.5).foregroundStyle(.white.opacity(0.6))
                }
                Text("我的耳机记录").font(.system(size: 27, weight: .semibold)).padding(.top, 22)
                Text(deviceName ?? "充电观察报告").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).padding(.top, 7)
                Spacer(minLength: 18)
                Text("已记录连接").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                Text(UIFormat.duration(summary.confirmedDuration)).font(.system(size: 37, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(2).minimumScaleFactor(0.65).padding(.top, 8)
                Text("\(summary.sessionCount) 段记录   ·   \(summary.needsReviewCount) 条待核对").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)).padding(.top, 14)
                Text(summary.conditionLabels.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Color(red: 0.76, green: 0.84, blue: 0.95)).padding(.top, 9)
                Spacer(minLength: 16)
                Text(period).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
                Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5).padding(.vertical, 14)
                Text("仅统计已确认的闭合连接区间。\n连接记录不等于佩戴、播放或电池健康。").font(.system(size: 11)).lineSpacing(4).foregroundStyle(.white.opacity(0.7))
            }.padding(28)
        }.foregroundStyle(.white).frame(width: 360, height: 450).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
