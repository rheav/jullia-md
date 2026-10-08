import JulliaCore
import SwiftUI

enum Layout {
    /// The strip along the top that holds the traffic lights and the path; panels start below it.
    static let topBar: CGFloat = 50
    static let filesWidth: CGFloat = 264
    static let filesRail: CGFloat = 52
    static let commentsWidth: CGFloat = 312
    static let commentsRail: CGFloat = 44
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var peekTimer: Task<Void, Never>?

    private struct RenderKey: Equatable {
        var theme: ThemeID
        var fontSize: Double
    }

    var body: some View {
        let theme = settings.theme
        let filesInsets = EdgeInsets(top: Layout.topBar, leading: PanelMetrics.gap, bottom: PanelMetrics.gap, trailing: 0)
        let commentsInsets = EdgeInsets(top: Layout.topBar, leading: 0, bottom: PanelMetrics.gap, trailing: PanelMetrics.gap)

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
            .windowTint(around: filesInsets, theme: theme, glass: settings.windowGlass)

            DocumentColumn(theme: theme)
                .frame(minWidth: 420, maxWidth: .infinity)
                .windowTint(around: EdgeInsets(), theme: theme, glass: settings.windowGlass)

            if let document = model.document {
                Group {
                    if model.commentsCollapsed {
                        CommentsRail(document: document, theme: theme)
                            .frame(width: Layout.commentsRail)
                            .onHover { hoverPeek($0) }
                    } else {
                        CommentsSidebar(document: document, theme: theme)
                            .frame(width: Layout.commentsWidth)
                    }
                }
                .glassPanel(settings.commentsGlass, theme: theme)
                .padding(commentsInsets)
                .windowTint(around: commentsInsets, theme: theme, glass: settings.windowGlass)
            }
        }
        .overlay(alignment: .topTrailing) { peekPanel(theme) }
        .animation(.smooth(duration: 0.25), value: model.filesCollapsed)
        .animation(.smooth(duration: 0.25), value: model.commentsCollapsed)
        .animation(.smooth(duration: 0.2), value: model.commentsPeek)
        .background {
            if anyGlass {
                BehindWindowBlur().ignoresSafeArea()
            } else {
                theme.background.color.ignoresSafeArea()
            }
        }
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .tint(theme.accent.color)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { applyAppearance(theme) }
        .onChange(of: theme.id) { applyAppearance(theme) }
        .onChange(of: RenderKey(theme: theme.id, fontSize: settings.fontSize)) { model.rerender() }
        .onChange(of: model.document?.composing) { if model.document?.composing != nil { model.revealComments() } }
        .onExitCommand { model.dismissPeek() }
    }

    private var anyGlass: Bool {
        !reduceTransparency && [settings.windowGlass, settings.filesGlass, settings.commentsGlass].contains { $0.isOn }
    }

    /// The comments floated out of their folded rail, over the text.
    @ViewBuilder
    private func peekPanel(_ theme: Theme) -> some View {
        if model.commentsCollapsed, model.commentsPeek != nil, let document = model.document {
            CommentsSidebar(document: document, theme: theme)
                .frame(width: Layout.commentsWidth)
                .glassPanel(settings.commentsGlass, theme: theme, minimumOpacity: 1)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 22, x: -4, y: 8)
                .padding(.top, Layout.topBar)
                .padding(.bottom, PanelMetrics.gap)
                .padding(.trailing, PanelMetrics.gap + Layout.commentsRail + 6)
                .onHover { hoverPeek($0) }
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Out after a moment's rest on the rail, back after a moment away — passing over it on the way elsewhere does
    /// nothing. A pinned panel stays.
    private func hoverPeek(_ inside: Bool) {
        peekTimer?.cancel()
        peekTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(inside ? 120 : 220))
            guard !Task.isCancelled else { return }
            if inside {
                if model.commentsPeek == nil { model.commentsPeek = .hover }
            } else if model.commentsPeek == .hover {
                model.commentsPeek = nil
            }
        }
    }

    /// System controls (menus, toggles, scrollers) follow the theme's lightness, whatever macOS is set to.
    private func applyAppearance(_ theme: Theme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

/// The middle column: the path in the top strip, over the document.
struct DocumentColumn: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let document = model.document {
                if let error = document.loadError {
                    ContentUnavailableView("Arquivo indisponível", systemImage: "exclamationmark.triangle", description: Text(error))
                        .foregroundStyle(theme.secondaryText.color)
                } else {
                    DocumentTextView(
                        document: document,
                        rendered: document.rendered,
                        renderToken: document.renderToken,
                        decorations: document.decorations(theme: theme),
                        scrollRequest: document.scrollRequest,
                        theme: theme,
                        readingWidth: settings.readingWidth
                    )
                    .id(document.url)
                }
            } else {
                EmptyState(theme: theme)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 5) {
            if let document = model.document {
                Text(document.url.deletingLastPathComponent().lastPathComponent)
                    .foregroundStyle(theme.secondaryText.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.secondaryText.color.opacity(0.7))
                Text(document.url.lastPathComponent)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.heading.color)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .lineLimit(1)
        .help(model.document?.url.path ?? "")
        // Clear of the traffic lights when the file panel is folded to its rail.
        .padding(.leading, model.filesCollapsed ? 28 : 16)
        .padding(.trailing, 16)
        // Centred on the traffic lights' row rather than on the whole strip.
        .frame(height: 32)
        .padding(.top, 2)
        .frame(height: Layout.topBar, alignment: .top)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
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
                Text("Abra uma pasta para navegar pelos seus .md, ou um arquivo solto.")
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
