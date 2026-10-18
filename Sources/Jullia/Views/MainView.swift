import AppKit
import JulliaCore
import SwiftUI

enum Layout {
    /// The strip along the top that holds the traffic lights and the path; panels start below it.
    static let topBar: CGFloat = 50
    static let filesWidth: CGFloat = 264
    static let filesRail: CGFloat = 52
    static let commentsRail: CGFloat = 44
    /// The right panel's width, the same for comments, chat and outline: the chat's, the widest, in a roomy window,
    /// and no narrower than the comments header fits on one line.
    static let inspectorWidths: ClosedRange<CGFloat> = 312...360

    /// A share of the window within `inspectorWidths`, so a smaller window or screen gives the document the room.
    static func inspectorWidth(window: CGFloat) -> CGFloat {
        min(max(window * 0.28, inspectorWidths.lowerBound), inspectorWidths.upperBound)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.undoManager) private var undoManager
    @State private var windowWidth: CGFloat?

    private struct RenderKey: Equatable {
        var theme: ThemeID
        var fontSize: Double
    }

    var body: some View {
        let theme = settings.theme
        let filesInsets = EdgeInsets(top: Layout.topBar, leading: PanelMetrics.gap, bottom: PanelMetrics.gap, trailing: 0)
        let commentsInsets = EdgeInsets(top: Layout.topBar, leading: 0, bottom: PanelMetrics.gap, trailing: PanelMetrics.gap)
        let zen = model.zen
        let windowGlass = settings.windowGlass

        HStack(spacing: 0) {
            Group {
                if model.filesCollapsed {
                    FileRail(theme: theme).frame(width: Layout.filesRail)
                } else {
                    FileSidebar(theme: theme).frame(width: Layout.filesWidth)
                }
            }
            .glassPanel(settings.filesGlass, theme: theme)
            .padding(filesInsets)
            .windowTint(around: filesInsets, theme: theme, glass: windowGlass)
            .zenHidden(zen, alignment: .leading)

            DocumentColumn(theme: theme)
                .frame(minWidth: 420, maxWidth: .infinity)
                .windowTint(around: EdgeInsets(), theme: theme, glass: windowGlass)

            if let document = model.document {
                Group {
                    if model.commentsCollapsed {
                        CommentsRail(document: document, theme: theme)
                            .frame(width: Layout.commentsRail)
                    } else {
                        InspectorSidebar(document: document, theme: theme)
                            .frame(width: windowWidth.map(Layout.inspectorWidth) ?? Layout.inspectorWidths.upperBound)
                    }
                }
                .glassPanel(settings.commentsGlass, theme: theme)
                .padding(commentsInsets)
                .windowTint(around: commentsInsets, theme: theme, glass: windowGlass)
                .zenHidden(zen, alignment: .trailing)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.filesCollapsed)
        .animation(.smooth(duration: 0.25), value: model.commentsCollapsed)
        .animation(.smooth(duration: 0.3), value: zen)
        .overlay(alignment: .top) {
            if model.zenHint {
                ZenHint(theme: theme)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.zenHint)
        .overlay(alignment: .topTrailing) {
            if zen {
                ZenExitButton(theme: theme)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .background {
            if zen { ZenEscapeMonitor { model.setZen(false) } }
        }
        .background {
            if anyGlass {
                BehindWindowBlur().ignoresSafeArea()
            } else {
                theme.background.color.ignoresSafeArea()
            }
        }
        .background(WindowConfigurator(hidesButtons: zen))
        .ignoresSafeArea()
        .tint(theme.accent.color)
        .frame(minWidth: 760, minHeight: 480)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onAppear {
            applyAppearance(theme)
            model.undoManager = undoManager
        }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onChange(of: theme.id) { applyAppearance(theme) }
        .onChange(of: RenderKey(theme: theme.id, fontSize: settings.fontSize)) { model.rerender() }
        .onChange(of: model.document?.composing) { if model.document?.composing != nil { model.revealComments() } }
    }

    private var anyGlass: Bool {
        !reduceTransparency && [settings.windowGlass, settings.filesGlass, settings.commentsGlass].contains { $0.isOn }
    }

    /// System controls (menus, toggles, scrollers) follow the theme's lightness, whatever macOS is set to.
    private func applyAppearance(_ theme: Theme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

/// The middle column: the tabs in the top strip, over the document.
struct DocumentColumn: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            if !model.zen {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.workspace.tabs.isEmpty {
                EmptyState(theme: theme)
            } else {
                PaneGrid(theme: theme)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            if !model.workspace.tabs.isEmpty {
                TabBar(theme: theme)
                LayoutPicker(theme: theme)
                ZenButton(theme: theme)
            }
            Spacer(minLength: 0)
        }
        // Clear of the traffic lights when the file panel is folded to its rail.
        .padding(.leading, model.filesCollapsed ? 28 : 10)
        .padding(.trailing, 12)
        // Centred on the traffic lights' row rather than on the whole strip.
        .frame(height: 32)
        .padding(.top, 2)
        .frame(height: Layout.topBar, alignment: .top)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        }
    }
}

/// Into zen from the top strip; Esc or ⌃⌘Z brings everything back.
private struct ZenButton: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.toggleZen()
        } label: {
            Image(systemName: "viewfinder")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondaryText.color)
        .pointerStyle(.link)
        .help("Modo zen: só os documentos (⌃⌘Z)")
    }
}

/// Zen's one control: the way back, quiet until the pointer is on it.
private struct ZenExitButton: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.setZen(false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hovering ? theme.heading.color : theme.secondaryText.color)
                .frame(width: 28, height: 28)
                .background(theme.surface.color.opacity(hovering ? 0.95 : 0.6), in: Circle())
                .overlay { Circle().strokeBorder(theme.rule.color, lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.55)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help("Sair do modo zen (Esc ou ⌃⌘Z)")
        .accessibilityLabel("Sair do modo zen")
    }
}

