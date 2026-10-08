import JulliaCore
import SwiftUI

/// One icon of a folded panel, named in its tooltip, with an optional count.
struct RailButton: View {
    let symbol: String
    let help: String
    let theme: Theme
    var count = 0
    var active = false
    /// Lit up: there is something to act on (a selection to comment).
    var lit = false
    var tone: Color?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(lit || active ? theme.heading.color : (tone ?? theme.secondaryText.color))
                .frame(width: 36, height: 36)
                .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.background.color)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(tone ?? theme.accent.color, in: Capsule())
                            .offset(x: 3, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if active || lit { return theme.accent.color.opacity(0.18) }
        return hovering ? theme.text.color.opacity(0.08) : .clear
    }
}

/// The gear: opens the Settings window from inside the app.
private struct SettingsRailButton: View {
    let theme: Theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        RailButton(symbol: "gearshape", help: "Ajustes (⌘,)", theme: theme) { openSettings() }
    }
}

private struct RailDivider: View {
    let theme: Theme
    var body: some View {
        Capsule().fill(theme.rule.color).frame(width: 20, height: 1).padding(.vertical, 4)
    }
}

/// The file panel folded down to its icons: expand, recent files, the open folders.
struct FileRail: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            RailButton(symbol: "sidebar.left", help: "Expandir arquivos (⌃⌘S)", theme: theme) {
                model.filesCollapsed = false
            }
            RailDivider(theme: theme)
            ForEach(model.recents.prefix(5), id: \.self) { url in
                let count = model.count(for: url)
                RailButton(
                    symbol: "doc.text",
                    help: count > 0 ? "\(url.lastPathComponent) · \(count)" : url.lastPathComponent,
                    theme: theme, count: count, active: model.document?.url == url
                ) {
                    model.openFile(url)
                }
            }
            if !model.roots.isEmpty {
                RailDivider(theme: theme)
                ForEach(model.roots) { root in
                    RailButton(symbol: "folder", help: root.name, theme: theme, tone: theme.accent.color) {
                        model.filesCollapsed = false
                    }
                }
            }
            Spacer(minLength: 0)
            RailButton(symbol: "plus", help: "Abrir pasta…", theme: theme) { model.presentFolderPanel() }
            SettingsRailButton(theme: theme)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// The comments folded down: expand, the open comments (floats the panel out), comment the selection.
struct CommentsRail: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let open = document.topLevelComments.filter { !$0.isResolved }.count
        VStack(spacing: 4) {
            RailButton(symbol: "sidebar.right", help: "Expandir comentários (⌥⌘0)", theme: theme) {
                model.commentsCollapsed = false
            }
            RailDivider(theme: theme)
            RailButton(
                symbol: "text.bubble", help: open > 0 ? "Comentários · \(open)" : "Comentários", theme: theme,
                count: open, active: model.commentsPeek == .pinned, tone: theme.tone(.yellow).stroke.color
            ) {
                model.commentsPeek = model.commentsPeek == .pinned ? nil : .pinned
            }
            RailButton(symbol: "plus.bubble", help: "Comentar o trecho selecionado (⌥⌘M)", theme: theme, lit: document.hasSelection) {
                model.commentSelection()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
