import AppKit
import JulliaCore
import SwiftUI

/// The reading area divided into the workspace's panes: columns side by side, or a 2×2 grid, with dividers to drag.
struct PaneGrid: View {
    let theme: Theme
    @Environment(AppModel.self) private var model
    /// Sizes while a divider is being dragged; saved to the workspace when the drag ends.
    @State private var dragging: [Double]?
    @State private var dragStart: [Double]?

    /// The gap between panes, with the divider line in its middle.
    static let gap: CGFloat = 9
    static let minimumSide: CGFloat = 160

    var body: some View {
        let workspace = model.workspace
        GeometryReader { proxy in
            if workspace.layout == .grid, workspace.panes.count == 4 {
                grid(in: proxy.size)
            } else {
                columns(in: proxy.size)
            }
        }
    }

    // MARK: Columns

    private func columns(in size: CGSize) -> some View {
        let panes = model.workspace.panes
        let fractions = dragging ?? columnFractions(panes.count)
        let usable = max(0, size.width - Self.gap * CGFloat(panes.count - 1))
        return HStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                PaneView(paneID: pane.id, theme: theme)
                    .frame(width: usable * fractions[index])
                if index < panes.count - 1 {
                    DividerHandle(axis: .vertical, theme: theme) { translation in
                        resize(after: index, by: translation / max(usable, 1), current: fractions, count: panes.count)
                    } onEnd: {
                        finishDrag(.columns(panes.count))
                    }
                    .frame(width: Self.gap)
                }
            }
        }
    }

    private func columnFractions(_ count: Int) -> [Double] {
        let layout = PaneLayout.columns(count)
        if let saved = model.workspace.fractions[layout], saved.count == count { return saved }
        return Array(repeating: 1 / Double(count), count: count)
    }

    /// Moves the divider after column `index`: the columns either side trade width, each kept above a minimum.
    private func resize(after index: Int, by delta: Double, current: [Double], count: Int) {
        if dragStart == nil { dragStart = current }
        guard var sizes = dragStart else { return }
        let minimum = 0.08
        let pair = sizes[index] + sizes[index + 1]
        let left = min(max(sizes[index] + delta, minimum), pair - minimum)
        sizes[index] = left
        sizes[index + 1] = pair - left
        dragging = sizes
    }

    private func finishDrag(_ layout: PaneLayout) {
        if let dragging { model.workspace.setFractions(dragging, for: layout) }
        dragging = nil
        dragStart = nil
    }

    // MARK: Grid

    private func grid(in size: CGSize) -> some View {
        let panes = model.workspace.panes
        let split = dragging ?? gridFractions
        let width = max(0, size.width - Self.gap)
        let height = max(0, size.height - Self.gap)
        let columnDivider = DividerHandle(axis: .vertical, theme: theme) { translation in
            dragGrid(column: translation / max(width, 1), row: 0, current: split)
        } onEnd: {
            finishDrag(.grid)
        }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                PaneView(paneID: panes[0].id, theme: theme).frame(width: width * split[0])
                columnDivider.frame(width: Self.gap)
                PaneView(paneID: panes[1].id, theme: theme)
            }
            .frame(height: height * split[1])
            DividerHandle(axis: .horizontal, theme: theme) { translation in
                dragGrid(column: 0, row: translation / max(height, 1), current: split)
            } onEnd: {
                finishDrag(.grid)
            }
            .frame(height: Self.gap)
            HStack(spacing: 0) {
                PaneView(paneID: panes[2].id, theme: theme).frame(width: width * split[0])
                columnDivider.frame(width: Self.gap)
                PaneView(paneID: panes[3].id, theme: theme)
            }
        }
    }

    private var gridFractions: [Double] {
        if let saved = model.workspace.fractions[.grid], saved.count == 2 { return saved }
        return [0.5, 0.5]
    }

    private func dragGrid(column: Double, row: Double, current: [Double]) {
        if dragStart == nil { dragStart = current }
        guard let start = dragStart else { return }
        dragging = [min(max(start[0] + column, 0.15), 0.85), min(max(start[1] + row, 0.15), 0.85)]
    }
}

