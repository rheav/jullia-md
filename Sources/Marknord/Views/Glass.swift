import AppKit
import MarknordCore
import SwiftUI

/// The blurred desktop behind the window. Every glass surface is a theme tint laid over this.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Lets the window itself be see-through, so the blur can show the desktop.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A rectangle with a rounded hole: the window's tint around a panel, so the panel sits straight on the blur and its
/// own transparency is not stacked on the window's.
struct PanelCutout: Shape {
    var insets: EdgeInsets
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let hole = CGRect(
            x: rect.minX + insets.leading, y: rect.minY + insets.top,
            width: rect.width - insets.leading - insets.trailing, height: rect.height - insets.top - insets.bottom
        )
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}

enum PanelMetrics {
    static let cornerRadius: CGFloat = 18
    static let gap: CGFloat = 8
}

extension View {
    /// A floating panel (file sidebar, comments): the theme's surface colour over the blurred desktop, as see-through
    /// as its setting says, with a glass edge.
    func glassPanel(_ glass: GlassSetting, theme: Theme, minimumOpacity: Double = 0) -> some View {
        modifier(GlassPanel(glass: glass, theme: theme, minimumOpacity: minimumOpacity))
    }

    /// The window tint around a panel laid out with `insets` of padding.
    func windowTint(around insets: EdgeInsets, theme: Theme, glass: GlassSetting) -> some View {
        modifier(WindowTint(insets: insets, theme: theme, glass: glass))
    }
}

private struct GlassPanel: ViewModifier {
    let glass: GlassSetting
    let theme: Theme
    let minimumOpacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        let opacity = max(glass.fillOpacity(reduceTransparency: reduceTransparency), minimumOpacity)
        content
            .background(shape.fill(theme.surface.color.opacity(opacity)))
            .clipShape(shape)
            .overlay {
                // The lit rim of a pane of glass: brighter along the top, fading down.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(theme.isDark ? 0.20 : 0.55), .white.opacity(theme.isDark ? 0.04 : 0.15)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            // A thin Jullia-green edge ties the panels to the logo.
            .overlay { shape.strokeBorder(theme.accent.color.opacity(theme.isDark ? 0.38 : 0.45), lineWidth: 1) }
    }
}

private struct WindowTint: ViewModifier {
    let insets: EdgeInsets
    let theme: Theme
    let glass: GlassSetting
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let tint = theme.background.color.opacity(glass.fillOpacity(reduceTransparency: reduceTransparency))
        content.background {
            if insets == EdgeInsets() {
                Rectangle().fill(tint)
            } else {
                PanelCutout(insets: insets, cornerRadius: PanelMetrics.cornerRadius).fill(tint, style: FillStyle(eoFill: true))
            }
        }
    }
}
