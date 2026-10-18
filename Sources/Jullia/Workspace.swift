import Foundation
import Observation

/// One open file in the tab bar. Its document is loaded the first time the tab is shown, so a restored session with
/// many tabs opens quickly.
@MainActor @Observable
final class DocumentTab: Identifiable {
    let id = UUID()
    let url: URL
    /// A preview tab (italic) is replaced by the next file opened from the sidebar, until it is kept.
    var isPreview: Bool
    var document: DocumentModel?
    /// The pane this tab belongs to, by position: clicking it shows it there. With fewer panes than that, it belongs
    /// to the last one, and goes back to its own when the window is divided again.
    var home = 0

    init(url: URL, isPreview: Bool) {
        self.url = url
        self.isPreview = isPreview
    }

    var name: String { url.lastPathComponent }
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }

    func matches(_ url: URL) -> Bool {
        self.url.standardizedFileURL == url.standardizedFileURL
    }
}

/// One reading area of the window, showing one tab (or none).
struct Pane: Identifiable, Equatable {
    let id = UUID()
    var tabID: DocumentTab.ID?
}

/// How a file is opened.
enum OpenKind {
    /// From the sidebar, a link or the rail: in the preview tab, replacing the previous preview.
    case preview
    /// Kept: double-click, the Open panel, Finder, a drop.
    case permanent
    /// In a new kept tab, from a menu.
    case newTab
    /// In a new pane beside the focused one.
    case beside
}

/// Where a file dragged onto a pane lands: in the pane, or in a new pane on one side of it.
enum DropSide: Equatable {
    case center, leading, trailing
}

/// How the reading area is divided.
enum PaneLayout: String, CaseIterable, Codable, Identifiable {
    case one, two, three, four, grid

    var id: Self { self }

    /// How many panes the layout holds.
    var slotCount: Int {
        switch self {
        case .one: 1
        case .two: 2
        case .three: 3
        case .four, .grid: 4
        }
    }

    /// The columns layout for a number of panes.
    static func columns(_ count: Int) -> PaneLayout {
        switch count {
        case ...1: .one
        case 2: .two
        case 3: .three
        default: .four
        }
    }

    var title: String {
        switch self {
        case .one: "Um painel"
        case .two: "Duas colunas"
        case .three: "Três colunas"
        case .four: "Quatro colunas"
        case .grid: "Grade 2×2"
        }
    }
}

/// The tabs and panes saved between launches.
struct Session: Codable, Equatable {
    struct SavedTab: Codable, Equatable {
        var path: String
        var preview: Bool
        /// The pane the tab belongs to; sessions from before panes had their own tabs leave it out.
        var pane: Int?
    }

    var tabs: [SavedTab]
    /// For each pane, the index of its tab in `tabs`.
    var panes: [Int?]
    var focused: Int
    var layout: PaneLayout?
    /// Divider positions per layout, as fractions of the reading area.
    var fractions: [String: [Double]]?
}

/// The tabs and the panes showing them. A file is open in at most one tab, and a tab shows in at most one pane, so
/// two views never edit the same annotations from different models. Each tab belongs to a pane, which shows one of
/// its own tabs; the bar keeps each pane's tabs together, in pane order.
@MainActor @Observable
final class Workspace {
    private(set) var tabs: [DocumentTab] = []
    private(set) var panes: [Pane] = [Pane()]
    private(set) var focusedPane = 0
    private(set) var layout: PaneLayout = .one
    /// Pane sizes per layout: column widths summing to 1, or `[left column, top row]` for the grid.
    private(set) var fractions: [PaneLayout: [Double]] = [:]

    /// Creates a tab's document when the tab is first shown.
    @ObservationIgnored var load: (DocumentTab) -> Void = { _ in }
    /// Lets go of a closed or replaced tab's document.
    @ObservationIgnored var unload: (DocumentTab) -> Void = { _ in }
    /// After any change worth saving: tabs, panes, focus, layout.
    @ObservationIgnored var onChange: () -> Void = {}

    static let maxPanes = 4

    var focusedTab: DocumentTab? { tab(panes[focusedPane].tabID) }

    func tab(_ id: DocumentTab.ID?) -> DocumentTab? {
        guard let id else { return nil }
        return tabs.first { $0.id == id }
    }

    func tab(for url: URL) -> DocumentTab? {
        tabs.first { $0.matches(url) }
    }

