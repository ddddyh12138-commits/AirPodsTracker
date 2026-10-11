import SwiftUI
import TrackerCore

@MainActor
struct ContentView: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var selection = 0
    var body: some View {
        Group {
            if let failure = store.storageFailure {
                VStack(spacing: 20) {
                    EmptyStateView(title: "本地记录暂时无法读取", detail: failure, symbol: "externaldrive.badge.exclamationmark")
                    Button("重新读取") { store.reload() }.buttonStyle(APPrimaryButtonStyle())
                }.padding(24).apPage()
            } else {
                TabView(selection: $selection) {
                    NavigationStack { DashboardView(selectedTab: $selection) }
                        .tabItem { Label("总览", systemImage: "house.fill") }.tag(0)
                    NavigationStack { SessionHistoryView() }
                        .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }.tag(1)
                    NavigationStack { StatisticsView() }
                        .tabItem { Label("统计", systemImage: "chart.bar.fill") }.tag(2)
                    NavigationStack { CaseChargeCycleView() }
                        .tabItem { Label("充电盒", systemImage: "battery.100.bolt") }.tag(3)
                }.tint(APStyle.accent)
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
