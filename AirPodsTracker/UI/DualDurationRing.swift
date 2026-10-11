import SwiftUI

@MainActor
struct DualDurationRing: View {
    let title: String
    let value: String
    let detail: String
    var awaitingEnd = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 14) {
            if !typeSize.isAccessibilitySize {
                ZStack {
                    Circle().stroke(APStyle.ring, lineWidth: 13).opacity(0.55)
                    Circle().inset(by: 24)
                        .stroke(APStyle.ring, style: StrokeStyle(lineWidth: 7, dash: awaitingEnd ? [3, 7] : [])).opacity(0.8)
                    VStack(spacing: 10) {
                        Image(systemName: "headphones").font(.title).foregroundStyle(APStyle.accent)
                        Text(title).font(.subheadline).foregroundStyle(.secondary)
                        Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }.padding(48)
                }.frame(maxWidth: 300).aspectRatio(1, contentMode: .fit)
            } else {
                Text(title).font(.headline)
                Text(value).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("无刻度时长视图 · 圆环不是电量").font(.footnote).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
