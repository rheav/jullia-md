import AppKit
import MarknordCore
import SwiftUI

/// The blurred desktop behind the window.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// The window's own background: the theme colour, laid over the blurred desktop as thinly as the window glass allows.
struct WindowBackdrop: View {
    let theme: Theme
    let glass: GlassSetting
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if glass.isGlassy(reduceTransparency: reduceTransparency) {
                BehindWindowBlur()
            }
            theme.background.color.opacity(glass.fillOpacity(reduceTransparency: reduceTransparency))
        }
        .ignoresSafeArea()
    }
}

/// Lets the window itself be see-through, so the backdrop can show the desktop.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

extension View {
    /// A floating panel (file sidebar, comments) in Liquid Glass, tinted by the theme as strongly as its setting says.
    func glassPanel(_ glass: GlassSetting, theme: Theme, cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassPanel(glass: glass, theme: theme, cornerRadius: cornerRadius))
    }
}

private struct GlassPanel: ViewModifier {
    let glass: GlassSetting
    let theme: Theme
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let opacity = glass.fillOpacity(reduceTransparency: reduceTransparency)
        if glass.isGlassy(reduceTransparency: reduceTransparency) {
            content
                .background(shape.fill(theme.surface.color.opacity(opacity)))
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(theme.surface.color))
                .clipShape(shape)
                .overlay(shape.strokeBorder(theme.rule.color))
                .shadow(color: .black.opacity(theme.isDark ? 0.25 : 0.08), radius: 10, y: 4)
        }
    }
}
