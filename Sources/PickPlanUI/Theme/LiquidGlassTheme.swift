import SwiftUI
import PickPlanCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pickplan monochrome obsidian & warm white tokens fused with iOS 26 Liquid Glass.
public enum PickPlanPalette {
    public static let obsidian = Color.black
    public static let elevatedSurface = Color(red: 0.118, green: 0.118, blue: 0.118) // #1E1E1E from Android AppTheme
    public static let borderGray = Color(red: 0.259, green: 0.259, blue: 0.259)      // #424242 from Android AppTheme
    public static let primary = Color.white
    public static let muted = Color.white.opacity(0.66)
    public static let subtle = Color.white.opacity(0.38)
    public static let deadlineCoral = Color(red: 0.812, green: 0.400, blue: 0.475)   // #CF6679 from Android AppTheme
    public static let successMint = Color(red: 0.38, green: 0.86, blue: 0.56)

    public static let springAnimation: Animation = .spring(response: 0.36, dampingFraction: 0.78)
    public static let quickSpring: Animation = .spring(response: 0.24, dampingFraction: 0.84)
    public static let androidPressIn: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.11)
    public static let androidPressOut: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.16)
}

/// PressScale button style replicating Android `motion.dart` (`PressScale`, `0.97` scale, `Cubic(0.23, 1, 0.32, 1)`).
public struct PickPlanPressScaleStyle: ButtonStyle {
    private let pressedScale: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pressedScale: CGFloat = 0.97) {
        self.pressedScale = pressedScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? pressedScale : 1.0))
            .animation(
                reduceMotion ? nil : (configuration.isPressed ? PickPlanPalette.androidPressIn : PickPlanPalette.androidPressOut),
                value: configuration.isPressed
            )
    }
}

/// Authentic Pickplan brand emblem loaded from bundled `pickplanlogo.jpg`.
public struct BrandLogoImage: View {
    private let size: CGFloat
    private let cornerRadius: CGFloat

    public init(size: CGFloat = 120, cornerRadius: CGFloat = 28) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            if let url = Bundle.module.url(forResource: "pickplanlogo", withExtension: "jpg"),
               let uiImage = UIImage(contentsOfFile: url.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackMark
            }
            #elseif canImport(AppKit)
            if let url = Bundle.module.url(forResource: "pickplanlogo", withExtension: "jpg"),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackMark
            }
            #else
            fallbackMark
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fallbackMark: some View {
        ZStack {
            Color.black
            Text("P")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// Subtle monochrome ambient pearl light canvas behind Liquid Glass chrome so optical refraction
/// remains legible without breaking Pickplan's stark `#000000` black identity.
public struct AmbientMonochromeCanvas: View {
    public init() {}

    public var body: some View {
        ZStack {
            PickPlanPalette.obsidian.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.095), Color.clear],
                center: .topLeading,
                startRadius: 24,
                endRadius: 460
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.84, green: 0.88, blue: 0.95).opacity(0.07), Color.clear],
                center: .bottomTrailing,
                startRadius: 24,
                endRadius: 500
            )
            .ignoresSafeArea()
        }
    }
}

/// Container that enables native `GlassEffectContainer` morphing on iOS/macOS 26+ (Swift 6.2+)
/// and passes through cleanly on earlier Xcode SDKs / OS versions.
public struct PickPlanGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    public init(spacing: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

private struct PickPlanGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tintColor: Color?

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
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
            fallbackGlass(content)
        }
        #else
        fallbackGlass(content)
        #endif
    }

    private func fallbackGlass(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.36),
                                Color.white.opacity(0.11),
                                Color.white.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.42), radius: 14, y: 8)
    }
}

public extension View {
    /// Applies native iOS 26 Liquid Glass (`glassEffect`) with automatic specular rim fallback on iOS 17–18 / Xcode 16.
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
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
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