    func paneIndex(of tab: DocumentTab) -> Int? {
        panes.firstIndex { $0.tabID == tab.id }
    }

    func isVisible(_ tab: DocumentTab) -> Bool {
        paneIndex(of: tab) != nil
    }

    /// The pane a tab belongs to now: its own, or the last one while there are fewer panes.
    func group(of tab: DocumentTab) -> Int {
        min(tab.home, panes.count - 1)
    }

    // MARK: Opening and selecting

    /// Opens `url` in a tab, reusing the one that already has it, and shows it.
    @discardableResult
    func open(_ url: URL, as kind: OpenKind) -> DocumentTab {
        if let existing = tab(for: url) {
            if kind != .preview { existing.isPreview = false }
            if kind == .beside, !isVisible(existing) { placeBeside(existing) } else { select(existing) }
            onChange()
            return existing
        }
        let tab = DocumentTab(url: url, isPreview: kind == .preview)
        tab.home = focusedPane
        if kind == .preview, let index = tabs.firstIndex(where: \.isPreview) {
            let old = tabs[index]
            if let pane = paneIndex(of: old), pane != focusedPane {
                // Showing in another pane: keep it there rather than swap the file under the reader.
                old.isPreview = false
                insert(tab)
            } else if group(of: old) == focusedPane {
                tabs[index] = tab
                for pane in panes.indices where panes[pane].tabID == old.id { panes[pane].tabID = tab.id }
                unload(old)
            } else {
                // Another pane's preview, not on screen: it goes, and the new one joins the focused pane's tabs.
                tabs.remove(at: index)
                unload(old)
                insert(tab)
            }
        } else {
            insert(tab)
        }
        if kind == .beside { placeBeside(tab) } else { show(tab, in: focusedPane) }
        return tab
    }

    /// Among its pane's tabs: right after the focused tab when that is one of them, otherwise after the last.
    private func insert(_ tab: DocumentTab) {
        let group = group(of: tab)
        let after = focusedTab.flatMap { focused in
            self.group(of: focused) == group ? tabs.firstIndex { $0.id == focused.id } : nil
        } ?? tabs.lastIndex { self.group(of: $0) <= group }
        tabs.insert(tab, at: after.map { $0 + 1 } ?? 0)
    }

    /// A tab already in a pane focuses that pane; otherwise it shows in the pane it belongs to.
    func select(_ tab: DocumentTab) {
        if let pane = paneIndex(of: tab) { focus(pane) } else { show(tab, in: group(of: tab)) }
    }

    /// Shows a tab in a pane, which it belongs to from then on. A tab already in another pane focuses that pane.
    func show(_ tab: DocumentTab, in pane: Int) {
        guard panes.indices.contains(pane) else { return }
        if let other = paneIndex(of: tab), other != pane { return focus(other) }
        panes[pane].tabID = tab.id
        if group(of: tab) != pane {
            tab.home = pane
            regroup()
        }
        if tab.document == nil { load(tab) }
        focusedPane = pane
        onChange()
    }

    func focus(_ pane: Int) {
        guard panes.indices.contains(pane), pane != focusedPane else { return }
        focusedPane = pane
        onChange()
    }

