import SwiftUI
import Combine

@main
@MainActor
struct AirPodsTrackerApp: App {
    @StateObject private var store = TrackerStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                    if scenePhase == .active { store.refreshClock() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.reload() }
                }
        }
    }
}
