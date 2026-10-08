import AppKit
import MarknordCore
import Observation

/// What the text view paints over the rendered text: highlights, comment underlines, the passage being commented.
struct Decoration: Equatable {
    var range: NSRange
    var background: NSColor?
    var underline: NSColor?
}

struct ScrollRequest: Equatable {
    var range: NSRange
    var token: Int
}

/// A comment being written: about a passage, or about the whole document when `anchor` is nil.
struct Composing: Equatable {
    var anchor: TextAnchor?
}

/// One open Markdown file: its rendered text and the highlights and comments on it.
@MainActor @Observable
final class DocumentModel {
    let url: URL
    let key: String

    private(set) var rendered = NSAttributedString()
    /// Bumped whenever `rendered` is replaced, so the text view knows to reload.
    private(set) var renderToken = 0
    private(set) var loadError: String?

    private(set) var highlights: [Highlight] = []
    private(set) var comments: [Comment] = []
    /// Where each anchored highlight / top-level comment currently sits; missing = orphan.
    private(set) var highlightRanges: [String: NSRange] = [:]
    private(set) var commentRanges: [String: NSRange] = [:]

    var activeCommentID: String?
    var composing: Composing?
    private(set) var scrollRequest: ScrollRequest?

    /// The text view's selection, kept for menu commands. Not observed: it changes on every drag.
    @ObservationIgnored var selection = NSRange(location: 0, length: 0) {
        didSet { if hasSelection != (selection.length > 0) { hasSelection = selection.length > 0 } }
    }
    /// Whether any text is selected — observed, for the rail's "comment the selection" button.
    private(set) var hasSelection = false
    /// Called after any change to annotations, so the sidebar counts follow.
    @ObservationIgnored var onAnnotationsChanged: () -> Void = {}

    @ObservationIgnored private let store: AnnotationStore?
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var options: RenderOptions?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var scrollToken = 0

    var text: NSString { rendered.string as NSString }

    init(url: URL, store: AnnotationStore?) {
        self.url = url
        self.key = documentKey(for: url)
        self.store = store
        highlights = (try? store?.highlights(for: key)) ?? []
        comments = (try? store?.comments(for: key)) ?? []
        readSource()
    }

    func watch(liveReload: @escaping @MainActor () -> Bool) {
        watcher = FileWatcher(url: url) { [weak self] in
            guard let self, liveReload() else { return }
            self.reload()
        }
    }

    // MARK: Rendering

    /// Renders with new options (theme, font size). The text is the same, so anchors stay put.
    func apply(_ options: RenderOptions) {
        let changedText = self.options == nil
        self.options = options
        render()
        if changedText { resolveAnchors() }
    }

    /// Reads the file again and re-anchors everything against the new text.
    func reload() {
        let before = text as String
        readSource()
        render()
        if text as String != before { resolveAnchors() }
    }

    private func readSource() {
        do {
            var encoding = String.Encoding.utf8
            source = try String(contentsOf: url, usedEncoding: &encoding)
            loadError = nil
        } catch {
            loadError = "Não foi possível ler \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func render() {
        guard let options else { return }
        rendered = MarkdownRenderer.render(source, options: options)
        renderToken += 1
    }

    private func resolveAnchors() {
        let text = self.text
        highlightRanges = [:]
        for index in highlights.indices {
            let resolution = Anchoring.resolve(highlights[index].anchor, in: text)
            guard let range = resolution.range else { continue }
            highlightRanges[highlights[index].id] = range
            if case .moved = resolution {
                highlights[index].anchor.start = range.location
                highlights[index].anchor.end = NSMaxRange(range)
                try? store?.setAnchor(highlights[index].anchor, ofHighlight: highlights[index].id)
            }
        }
        commentRanges = [:]
        for index in comments.indices {
            guard let anchor = comments[index].anchor else { continue }
            let resolution = Anchoring.resolve(anchor, in: text)
            guard let range = resolution.range else { continue }
            commentRanges[comments[index].id] = range
            if case .moved = resolution {
                comments[index].anchor?.start = range.location
                comments[index].anchor?.end = NSMaxRange(range)
                try? store?.setAnchor(comments[index].anchor!, ofComment: comments[index].id)
            }
        }
    }

    func decorations(theme: Theme) -> [Decoration] {
        var result: [Decoration] = []
        for highlight in highlights {
            guard let range = highlightRanges[highlight.id] else { continue }
            result.append(Decoration(range: range, background: theme.tone(highlight.color).fill.ns))
        }
        for comment in topLevelComments where !comment.isResolved {
            guard let range = commentRanges[comment.id] else { continue }
            let stroke = theme.tone(comment.color ?? .yellow).stroke
            result.append(Decoration(
                range: range,
                background: comment.id == activeCommentID ? stroke.alpha(theme.isDark ? 0.2 : 0.16).ns : nil,
                underline: stroke.ns
            ))
        }
        if let anchor = composing?.anchor {
            result.append(Decoration(range: anchor.range, background: theme.selection.ns))
        }
        return result
    }

    func scroll(to range: NSRange) {
        scrollToken += 1
        scrollRequest = ScrollRequest(range: range, token: scrollToken)
    }

    // MARK: Highlights

    func highlight(_ range: NSRange, color: MarkColor) {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return }
        if let same = highlights.first(where: { highlightRanges[$0.id] == range }) {
            recolorHighlight(same.id, to: color)
            return
        }
        // A new highlight swallows the ones it covers entirely.
        for covered in highlights where highlightRanges[covered.id].map({ NSIntersectionRange($0, range) == $0 }) == true {
            removeHighlight(covered.id)
        }
        let highlight = Highlight(docPath: key, anchor: Anchoring.make(range: range, in: text), color: color)
        do {
            try store?.insert(highlight)
            highlights.append(highlight)
            highlightRanges[highlight.id] = range
            onAnnotationsChanged()
        } catch {
            NSSound.beep()
        }
    }