    /// Keeps a preview tab: the next file from the sidebar opens in a tab of its own.
    func pin(_ tab: DocumentTab) {
        guard tab.isPreview else { return }
        tab.isPreview = false
        onChange()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    /// The tab after (or before) the focused one among the focused pane's tabs, wrapping around.
    func selectAdjacentTab(_ offset: Int) {
        let own = tabs.filter { group(of: $0) == focusedPane }
        guard !own.isEmpty else { return }
        let current = focusedTab.flatMap { focused in own.firstIndex { $0.id == focused.id } } ?? 0
        select(own[(current + offset + own.count) % own.count])
    }

    /// Puts a tab at another place in the bar, as when it is dragged there. Among another pane's tabs it belongs to
    /// that pane; where two panes' tabs meet, it stays with its own. The panes change only with `settle`, when the
    /// drag ends, so they do not flicker while the tab passes.
    func move(_ tab: DocumentTab, to index: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let to = min(max(index, 0), tabs.count - 1)
        if from != to { tabs.insert(tabs.remove(at: from), at: to) }
        let lower = to > 0 ? group(of: tabs[to - 1]) : 0
        let upper = to < tabs.count - 1 ? group(of: tabs[to + 1]) : panes.count - 1
        let group = min(max(group(of: tab), lower), upper)
        guard from != to || group != self.group(of: tab) else { return }
        if group != self.group(of: tab) { tab.home = group }
        onChange()
    }

    /// Moves a tab to the end of another pane's tabs and shows it there.
    func move(_ tab: DocumentTab, toPane pane: Int) {
        guard panes.indices.contains(pane), paneIndex(of: tab) != pane else { return }
        tabs.removeAll { $0.id == tab.id }
        tab.home = pane
        tabs.insert(tab, at: (tabs.lastIndex { group(of: $0) <= pane } ?? -1) + 1)
        settle(tab)
    }

    /// After a tab changed panes: the pane showing it shows another of its own tabs, or closes when it has none
    /// left, and the tab shows in its new pane.
    func settle(_ tab: DocumentTab) {
        if let from = paneIndex(of: tab), from != group(of: tab) {
            if let next = tabs.first(where: { group(of: $0) == from && !isVisible($0) }) {
                panes[from].tabID = next.id
                if next.document == nil { load(next) }
            } else {
                panes[from].tabID = nil
                if panes.count > 1 { removePane(from) }
            }
        }
        show(tab, in: group(of: tab))
    }

    /// Keeps each pane's tabs together in the bar, in pane order, and otherwise in their order.
    private func regroup() {
        let grouped = tabs.enumerated()
            .sorted { (group(of: $0.element), $0.offset) < (group(of: $1.element), $1.offset) }
            .map(\.element)
        if grouped.map(\.id) != tabs.map(\.id) { tabs = grouped }
    }

    // MARK: Closing

    /// Closes a tab. A pane that showed it takes the nearest of its other tabs; in a split, a pane left with none
    /// closes.
    func close(_ tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        let group = group(of: tab)
        tabs.remove(at: index)
        unload(tab)
        var emptied: Pane.ID?
        for pane in panes.indices where panes[pane].tabID == tab.id {
            let own = { (other: DocumentTab) in self.group(of: other) == group && !self.isVisible(other) }
            let replacement = tabs[index...].first(where: own) ?? tabs[..<index].last(where: own)
            panes[pane].tabID = replacement?.id
            if let replacement, replacement.document == nil { load(replacement) }
            if replacement == nil { emptied = panes[pane].id }
        }
        if panes.count > 1, let emptied, let pane = panes.firstIndex(where: { $0.id == emptied }) {
            removePane(pane)
        }
        onChange()
    }

    func closeOthers(than tab: DocumentTab) {
        for other in tabs where other.id != tab.id { close(other) }
        select(tab)
    }

    func closeTabsToRight(of tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        for other in tabs[(index + 1)...] { close(other) }
    }

    // MARK: Panes

    /// Divides the reading area. A new pane gets back the tabs that belonged to it before, or else takes the next
    /// tab not shown; panes past the new count close, and their tabs join the last pane.
    func setLayout(_ layout: PaneLayout) {
        let count = layout.slotCount
        if panes.count > count {
            panes.removeLast(panes.count - count)
            focusedPane = min(focusedPane, count - 1)
        }
        while panes.count < count {
            let index = panes.count
            panes.append(Pane())
            let returning = tabs.first { $0.home == index && !isVisible($0) }
            if let next = returning ?? nextHiddenTab() {
                next.home = index
                panes[index].tabID = next.id
                if next.document == nil { load(next) }
            }
        }
        self.layout = layout
        regroup()
        onChange()
    }

    /// Opens a tab in a new pane right of the focused one; with every pane in use, in the next pane.
    private func placeBeside(_ tab: DocumentTab) {
        if panes[focusedPane].tabID == nil { return show(tab, in: focusedPane) }
        if panes.count < Self.maxPanes {
            insertPane(at: focusedPane + 1, showing: tab)
        } else {
            show(tab, in: (focusedPane + 1) % panes.count)
        }
    }

    /// A new pane at `index`, showing a tab that belongs to it; the tabs of the panes after it move along with them.
    private func insertPane(at index: Int, showing tab: DocumentTab) {
        for other in tabs where other.home >= index { other.home += 1 }
        var pane = Pane()
        pane.tabID = tab.id
        panes.insert(pane, at: index)
        layout = .columns(panes.count)
        focusedPane = index
        tab.home = index
        regroup()
        if tab.document == nil { load(tab) }
        onChange()
    }

    /// Whether a drop on a pane's side can open a new pane there: columns, with room for one more.
    var canAddPane: Bool { layout != .grid && panes.count < Self.maxPanes }

    /// A file dropped on a pane: in that pane (center), or in a new pane beside it. A file already on screen keeps
    /// its pane, which is focused.
    func drop(_ url: URL, on pane: Int, side: DropSide) {
        guard panes.indices.contains(pane) else { return }
        let tab: DocumentTab
        if let existing = self.tab(for: url) {
            tab = existing
        } else {
            tab = DocumentTab(url: url, isPreview: false)
            tab.home = pane
            insert(tab)
        }
        tab.isPreview = false
        if let shown = paneIndex(of: tab) { return show(tab, in: shown) }
        guard side != .center, canAddPane, panes[pane].tabID != nil else { return show(tab, in: pane) }
        insertPane(at: side == .leading ? pane : pane + 1, showing: tab)
    }

    /// Closes a pane; its tabs stay in the bar, with the pane to its left (or, for the first, to its right).
    func closePane(_ pane: Int) {
        guard panes.count > 1, panes.indices.contains(pane) else { return }
        removePane(pane)
        onChange()
    }

    private func removePane(_ pane: Int) {
        panes.remove(at: pane)
        for tab in tabs where tab.home > pane || (tab.home == pane && pane > 0) { tab.home -= 1 }
        regroup()
        layout = layout == .grid && panes.count == 4 ? .grid : .columns(panes.count)
        if focusedPane > pane || focusedPane >= panes.count { focusedPane = max(0, focusedPane - 1) }
    }

    /// The first tab no pane shows, looking right of the focused tab first.
    private func nextHiddenTab() -> DocumentTab? {
        let start = focusedTab.flatMap { focused in tabs.firstIndex { $0.id == focused.id } } ?? -1
        let ordered = tabs[(start + 1)...] + tabs[..<max(0, start + 1)]
        return ordered.first { !isVisible($0) }
    }

    func setFractions(_ values: [Double], for layout: PaneLayout) {
        fractions[layout] = values
        onChange()
    }

    // MARK: Session

    var session: Session {
        Session(
            tabs: tabs.map { Session.SavedTab(path: $0.url.path, preview: $0.isPreview, pane: $0.home) },
            panes: panes.map { pane in tabs.firstIndex { $0.id == pane.tabID } },
            focused: focusedPane,
            layout: layout,
            fractions: Dictionary(uniqueKeysWithValues: fractions.map { ($0.key.rawValue, $0.value) })
        )
    }

    /// Reopens saved tabs whose files still exist, loading only the ones shown.
    func restore(_ session: Session, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        var restored: [Int: DocumentTab] = [:]
        tabs = []
        for (index, saved) in session.tabs.enumerated() where fileExists(saved.path) {
            let tab = DocumentTab(url: URL(fileURLWithPath: saved.path), isPreview: saved.preview)
            tab.home = max(saved.pane ?? 0, 0)
            restored[index] = tab
            tabs.append(tab)
        }
        var seen = Set<DocumentTab.ID>()
        panes = session.panes.prefix(Self.maxPanes).map { index in
            var pane = Pane()
            if let index, let tab = restored[index], seen.insert(tab.id).inserted { pane.tabID = tab.id }
            return pane
        }
        if panes.isEmpty { panes = [Pane()] }
        let saved = session.layout ?? .one
        layout = saved.slotCount == panes.count ? saved : .columns(panes.count)
        fractions = Dictionary(uniqueKeysWithValues: (session.fractions ?? [:]).compactMap { key, value in
            PaneLayout(rawValue: key).map { ($0, value) }
        })
        focusedPane = min(max(session.focused, 0), panes.count - 1)
        // Before panes had their own tabs, a tab belonged to the pane showing it.
        for (index, pane) in panes.enumerated() {
            if let tab = tab(pane.tabID), session.tabs.allSatisfy({ $0.pane == nil }) { tab.home = index }
        }
        regroup()
        for pane in panes {
            if let tab = tab(pane.tabID), tab.document == nil { load(tab) }
        }
        onChange()
    }
}