/// The gap between two panes: a thin line that brightens under the pointer and drags to resize.
private struct DividerHandle: View {
    let axis: Axis
    let theme: Theme
    let onDrag: (Double) -> Void
    let onEnd: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            Rectangle()
                .fill(hovering ? theme.accent.color.opacity(0.7) : theme.rule.color)
                .frame(width: axis == .vertical ? (hovering ? 2 : 1) : nil, height: axis == .horizontal ? (hovering ? 2 : 1) : nil)
        }
        .pointerStyle(axis == .vertical ? .columnResize : .rowResize)
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    onDrag(axis == .vertical ? value.translation.width : value.translation.height)
                }
                .onEnded { _ in onEnd() }
        )
    }
}

/// One pane: a header when the window is split, the document of its tab (or a choice of tabs), and a click anywhere
/// in it focuses it.
struct PaneView: View {
    let paneID: Pane.ID
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let workspace = model.workspace
        if let index = workspace.panes.firstIndex(where: { $0.id == paneID }) {
            let tab = workspace.tab(workspace.panes[index].tabID)
            VStack(spacing: 0) {
                if workspace.panes.count > 1, !model.zen {
                    PaneHeader(index: index, tab: tab, focused: workspace.focusedPane == index, theme: theme)
                }
                if let document = tab?.document {
                    DocumentReader(document: document, theme: theme)
                        .id(document.url)
                } else {
                    EmptyPane(index: index, theme: theme)
                }
            }
            .background(PaneFocusMonitor { [weak workspace] in workspace?.focus(index) })
            .overlay {
                if model.draggedFile != nil {
                    PaneDropTarget(
                        allowsSides: workspace.canAddPane && tab != nil,
                        color: theme.accent.ns
                    ) { url, side in
                        model.dropFile(url, on: index, side: side)
                    }
                }
            }
        }
    }
}

/// Over a pane while a file is dragged from the sidebar: shows where it would land (the whole pane, or the half
/// where a new pane would open) and takes the drop. An AppKit view, so it sits above the PDF and text views, which
/// would otherwise receive the drag.
private struct PaneDropTarget: NSViewRepresentable {
    let allowsSides: Bool
    let color: NSColor
    let onDrop: @MainActor (URL, DropSide) -> Void

    func makeNSView(context: Context) -> DropTargetView {
        let view = DropTargetView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DropTargetView, context: Context) {
        view.allowsSides = allowsSides
        view.color = color
        view.onDrop = onDrop
    }
}

final class DropTargetView: NSView {
    var allowsSides = true
    var color: NSColor = .controlAccentColor
    var onDrop: @MainActor (URL, DropSide) -> Void = { _, _ in }
    private let zone = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        zone.cornerRadius = 10
        zone.borderWidth = 2
        zone.isHidden = true
        layer?.addSublayer(zone)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The outer thirds open a new pane on that side, when there is room for one; the rest replaces the pane's file.
    func side(at point: NSPoint) -> DropSide {
        guard allowsSides, bounds.width > 0 else { return .center }
        if point.x < bounds.width * 0.3 { return .leading }
        if point.x > bounds.width * 0.7 { return .trailing }
        return .center
    }

    func rect(for side: DropSide) -> NSRect {
        let inset = bounds.insetBy(dx: 6, dy: 6)
        switch side {
        case .center: return inset
        case .leading: return NSRect(x: inset.minX, y: inset.minY, width: inset.width / 2, height: inset.height)
        case .trailing: return NSRect(x: inset.midX, y: inset.minY, width: inset.width / 2, height: inset.height)
        }
    }

    /// Lights the part of the pane the file would land in; nil puts it out.
    func highlight(_ side: DropSide?) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        if let side {
            zone.frame = rect(for: side)
            zone.backgroundColor = color.withAlphaComponent(0.16).cgColor
            zone.borderColor = color.withAlphaComponent(0.75).cgColor
        }
        zone.isHidden = side == nil
        CATransaction.commit()
    }

    private func fileURL(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard fileURL(sender) != nil else { return [] }
        highlight(side(at: convert(sender.draggingLocation, from: nil)))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlight(nil) }

    override func draggingEnded(_ sender: NSDraggingInfo) { highlight(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight(nil)
        guard let url = fileURL(sender) else { return false }
        let side = side(at: convert(sender.draggingLocation, from: nil))
        // After the drag session returns: the drop rebuilds the panes, this view included.
        DispatchQueue.main.async { [onDrop] in onDrop(url, side) }
        return true
    }
}

