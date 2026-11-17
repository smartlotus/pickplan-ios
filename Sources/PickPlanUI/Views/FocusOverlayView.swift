import SwiftUI
import PickPlanCore

/// Calm single-task Liquid Glass Pomodoro / focus timer view.
public struct FocusOverlayView: View {
    @ObservedObject private var store: PlanStore
    @Environment(\.dismiss) private var dismiss
    private let embedded: Bool

    public init(store: PlanStore, embedded: Bool = false) {
        self.store = store
        self.embedded = embedded
    }

    private var progress: Double {
        let total = max(1, store.focusTotalDurationSeconds)
        return Double(total - store.focusRemainingSeconds) / Double(total)
    }

    public var body: some View {
        VStack(spacing: 18) {
            if !embedded {
                HStack {
                    Text(AppLocalizer.t(zh: "专注时刻", en: "Focus Mode", language: store.language))
                        .font(.headline)
                    Spacer()
                    Button(AppLocalizer.t(zh: "收起", en: "Done", language: store.language)) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text(AppLocalizer.t(zh: "专注计时", en: "FOCUS TIMER", language: store.language))
                    .font(.caption.bold())
                    .foregroundStyle(PickPlanPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: progress)

                VStack(spacing: 4) {
                    Text(formattedClock)
                        .font(.system(size: embedded ? 34 : 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(store.activeFocusTodo?.title ?? AppLocalizer.t(zh: "下一件事，从这里开始", en: "Pick a task to begin", language: store.language))
                        .font(.caption)
                        .foregroundStyle(PickPlanPalette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                }
            }
            .frame(width: embedded ? 184 : 240, height: embedded ? 184 : 240)

            HStack(spacing: 12) {
                Button {
                    HapticsBridge.impact(store.preferences.hapticsEnabled, style: 1)
                    Task {
                        if store.isFocusRunning {
                            await store.pauseFocus()
                        } else if store.activeFocusTodoId != nil {
                            await store.resumeFocus()
                        } else if let first = store.todos.first(where: { !$0.isCompleted }) {
                            await store.startFocus(forTodoId: first.id)
                        }
                    }
                } label: {
                    Label(
                        store.isFocusRunning
                            ? AppLocalizer.t(zh: "暂停", en: "Pause", language: store.language)
                            : AppLocalizer.t(zh: "开始", en: "Start", language: store.language),
                        systemImage: store.isFocusRunning ? "pause.fill" : "play.fill"
                    )
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)

                if store.activeFocusTodoId != nil {
                    Button {
                        Task { await store.stopFocus(logElapsedMinutes: true) }
                    } label: {
                        Text(AppLocalizer.t(zh: "结束并记录", en: "Finish", language: store.language))
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .pickPlanGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(embedded ? 20 : 28)
        .frame(maxWidth: .infinity)
        .background {
            if embedded {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.clear)
                    .pickPlanGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                AmbientMonochromeCanvas()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var formattedClock: String {
        let mins = max(0, store.focusRemainingSeconds) / 60
        let secs = max(0, store.focusRemainingSeconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
