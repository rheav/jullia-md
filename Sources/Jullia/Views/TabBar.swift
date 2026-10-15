import AppKit
import JulliaCore
import SwiftUI

/// The open files along the top strip. Tabs share the width up to a comfortable size and scroll past a minimum, so
/// the strip's empty end still drags the window.
struct TabBar: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    private static let widest: CGFloat = 220
    private static let narrowest: CGFloat = 110
    private static let spacing: CGFloat = 4
    /// The + button and some empty strip to drag the window by.
    private static let reserved: CGFloat = 96

    var body: some View {
        let workspace = model.workspace
        GeometryReader { proxy in
            let available = max(0, proxy.size.width - Self.reserved)
            let count = CGFloat(max(workspace.tabs.count, 1))
            let width = min(Self.widest, max(Self.narrowest, (available - Self.spacing * (count - 1)) / count))
            let total = workspace.tabs.isEmpty ? 0 : width * count + Self.spacing * (count - 1)
            HStack(spacing: 6) {
                ScrollViewReader { scroller in
                    ScrollView(.horizontal) {
                        HStack(spacing: Self.spacing) {
                            ForEach(workspace.tabs) { tab in
                                TabChip(tab: tab, theme: theme)
                                    .frame(width: width)
                                    .id(tab.id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(width: min(total, available))
                    .onChange(of: workspace.focusedTab?.id) { _, id in
                        guard let id else { return }
                        withAnimation(.smooth(duration: 0.2)) { scroller.scrollTo(id) }
                    }
                }
                Button {
                    model.presentOpenPanel()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                .help("Abrir arquivo (⌘O)")
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// One tab: icon, name (italic while it is a preview), the pane it shows in when the window is split, and ✕.
private struct TabChip: View {
    let tab: DocumentTab
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let workspace = model.workspace
        let active = workspace.focusedTab?.id == tab.id
        let pane = workspace.paneIndex(of: tab)
        HStack(spacing: 6) {
            if workspace.panes.count > 1, let pane {
                PaneNumber(number: pane + 1, active: active, theme: theme)
            }
            Image(systemName: tab.isPDF ? "doc.richtext" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(active ? theme.accent.color : theme.secondaryText.color)
            Text(tab.name)
                .italic(tab.isPreview)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(active ? theme.heading.color : (pane != nil ? theme.text.color : theme.secondaryText.color))
            Spacer(minLength: 0)
            Button {
                workspace.close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText.color)
            .opacity(hovering || active ? 1 : 0)
            .help("Fechar aba (⌘W)")
        }
        .font(.system(size: 12))
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.accent.color.opacity(theme.isDark ? 0.45 : 0.55), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { workspace.select(tab) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { workspace.pin(tab) })
        .onHover { hovering = $0 }
        .help(tab.isPreview ? "\(tab.url.path)\nPrévia: dê duplo clique para manter a aba" : tab.url.path)
        .contextMenu {
            if tab.isPreview {
                Button("Manter aba") { workspace.pin(tab) }
            }
            Button("Fechar") { workspace.close(tab) }
            Button("Fechar outras") { workspace.closeOthers(than: tab) }
                .disabled(workspace.tabs.count < 2)
            Button("Fechar à direita") { workspace.closeTabsToRight(of: tab) }
                .disabled(workspace.tabs.last?.id == tab.id)
            Divider()
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([tab.url]) }
        }
    }

    private var background: Color {
        let workspace = model.workspace
        if workspace.focusedTab?.id == tab.id { return theme.surface.color }
        if hovering { return theme.text.color.opacity(0.07) }
        return workspace.paneIndex(of: tab) != nil ? theme.text.color.opacity(0.04) : .clear
    }
}

/// The number of the pane a tab shows in, matching the pane's own header.
struct PaneNumber: View {
    let number: Int
    let active: Bool
    let theme: Theme

    var body: some View {
        Text("\(number)")
            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
            .foregroundStyle(active ? theme.background.color : theme.secondaryText.color)
            .frame(width: 15, height: 15)
            .background(active ? theme.accent.color : theme.text.color.opacity(0.1), in: Circle())
    }
}
