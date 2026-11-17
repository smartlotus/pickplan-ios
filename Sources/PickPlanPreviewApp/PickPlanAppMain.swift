import SwiftUI
import PickPlanCore
import PickPlanUI

@main
struct PickPlanPreviewApp: App {
    @StateObject private var store = PlanStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PickPlanRootScene(store: store)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        Task { await store.handleSceneDidEnterBackground() }
                    } else if newPhase == .active {
                        Task { await store.evaluateScheduledBackupIfNeeded() }
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        #endif
    }
}