/// Esc leaves zen from anywhere in this window, even while the PDF or the text has the keyboard: a menu shortcut
/// cannot carry a bare Esc, and those views take it before SwiftUI sees it. Other windows and modal panels keep
/// their own Esc.
private struct ZenEscapeMonitor: NSViewRepresentable {
    let onEscape: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onEscape = onEscape
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stop()
    }

    final class MonitorView: NSView {
        var onEscape: @MainActor () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                else { return event }
                let eventWindow = event.window
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, eventWindow === window,
                          NSApp.modalWindow == nil, window.attachedSheet == nil else { return false }
                    // A field being typed in, such as a find bar, gets the Esc to close itself.
                    if let editor = window.firstResponder as? NSTextView, editor.isEditable { return false }
                    self.onEscape()
                    return true
                }
                return handled ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The note shown for a moment when zen starts: the only way out is not on screen.
private struct ZenHint: View {
    let theme: Theme

    var body: some View {
        Text("Modo zen · Esc para sair")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(theme.text.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.surface.color.opacity(0.94), in: Capsule())
            .overlay { Capsule().strokeBorder(theme.rule.color, lineWidth: 1) }
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.12), radius: 14, y: 4)
            .padding(.top, 18)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Out of sight in zen but kept alive, so a draft, a list's scroll or the chat tab are where they were when zen
    /// ends.
    func zenHidden(_ hidden: Bool, alignment: Alignment) -> some View {
        frame(width: hidden ? 0 : nil, alignment: alignment)
            .clipped()
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// One document as it reads: the PDF reader or the rendered Markdown, or why the file could not be opened.
struct DocumentReader: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let error = document.loadError {
            ContentUnavailableView("Arquivo indisponível", systemImage: "exclamationmark.triangle", description: Text(error))
                .foregroundStyle(theme.secondaryText.color)
        } else if document.isPDF {
            PDFReader(document: document, theme: theme)
        } else {
            DocumentTextView(
                document: document,
                rendered: document.rendered,
                renderToken: document.renderToken,
                decorations: document.decorations(theme: theme),
                scrollRequest: document.scrollRequest,
                findRequest: document.findRequest,
                theme: theme,
                readingWidth: settings.readingWidth
            )
        }
    }
}

struct EmptyState: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.document")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(theme.accent.color)
            VStack(spacing: 6) {
                Text("Nada aberto ainda")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.heading.color)
                Text("Abra uma pasta para navegar pelos seus Markdown e PDFs, ou um arquivo solto.")
                    .foregroundStyle(theme.secondaryText.color)
            }
            HStack(spacing: 10) {
                Button("Abrir pasta…") { model.presentFolderPanel() }
                    .buttonStyle(.glassProminent)
                Button("Abrir arquivo…") { model.presentOpenPanel() }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(model.open)
            return !urls.isEmpty
        }
    }
}
