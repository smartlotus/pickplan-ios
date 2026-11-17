import SwiftUI
import PickPlanCore
import PickPlanUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct PickPlanAppEntry: App {
    @StateObject private var store = PlanStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.smartlotus.pickplan.autobackup",
            using: nil
        ) { task in
            task.setTaskCompleted(success: true)
        }
        #endif
    }

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
