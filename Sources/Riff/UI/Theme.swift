import AppKit
import SwiftUI

/// Semantic colors and native materials shared by every Riff surface. These
/// intentionally avoid fixed light/dark values so macOS can resolve appearance,
/// contrast, transparency, and inactive-window behavior for the user.
enum LauncherTheme {
    static let primary = Color(nsColor: .labelColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.72)
    static let selection = Color(nsColor: .selectedContentBackgroundColor).opacity(0.34)
    static let subtleSelection = Color(nsColor: .quaternaryLabelColor).opacity(0.22)
    static let contentSurface = Color(nsColor: .windowBackgroundColor).opacity(0.42)
    static let sidebarSurface = Color(nsColor: .underPageBackgroundColor).opacity(0.34)
    static let tileSurface = Color(nsColor: .controlBackgroundColor).opacity(0.28)
    static let codeSurface = Color(nsColor: .quaternarySystemFill)
    static let accent = Color(nsColor: .controlAccentColor)
}

enum RiffPanelSurfaceStyle {
    /// The refractive capsule used by Spotlight-like search. Regular glass
    /// keeps a visible material body across both quiet and detailed desktops;
    /// clear glass can visually disappear over low-contrast backgrounds.
    case spotlight
    /// A transient command surface, such as the launcher or translator.
    case floating
    /// A content-heavy utility window, such as notes or settings.
    case content
}

private struct RiffPanelSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let style: RiffPanelSurfaceStyle
    @AppStorage(AppearancePreferences.glassOpacityKey)
    private var glassOpacity = AppearancePreferences.defaultGlassOpacity

    private var resolvedGlassOpacity: Double {
        AppearancePreferences.normalizedGlassOpacity(glassOpacity)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Keep one AppKit glass view alive while SwiftUI updates the
            // content above it. Rebuilding `glassEffect` with a different
            // shape made the first search character look like a material swap
            // and forced the whole launcher surface to re-materialize.
            content
                .background {
                    RiffGlassBackdrop(
                        cornerRadius: cornerRadius,
                        opacity: resolvedGlassOpacity
                    )
                }
                .overlay { panelRim }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(
                    color: .black.opacity(style == .content ? 0.42 : 0.58),
                    radius: style == .content ? 24 : 30,
                    x: 0,
                    y: style == .content ? 12 : 16
                )
        } else {
            if style == .content {
                content
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(resolvedGlassOpacity)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    private var panelRim: some View {
        ZStack {
            // Liquid Glass has a bright upper lens and a substantially darker
            // lower edge. The lower-biased rim also gives the system window
            // shadow a denser silhouette to composite from.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.14), location: 0),
                            .init(color: .clear, location: 0.48),
                            .init(color: .black.opacity(0.52), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LauncherTheme.hairline.opacity(0.22 + 0.32 * resolvedGlassOpacity),
                    lineWidth: 0.5
                )
        }
        .allowsHitTesting(false)
    }
}

@available(macOS 26.0, *)
private struct RiffGlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat
    let opacity: Double

    func makeNSView(context: Context) -> RiffGlassBackdropView {
        let view = RiffGlassBackdropView()
        view.style = .regular
        view.update(
            cornerRadius: cornerRadius,
            opacity: opacity,
            animated: false
        )
        return view
    }

    func updateNSView(_ view: RiffGlassBackdropView, context: Context) {
        view.update(
            cornerRadius: cornerRadius,
            opacity: opacity,
            animated: view.window?.isVisible == true
        )
    }
}

@available(macOS 26.0, *)
final class RiffGlassBackdropView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(
        cornerRadius targetRadius: CGFloat,
        opacity: Double,
        animated: Bool
    ) {
        style = .regular
        alphaValue = opacity

        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              abs(cornerRadius - targetRadius) > 0.1
        else {
            cornerRadius = targetRadius
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LauncherMotion.resizeDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20, 0.80, 0.20, 1
            )
            animator().cornerRadius = targetRadius
        }
    }
}

private struct RiffGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct RiffSelectedSurfaceModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if selected {
            content.background(
                LauncherTheme.selection,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
        }
    }
}

extension View {
    func riffPanelSurface(
        cornerRadius: CGFloat,
        style: RiffPanelSurfaceStyle
    ) -> some View {
        modifier(RiffPanelSurfaceModifier(cornerRadius: cornerRadius, style: style))
    }

    func riffGlassButton(prominent: Bool = false) -> some View {
        modifier(RiffGlassButtonModifier(prominent: prominent))
    }

    func riffSelectedSurface(_ selected: Bool, cornerRadius: CGFloat) -> some View {
        modifier(RiffSelectedSurfaceModifier(selected: selected, cornerRadius: cornerRadius))
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(LauncherTheme.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(LauncherTheme.hairline, lineWidth: 0.5)
            }
    }
}

struct PanelCloseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("关闭", systemImage: "xmark")
                .font(.system(size: 11.5, weight: .medium))
        }
        .riffGlassButton()
        .controlSize(.small)
        .help("\(title)（Esc 或 ⌘W）")
    }
}
