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
/// two views never edit the same annotations from different models.
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
        if kind == .preview, let index = tabs.firstIndex(where: \.isPreview) {
            let old = tabs[index]
            if let pane = paneIndex(of: old), pane != focusedPane {
                // Showing in another pane: keep it there rather than swap the file under the reader.
                old.isPreview = false
                insert(tab)
            } else {
                tabs[index] = tab
                for pane in panes.indices where panes[pane].tabID == old.id { panes[pane].tabID = tab.id }
                unload(old)
            }
        } else {
            insert(tab)
        }
        if kind == .beside { placeBeside(tab) } else { show(tab, in: focusedPane) }
        return tab
    }

    /// Right after the focused pane's tab.
    private func insert(_ tab: DocumentTab) {
        let after = focusedTab.flatMap { focused in tabs.firstIndex { $0.id == focused.id } }
        tabs.insert(tab, at: after.map { $0 + 1 } ?? tabs.endIndex)
    }

    /// A tab already in a pane focuses that pane; otherwise it moves into the focused pane.
    func select(_ tab: DocumentTab) {
        if let pane = paneIndex(of: tab) { focus(pane) } else { show(tab, in: focusedPane) }
    }

    func show(_ tab: DocumentTab, in pane: Int) {
        guard panes.indices.contains(pane) else { return }
        if let other = paneIndex(of: tab), other != pane { return focus(other) }
        panes[pane].tabID = tab.id
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

    /// The tab after (or before) the focused one, wrapping around.
    func selectAdjacentTab(_ offset: Int) {
        guard !tabs.isEmpty else { return }
        let current = focusedTab.flatMap { focused in tabs.firstIndex { $0.id == focused.id } } ?? 0
        select(tabs[(current + offset + tabs.count) % tabs.count])
    }

    // MARK: Closing

    /// Closes a tab. A pane that showed it takes the nearest tab not shown elsewhere; in a split, a pane left empty
    /// closes.
    func close(_ tab: DocumentTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        unload(tab)
        var emptied: Pane.ID?
        for pane in panes.indices where panes[pane].tabID == tab.id {
            let replacement = tabs[index...].first { !isVisible($0) } ?? tabs[..<index].last { !isVisible($0) }
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

    /// Divides the reading area. New panes take the next tabs not shown; panes past the new count close, their tabs
    /// stay in the bar.
    func setLayout(_ layout: PaneLayout) {
        let count = layout.slotCount
        if panes.count > count {
            panes.removeLast(panes.count - count)
            focusedPane = min(focusedPane, count - 1)
        }
        while panes.count < count {
            var pane = Pane()
            if let next = nextHiddenTab() {
                pane.tabID = next.id
                if next.document == nil { load(next) }
            }
            panes.append(pane)
        }
        self.layout = layout
        onChange()
    }

    /// Opens a tab in a new pane right of the focused one; with every pane in use, in the next pane.
    private func placeBeside(_ tab: DocumentTab) {
        if panes[focusedPane].tabID == nil { return show(tab, in: focusedPane) }
        if panes.count < Self.maxPanes {
            var pane = Pane()
            pane.tabID = tab.id
            panes.insert(pane, at: focusedPane + 1)
            layout = .columns(panes.count)
            focusedPane += 1
            if tab.document == nil { load(tab) }
            onChange()
        } else {
            show(tab, in: (focusedPane + 1) % panes.count)
        }
    }

    /// Closes a pane; its tab stays in the bar.
    func closePane(_ pane: Int) {
        guard panes.count > 1, panes.indices.contains(pane) else { return }
        removePane(pane)
        onChange()
    }

    private func removePane(_ pane: Int) {
        panes.remove(at: pane)
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
            tabs: tabs.map { Session.SavedTab(path: $0.url.path, preview: $0.isPreview) },
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
        for pane in panes {
            if let tab = tab(pane.tabID), tab.document == nil { load(tab) }
        }
        onChange()
    }
}
