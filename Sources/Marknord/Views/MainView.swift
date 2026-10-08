import MarknordCore
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    private struct RenderKey: Equatable {
        var theme: ThemeID
        var fontSize: Double
    }

    var body: some View {
        let theme = settings.theme
        HStack(spacing: 0) {
            if model.showFiles {
                FileSidebar(theme: theme)
                    .frame(width: 264)
                    .glassPanel(settings.filesGlass, theme: theme)
                    .padding([.leading, .vertical], 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            DocumentColumn(theme: theme)
                .frame(minWidth: 420, maxWidth: .infinity)

            if model.showComments, let document = model.document {
                CommentsSidebar(document: document, theme: theme)
                    .frame(width: 312)
                    .glassPanel(settings.commentsGlass, theme: theme)
                    .padding([.trailing, .vertical], 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: model.showFiles)
        .animation(.smooth(duration: 0.25), value: model.showComments)
        .background(WindowBackdrop(theme: theme, glass: settings.windowGlass))
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .tint(theme.accent.color)
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { applyAppearance(theme) }
        .onChange(of: theme.id) { applyAppearance(theme) }
        .onChange(of: RenderKey(theme: theme.id, fontSize: settings.fontSize)) { model.rerender() }
        .onChange(of: model.document?.composing) { if model.document?.composing != nil { model.showComments = true } }
    }

    /// System controls (menus, toggles, scrollers) follow the theme's lightness, whatever macOS is set to.
    private func applyAppearance(_ theme: Theme) {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

/// The middle column: a slim bar (path, sidebar buttons) over the document.
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
        HStack(spacing: 10) {
            if !model.showFiles {
                // Room for the traffic lights.
                Color.clear.frame(width: 64, height: 1)
                barButton("sidebar.left", help: "Mostrar arquivos (⌃⌘S)") { model.showFiles = true }
            }
            if let document = model.document {
                HStack(spacing: 5) {
                    Text(document.url.deletingLastPathComponent().lastPathComponent)
                        .foregroundStyle(theme.secondaryText.color)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryText.color.opacity(0.7))
                    Text(document.url.lastPathComponent)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.heading.color)
                }
                .font(.system(size: 12.5))
                .lineLimit(1)
                .help(document.url.path)
            }
            Spacer(minLength: 12)
            if model.showFiles {
                barButton("sidebar.left", help: "Esconder arquivos (⌃⌘S)") { model.showFiles = false }
            }
            if let document = model.document {
                let open = document.topLevelComments.filter { !$0.isResolved }.count
                Button {
                    model.showComments.toggle()
                } label: {
                    Label(open > 0 ? "\(open)" : "Comentários", systemImage: model.showComments ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.glass)
                .help("Comentários (⌥⌘0)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(height: 50)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        }
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.glass)
        .help(help)
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
