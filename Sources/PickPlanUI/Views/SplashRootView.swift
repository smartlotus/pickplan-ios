import SwiftUI
import PickPlanCore

/// Root entry scene showing Pickplan's editorial warm paper splash before dissolving into Obsidian Liquid Glass.
public struct PickPlanRootScene: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSplash = true
    @State private var logoScale: CGFloat = 0.94
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
                    PickPlanPalette.editorialPaper.ignoresSafeArea()
                    VStack(spacing: 18) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 108, height: 108)
                                .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                            Image(systemName: "checkmark")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        Text("PICKPLAN")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(PickPlanPalette.editorialInk)
                        Text(AppLocalizer.t(zh: "做计划，说大白话", en: "Plan in plain words", language: store.language))
                            .font(.subheadline)
                            .foregroundStyle(PickPlanPalette.editorialInk.opacity(0.62))
                    }
                    .scaleEffect(logoScale)
                }
                .opacity(splashOpacity)
                .transition(.opacity)
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
            withAnimation(.easeOut(duration: 0.45)) {
                logoScale = 1.03
            }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeInOut(duration: 0.28)) {
                splashOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(280))
            showSplash = false
        }
    }
}
