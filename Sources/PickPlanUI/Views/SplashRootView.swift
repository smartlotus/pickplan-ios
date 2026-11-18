import SwiftUI
import PickPlanCore

/// Faithful port of Android Pickplan's `SplashScreen`:
/// Pure white `#FFFFFF` backdrop, real `pickplanlogo.jpg` (`120×120`, radius `28`), `PICKPLAN`,
/// `做计划，说大白话`, `900ms` breathing pulse (`1.0 -> 1.04 -> 1.0`) + `220ms` cross-fade into Obsidian workspace.
public struct PickPlanRootScene: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSplash = true
    @State private var logoScale: CGFloat = 1.0
    @State private var splashOpacity: Double = 1.0

    public init(store: PlanStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            AdaptiveWorkspaceView(store: store)
                .preferredColorScheme(.dark)

            if showSplash {
                ZStack {
                    Color.white.ignoresSafeArea()
                    VStack(spacing: 0) {
                        BrandLogoImage(size: 120, cornerRadius: 28)
                            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                        Spacer().frame(height: 24)
                        Text("PICKPLAN")
                            .font(.system(size: 22, weight: .bold))
                            .tracking(3)
                            .foregroundStyle(.black)
                        Spacer().frame(height: 8)
                        Text(AppLocalizer.t(zh: "做计划，说大白话", en: "Plan in plain words", language: store.language))
                            .font(.system(size: 13))
                            .tracking(0.4)
                            .foregroundStyle(Color.black.opacity(0.58))
                    }
                    .scaleEffect(logoScale)
                }
                .opacity(splashOpacity)
                .zIndex(20)
            }
        }
        .task {
            await store.reload()
            await store.evaluateScheduledBackupIfNeeded()
            if reduceMotion {
                showSplash = false
                return
            }
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(.easeInOut(duration: 0.25)) {
                logoScale = 1.04
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeInOut(duration: 0.25)) {
                logoScale = 1.0
            }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.timingCurve(0.8, 0, 0.2, 1, duration: 0.22)) {
                splashOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(230))
            showSplash = false
        }
    }
}
