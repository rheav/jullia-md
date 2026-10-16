import AppKit
import Observation
import PDFKit

/// The find commands, sent to the focused document: Markdown hands them to AppKit's find bar, a PDF to `PDFFind`.
enum FindAction {
    case show, next, previous, useSelection

    /// The same command for the text view's `NSTextFinder`.
    var textFinderAction: NSTextFinder.Action {
        switch self {
        case .show: .showFindInterface
        case .next: .nextMatch
        case .previous: .previousMatch
        case .useSelection: .setSearchString
        }
    }
}

/// A find command for the Markdown text view, with a token so each one is carried out once.
struct FindRequest: Equatable {
    var action: FindAction
    var token: Int
}

/// Searching a PDF, which PDFKit leaves to the app: the query, its matches and the one shown. Matching ignores case
/// and accents, as the text's find bar does, and starts on the reader's page. The query goes to the find pasteboard,
/// so ⌘G and other apps' find bars share it.
@MainActor @Observable
final class PDFFind {
    private(set) var isVisible = false
    /// What is searched for. Setting it searches again.
    var query = "" { didSet { if query != oldValue { search() } } }
    private(set) var matches: [PDFSelection] = []
    /// The match on screen, an index in `matches`.
    private(set) var current: Int?
    /// Bumped whenever the view should show the current match again.
    private(set) var revealToken = 0
    /// Bumped by ⌘F, so the field takes the focus even when the bar is already open.
    private(set) var focusToken = 0

    @ObservationIgnored var pasteboard = NSPasteboard(name: .find)
    /// The page the reader is on, zero-based.
    @ObservationIgnored var startPage: () -> Int = { 0 }
    @ObservationIgnored private weak var document: PDFDocument?

    /// A new or reloaded document: earlier matches belong to the old one.
    func attach(_ document: PDFDocument?) {
        self.document = document
        search()
    }

    func perform(_ action: FindAction, selectedText: String?) {
        switch action {
        case .show:
            if query.isEmpty { query = sharedQuery }
            isVisible = true
            focusToken += 1
        case .next:
            step(1)
        case .previous:
            step(-1)
        case .useSelection:
            let text = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return NSSound.beep() }
            query = text
            share()
        }
    }

    /// The next match (1) or the previous one (-1), wrapping around the document.
    func step(_ direction: Int) {
        if query.isEmpty { query = sharedQuery }
        guard !matches.isEmpty else { return NSSound.beep() }
        let from = current ?? (direction > 0 ? -1 : 0)
        current = (from + direction + matches.count) % matches.count
        revealToken += 1
        share()
    }

    func close() {
        isVisible = false
        share()
    }

    private func search() {
        guard let document, !query.isEmpty else {
            matches = []
            current = nil
            return
        }
        matches = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
        let page = startPage()
        current = matches.isEmpty ? nil : matches.firstIndex { selection in
            selection.pages.first.map { document.index(for: $0) >= page } ?? false
        } ?? 0
        revealToken += 1
    }

    private var sharedQuery: String { pasteboard.string(forType: .string) ?? "" }

    private func share() {
        guard !query.isEmpty, query != sharedQuery else { return }
        pasteboard.clearContents()
        pasteboard.setString(query, forType: .string)
    }
}