/// A split pane's title: its number (as on its tab), the file, and ✕ to close the pane.
private struct PaneHeader: View {
    let index: Int
    let tab: DocumentTab?
    let focused: Bool
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            PaneNumber(number: index + 1, active: focused, theme: theme)
            if let tab {
                Image(systemName: tab.isPDF ? "doc.richtext" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(focused ? theme.accent.color : theme.secondaryText.color)
                Text(tab.name)
                    .italic(tab.isPreview)
                    .fontWeight(focused ? .semibold : .regular)
                    .foregroundStyle(focused ? theme.heading.color : theme.secondaryText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(tab.url.path)
            } else {
                Text("Painel vazio").foregroundStyle(theme.secondaryText.color)
            }
            Spacer(minLength: 4)
            Button {
                model.workspace.closePane(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText.color)
            .help("Fechar painel (a aba continua aberta)")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { if let tab { model.workspace.pin(tab) } })
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused ? theme.accent.color.opacity(0.8) : theme.rule.color)
                .frame(height: focused ? 2 : 1)
        }
    }
}

/// A pane with nothing in it: the tabs not shown anywhere, to pick one, or a file to open.
private struct EmptyPane: View {
    let index: Int
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let workspace = model.workspace
        let hidden = workspace.tabs.filter { !workspace.isVisible($0) }
        VStack(alignment: .leading, spacing: 10) {
            Text(hidden.isEmpty ? "Nenhuma outra aba aberta" : "Mostrar neste painel")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.heading.color)
            ForEach(hidden) { tab in
                Button {
                    workspace.show(tab, in: index)
                } label: {
                    Label(tab.name, systemImage: tab.isPDF ? "doc.richtext" : "doc.text")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.color)
            }
            Button("Abrir arquivo…") {
                workspace.focus(index)
                model.presentOpenPanel()
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .font(.system(size: 12.5))
        .frame(maxWidth: 280)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Watches mouse-downs in the window and reports the ones inside this view, without taking them from the views that
/// handle them (the PDF and text views run their own tracking).
private struct PaneFocusMonitor: NSViewRepresentable {
    let onClick: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onClick = onClick
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stop()
    }

    final class MonitorView: NSView {
        var onClick: @MainActor () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, event.window === window else { return }
                    if self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.onClick() }
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Never in the way of clicks: the panes' own views receive them.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The layouts of the reading area, as small drawings: one to four columns, and the grid.
struct LayoutPicker: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let workspace = model.workspace
        HStack(spacing: 2) {
            ForEach(PaneLayout.allCases) { layout in
                let active = workspace.layout == layout
                Button {
                    workspace.setLayout(layout)
                } label: {
                    LayoutGlyph(layout: layout, color: active ? theme.accent.color : theme.secondaryText.color)
                        .frame(width: 26, height: 24)
                        .background(active ? theme.accent.color.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(layout.title) (⌥⌘\(PaneLayout.allCases.firstIndex(of: layout)! + 1))")
            }
        }
    }
}

private struct LayoutGlyph: View {
    let layout: PaneLayout
    let color: Color

    var body: some View {
        let cell = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
        Group {
            if layout == .grid {
                VStack(spacing: 1.5) {
                    HStack(spacing: 1.5) { cell.stroke(color, lineWidth: 1.2); cell.stroke(color, lineWidth: 1.2) }
                    HStack(spacing: 1.5) { cell.stroke(color, lineWidth: 1.2); cell.stroke(color, lineWidth: 1.2) }
                }
            } else {
                HStack(spacing: 1.5) {
                    ForEach(0..<layout.slotCount, id: \.self) { _ in cell.stroke(color, lineWidth: 1.2) }
                }
            }
        }
        .frame(width: 17, height: 12)
    }
}