    func recolorHighlight(_ id: String, to color: MarkColor) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        try? store?.setColor(color, ofHighlight: id)
        highlights[index].color = color
    }

    func removeHighlight(_ id: String) {
        try? store?.deleteHighlight(id)
        highlights.removeAll { $0.id == id }
        highlightRanges[id] = nil
        onAnnotationsChanged()
    }

    /// The highlight drawn at a character, the most recent one if several overlap.
    func highlight(at location: Int) -> Highlight? {
        highlights.last { highlightRanges[$0.id].map { NSLocationInRange(location, $0) } == true }
    }

    var orphanHighlights: [Highlight] {
        highlights.filter { highlightRanges[$0.id] == nil }
    }

    // MARK: Comments

    var topLevelComments: [Comment] { comments.filter { $0.parentID == nil } }

    func replies(to id: String) -> [Comment] { comments.filter { $0.parentID == id } }

    func isOrphan(_ comment: Comment) -> Bool {
        comment.anchor != nil && commentRanges[comment.id] == nil
    }

    /// Open or resolved comments that still have their place (or are about the whole document): whole-document first,
    /// then in reading order.
    func listedComments(resolved: Bool) -> [Comment] {
        topLevelComments
            .filter { $0.isResolved == resolved && !isOrphan($0) }
            .sorted { lhs, rhs in
                let left = commentRanges[lhs.id]?.location ?? -1
                let right = commentRanges[rhs.id]?.location ?? -1
                return left == right ? lhs.createdAt < rhs.createdAt : left < right
            }
    }

    var orphanComments: [Comment] { topLevelComments.filter(isOrphan) }

    func comment(at location: Int) -> Comment? {
        topLevelComments.last { comment in
            !comment.isResolved && commentRanges[comment.id].map { NSLocationInRange(location, $0) } == true
        }
    }

    func startComment(on range: NSRange?) {
        if let range, range.length > 0, NSMaxRange(range) <= text.length {
            composing = Composing(anchor: Anchoring.make(range: range, in: text))
        } else {
            composing = Composing(anchor: nil)
        }
        activeCommentID = nil
    }

    func submitComment(body: String, color: MarkColor?) {
        guard let composing, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let comment = Comment(docPath: key, anchor: composing.anchor, body: body, color: color)
        do {
            try store?.insert(comment)
            comments.append(comment)
            if let anchor = composing.anchor { commentRanges[comment.id] = anchor.range }
            self.composing = nil
            activeCommentID = comment.id
            onAnnotationsChanged()
        } catch {
            NSSound.beep()
        }
    }

    func reply(to id: String, body: String) {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let reply = Comment(docPath: key, parentID: id, anchor: nil, body: body)
        guard (try? store?.insert(reply)) != nil else { return NSSound.beep() }
        comments.append(reply)
    }

    func edit(_ id: String, body: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? store?.setBody(body, ofComment: id)
        comments[index].body = body
        comments[index].updatedAt = .now
    }

    func setResolved(_ id: String, _ resolved: Bool) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let date: Date? = resolved ? .now : nil
        try? store?.setResolved(date, ofComment: id)
        comments[index].resolvedAt = date
        if resolved, activeCommentID == id { activeCommentID = nil }
        onAnnotationsChanged()
    }

    func recolorComment(_ id: String, to color: MarkColor?) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        try? store?.setColor(color, ofComment: id)
        comments[index].color = color
    }

    func deleteComment(_ id: String) {
        try? store?.deleteComment(id)
        comments.removeAll { $0.id == id || $0.parentID == id }
        commentRanges[id] = nil
        if activeCommentID == id { activeCommentID = nil }
        onAnnotationsChanged()
    }

    /// From the inspector: light the comment up and bring its passage into view.
    func focusComment(_ id: String) {
        activeCommentID = id
        if let range = commentRanges[id] { scroll(to: range) }
    }
}
