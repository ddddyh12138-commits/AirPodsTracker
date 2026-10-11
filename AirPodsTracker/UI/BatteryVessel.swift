import SwiftUI

@MainActor
struct BatteryVessel: View {
    let level: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var fill: LinearGradient {
        LinearGradient(colors: (level ?? 100) < 20 ? [.orange, .yellow] : [.green, .cyan], startPoint: .bottomLeading, endPoint: .topTrailing)
    }
    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 42).fill(APStyle.surface)
                    if let level {
                        fill.frame(height: proxy.size.height * CGFloat(min(100, max(0, level))) / 100)
                            .opacity(reduceTransparency ? 1 : 0.6)
                    }
                    VStack {
                        Rectangle().fill(.primary.opacity(0.15)).frame(height: 1).padding(.top, 48)
                        Spacer()
                        Capsule().fill(.primary.opacity(0.45)).frame(width: 22, height: 5).padding(.bottom, 27)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 42))
                .overlay(RoundedRectangle(cornerRadius: 42).stroke(.primary.opacity(0.3), lineWidth: 1.5))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(reduceTransparency ? 0 : 0.3), lineWidth: 2).padding(10)
                }
            }.frame(width: 245, height: 172)
            Text(level.map { "盒子 \($0)%" } ?? "尚无盒子电量")
                .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
        }.frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: level)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(level.map { "盒子历史读数，百分之\($0)" } ?? "盒子电量未知")
    }
}
