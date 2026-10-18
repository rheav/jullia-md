import AppKit
import JulliaCore
import SwiftUI

/// The open files along the top strip. Tabs share the width up to a comfortable size and scroll past a minimum, so
/// the strip's empty end still drags the window. A tab dragged along the strip changes places with the tabs it passes.
/// In a split, each pane's tabs sit together, numbered and set apart by a line; a tab dragged among another pane's
/// tabs moves to that pane when it is let go.
struct TabBar: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var drag: Drag?
    @State private var overTabs = false

    /// The tab being dragged: the slot it started in, where along the strip that was, its pane then, and how far the
    /// pointer has taken it from the slot it is in now.
    private struct Drag {
        let tab: DocumentTab.ID
        let start: Int
        let origin: CGFloat
        let group: Int
        var offset: CGFloat
    }

    private static let widest: CGFloat = 220
    private static let narrowest: CGFloat = 110
    private static let spacing: CGFloat = 4
    /// The room a line between two panes' tabs adds.
    private static let boundary: CGFloat = 9
    /// The + button and some empty strip to drag the window by.
    private static let reserved: CGFloat = 96

    var body: some View {
        let workspace = model.workspace
        GeometryReader { proxy in
            let available = max(0, proxy.size.width - Self.reserved)
            let count = CGFloat(max(workspace.tabs.count, 1))
            let lines = CGFloat(boundaries(before: workspace.tabs.count))
            let width = min(Self.widest, max(Self.narrowest, (available - Self.spacing * (count - 1) - Self.boundary * lines) / count))
            let total = workspace.tabs.isEmpty ? 0 : width * count + Self.spacing * (count - 1) + Self.boundary * lines
            HStack(spacing: 6) {
                ScrollViewReader { scroller in
                    ScrollView(.horizontal) {
                        HStack(spacing: Self.spacing) {
                            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                                let dragged = drag?.tab == tab.id
                                if startsGroup(index) {
                                    Capsule()
                                        .fill(theme.rule.color)
                                        .frame(width: 1, height: 16)
                                        .frame(width: Self.boundary - Self.spacing)
                                }
                                TabChip(tab: tab, theme: theme)
                                    .frame(width: width)
                                    .offset(x: dragged ? drag?.offset ?? 0 : 0)
                                    .zIndex(dragged ? 1 : 0)
                                    // The dragged tab stays under the pointer while the others slide.
                                    .transaction { if dragged { $0.animation = nil } }
                                    .gesture(reorder(tab, stride: width + Self.spacing))
                                    .id(tab.id)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(width: min(total, available))
                    .onHover { overTabs = $0 }
                    .background(WindowMoveLock(locked: overTabs || drag != nil))
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

    /// Moves the tab to the slot the pointer has taken it to, past half of each tab on the way. Let go among another
    /// pane's tabs, it moves to that pane.
    private func reorder(_ tab: DocumentTab, stride: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let workspace = model.workspace
                let current = workspace.tabs.firstIndex { $0.id == tab.id } ?? 0
                let begun = drag?.tab == tab.id ? drag : nil
                let start = begun?.start ?? current
                let origin = begun?.origin ?? position(of: current, stride: stride)
                let slot = Self.slot(from: start, moved: value.translation.width, stride: stride, count: workspace.tabs.count)
                if slot != current {
                    withAnimation(.smooth(duration: 0.18)) { workspace.move(tab, to: slot) }
                }
                let now = workspace.tabs.firstIndex { $0.id == tab.id } ?? slot
                drag = Drag(tab: tab.id, start: start, origin: origin, group: begun?.group ?? workspace.group(of: tab),
                            offset: origin + value.translation.width - position(of: now, stride: stride))
            }
            .onEnded { _ in
                let workspace = model.workspace
                let changedPane = drag.map { workspace.group(of: tab) != $0.group } ?? false
                withAnimation(.smooth(duration: 0.18)) { drag = nil }
                if changedPane { workspace.settle(tab) }
            }
    }

    /// Whether the tab at `index` is the first of a pane's tabs after another pane's.
    private func startsGroup(_ index: Int) -> Bool {
        let tabs = model.workspace.tabs
        return index > 0 && index < tabs.count && model.workspace.group(of: tabs[index]) != model.workspace.group(of: tabs[index - 1])
    }

    /// How many lines between panes' tabs come before the tab at `index`.
    private func boundaries(before index: Int) -> Int {
        (0..<max(index, 0)).filter { startsGroup($0) }.count + (startsGroup(index) ? 1 : 0)
    }

    /// Where the tab at `index` starts along the strip.
    private func position(of index: Int, stride: CGFloat) -> CGFloat {
        CGFloat(index) * stride + CGFloat(boundaries(before: index)) * Self.boundary
    }

    /// The slot a tab dragged `moved` points from `start` lands in, tabs being `stride` apart.
    static func slot(from start: Int, moved: CGFloat, stride: CGFloat, count: Int) -> Int {
        guard stride > 0, count > 0 else { return start }
        return min(max(start + Int((moved / stride).rounded()), 0), count - 1)
    }
}

/// Holds the window still while the pointer is over the tabs. The strip sits in the title bar, where the window
/// server would move the whole window with a tab being dragged; anywhere else on the strip still moves it.
private struct WindowMoveLock: NSViewRepresentable {
    let locked: Bool

    final class Lock: NSView {
        var locked = false {
            didSet { window?.isMovable = !locked }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            window?.isMovable = true
            newWindow?.isMovable = !locked
        }
    }

    func makeNSView(context: Context) -> Lock { Lock() }

    func updateNSView(_ view: Lock, context: Context) { view.locked = locked }
}

/// One tab: icon, name (italic while it is a preview), the pane it belongs to when the window is split, and ✕.
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
            if workspace.panes.count > 1 {
                PaneNumber(number: workspace.group(of: tab) + 1, active: active, theme: theme)
                    .opacity(pane != nil ? 1 : 0.55)
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
            Button("Abrir ao lado") { workspace.open(tab.url, as: .beside) }
                .disabled(workspace.isVisible(tab))
            if workspace.panes.count > 1 {
                Menu("Mover para o painel") {
                    ForEach(workspace.panes.indices, id: \.self) { index in
                        Button("Painel \(index + 1)") { workspace.move(tab, toPane: index) }
                            .disabled(workspace.group(of: tab) == index)
                    }
                }
            }
            Divider()
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
