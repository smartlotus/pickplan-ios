import SwiftUI
import PickPlanCore
#if canImport(UIKit)
import UIKit
#endif

/// Pickplan monochrome obsidian & warm editorial tokens paired with iOS 26 Liquid Glass.
public enum PickPlanPalette {
    public static let obsidian = Color(red: 0.02, green: 0.02, blue: 0.025)
    public static let elevatedSurface = Color(red: 0.08, green: 0.08, blue: 0.095)
    public static let editorialPaper = Color(red: 0.968, green: 0.968, blue: 0.949)
    public static let editorialInk = Color(red: 0.08, green: 0.08, blue: 0.08)
    public static let primary = Color.white
    public static let muted = Color.white.opacity(0.64)
    public static let subtle = Color.white.opacity(0.36)
    public static let deadlineCoral = Color(red: 0.812, green: 0.400, blue: 0.475)
    public static let successMint = Color(red: 0.56, green: 0.89, blue: 0.69)

    public static let springAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.78)
    public static let quickSpring: Animation = .spring(response: 0.28, dampingFraction: 0.82)
}

/// Subtle monochrome ambient pearl glow canvas behind Liquid Glass chrome so optical refraction
/// remains legible without breaking Pickplan's stark monochrome identity.
public struct AmbientMonochromeCanvas: View {
    public init() {}

    public var body: some View {
        ZStack {
            PickPlanPalette.obsidian.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.11), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 480
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.82, green: 0.86, blue: 0.94).opacity(0.08), Color.clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()
        }
    }
}

/// Container that enables native `GlassEffectContainer` morphing on iOS/macOS 26+ and passes through cleanly on 18+.
public struct PickPlanGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    public init(spacing: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct PickPlanGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tintColor: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let tintColor {
                if interactive {
                    content.glassEffect(.regular.tint(tintColor).interactive(), in: shape)
                } else {
                    content.glassEffect(.regular.tint(tintColor), in: shape)
                }
            } else if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.36),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.38), radius: 14, y: 8)
        }
    }
}

public extension View {
    /// Applies native iOS 26 Liquid Glass (`glassEffect`) with automatic specular rim fallback on iOS 18 / macOS 15.
    func pickPlanGlass<S: InsettableShape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(PickPlanGlassModifier(shape: shape, interactive: interactive, tintColor: tint))
    }

    /// Attaches native `glassEffectID` on iOS/macOS 26+ when morphing inside `PickPlanGlassGroup`.
    @ViewBuilder
    func pickPlanGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Safe cross-platform tactile haptics bridge.
@MainActor
public enum HapticsBridge {
    public static func impact(_ enabled: Bool, style: Int = 1) {
        guard enabled else { return }
        #if os(iOS)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle = style == 0 ? .light : (style == 2 ? .heavy : .medium)
        UIImpactFeedbackGenerator(style: uiStyle).impactOccurred()
        #endif
    }

    public static func success(_ enabled: Bool) {
        guard enabled else { return }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
