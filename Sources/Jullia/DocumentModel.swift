import AppKit
import JulliaCore
import Observation
import PDFKit

/// What the text view paints over the rendered text: highlights, comment underlines, the passage being commented.
struct Decoration: Equatable {
    var range: NSRange
    var background: NSColor?
    var underline: NSColor?
    var anchor: TextAnchor? = nil
}

/// A place in a PDF: the page, the point at the top left of the view on it, and the zoom (fitted to the pane,
/// filling it, or chosen by the reader).
struct PDFPosition: Equatable {
    var page: Int
    var point: CGPoint
    var scale: CGFloat
    var autoScales: Bool
    var fitsPane: Bool
}

struct ScrollRequest: Equatable {
    var range: NSRange
    var token: Int
    var anchor: TextAnchor? = nil
}

/// A comment being written: about a passage, or about the whole document when `anchor` is nil.
struct Composing: Equatable {
    var anchor: TextAnchor?
}

/// One open Markdown or PDF file: its rendered text and the highlights and comments on it.
@MainActor @Observable
final class DocumentModel {
    let url: URL
    let key: String
    let chat: PassageChat
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
    private(set) var pdfDocument: PDFDocument?
    private(set) var pdfIndex: PDFTextIndex?
    private(set) var pdfLocked = false
    private(set) var passwordError: String?
    var pdfPageNumber = 1
    private(set) var pdfZoomToken = 0
    private(set) var pdfZoomDirection = 0
    var hasPDFText: Bool { pdfIndex?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    @ObservationIgnored private var pdfSelectionAnchor: TextAnchor?

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
    @ObservationIgnored var onChatStarted: () -> Void = {}
    /// Called when the reader moves away from where the document opened: another page, a scroll.
    @ObservationIgnored var onNavigated: () -> Void = {}
    /// Where the reader was, kept while the document's view is not on screen (another tab, another layout).
    @ObservationIgnored var pdfPosition: PDFPosition?
    @ObservationIgnored var textOffset: CGFloat?

    @ObservationIgnored private let store: AnnotationStore?
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var options: RenderOptions?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var scrollToken = 0

    var text: NSString { pdfIndex?.text ?? (rendered.string as NSString) }

    init(url: URL, store: AnnotationStore?, chatGenerator: (any PassageChatGenerating)? = nil) {
        self.url = url
        self.key = documentKey(for: url)
        self.store = store
        self.chat = PassageChat(generator: chatGenerator ?? ApplePassageChat(), store: store, docPath: self.key)
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
        if isPDF {
            selection = NSRange(location: 0, length: 0)
            pdfSelectionAnchor = nil
            scrollRequest = nil
        }
        if isPDF || text as String != before {
            resolveAnchors()
            if isPDF, let anchor = composing?.anchor {
                composing = resolvedAnchor(anchor).map { Composing(anchor: $0) }
            }
        }
    }

    private func readSource() {
        if isPDF {
            pdfIndex = nil
            pdfDocument = PDFDocument(url: url)
            pdfLocked = pdfDocument?.isLocked == true
            passwordError = nil
            guard pdfDocument != nil else {
                loadError = "Não foi possível abrir este PDF. O arquivo pode estar danificado ou indisponível."
                return
            }
            loadError = nil
            if !pdfLocked { loadPDFText() }
            return
        }
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
        if !isPDF { rendered = MarkdownRenderer.render(source, options: options) }
        renderToken += 1
    }

    private func loadPDFText() {
        guard let pdfDocument else { return }
        guard pdfDocument.pageCount > 0 else {
            loadError = "Este PDF não contém páginas."
            return
        }
        pdfIndex = PDFTextIndex(document: pdfDocument)
    }

    func unlockPDF(password: String) {
        guard let pdfDocument, pdfLocked else { return }
        guard pdfDocument.unlock(withPassword: password) else {
            passwordError = "Senha incorreta. Tente novamente."
            return
        }
        pdfLocked = false
        passwordError = nil
        loadPDFText()
        renderToken += 1
        resolveAnchors()
    }

    func zoomPDF(_ direction: Int) {
        pdfZoomDirection = direction
        pdfZoomToken += 1
    }

    func selectPDF(_ selection: PDFSelection?) {
        pdfSelectionAnchor = selection.flatMap { pdfIndex?.anchor(for: $0) }
        self.selection = pdfSelectionAnchor?.range ?? NSRange(location: 0, length: 0)
    }

    private func makeAnchor(_ range: NSRange) -> TextAnchor? {
        guard range.location >= 0, range.location <= text.length,
              range.length > 0, range.length <= text.length - range.location else { return nil }
        if isPDF {
            if let pdfSelectionAnchor, pdfSelectionAnchor.range == range { return pdfSelectionAnchor }
            return pdfIndex?.anchor(for: range)
        }
        return Anchoring.make(range: range, in: text)
    }

    private func resolvedAnchor(_ anchor: TextAnchor) -> TextAnchor? {
        if isPDF { return pdfIndex?.resolve(anchor) }
        guard let range = Anchoring.resolve(anchor, in: text).range else { return nil }
        var resolved = anchor
        resolved.start = range.location
        resolved.end = NSMaxRange(range)
        return resolved
    }

    private func resolveAnchors() {
        highlightRanges = [:]
        for index in highlights.indices {
            guard let anchor = resolvedAnchor(highlights[index].anchor) else { continue }
            highlightRanges[highlights[index].id] = anchor.range
            if anchor != highlights[index].anchor {
                highlights[index].anchor = anchor
                try? store?.setAnchor(anchor, ofHighlight: highlights[index].id)
            }
        }
        commentRanges = [:]
        for index in comments.indices {
            guard let original = comments[index].anchor, let anchor = resolvedAnchor(original) else { continue }
            commentRanges[comments[index].id] = anchor.range
            if anchor != original {
                comments[index].anchor = anchor
                try? store?.setAnchor(anchor, ofComment: comments[index].id)
            }
        }
    }

    func decorations(theme: Theme) -> [Decoration] {
        var result: [Decoration] = []
        for highlight in highlights {
            guard let range = highlightRanges[highlight.id] else { continue }
            result.append(Decoration(range: range, background: theme.tone(highlight.color).fill.ns, anchor: highlight.anchor))
        }
        for comment in topLevelComments where !comment.isResolved {
            guard let range = commentRanges[comment.id] else { continue }
            let stroke = theme.tone(comment.color ?? .yellow).stroke
            result.append(Decoration(
                range: range,
                background: comment.id == activeCommentID ? stroke.alpha(theme.isDark ? 0.2 : 0.16).ns : nil,
                underline: stroke.ns, anchor: comment.anchor
            ))
        }
        if let anchor = composing?.anchor {
            result.append(Decoration(range: anchor.range, background: theme.selection.ns, anchor: anchor))
        }
        return result
    }

    func scroll(to range: NSRange, anchor: TextAnchor? = nil) {
        scrollToken += 1
        scrollRequest = ScrollRequest(range: range, token: scrollToken, anchor: anchor)
    }

    // MARK: Passage chat

    func startChat(on range: NSRange) {
        guard let anchor = makeAnchor(range) else { return }
        startChat(anchor: anchor)
    }

    func startChat(anchor: TextAnchor) {
        guard !anchor.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chat.start(anchor: anchor)
        onChatStarted()
    }

    func focusChatPassage() {
        guard let original = chat.anchor, let anchor = resolvedAnchor(original) else { return }
        scroll(to: anchor.range, anchor: anchor)
    }

    /// Saving uses the captured passage, even if the current selection or document offsets changed.
    @discardableResult
    func saveChatResponse(_ id: String) throws -> String {
        if comments.contains(where: { $0.id == id }) { return id }
        guard let original = chat.anchor,
              let message = chat.messages.first(where: { $0.id == id && $0.role == .assistant && $0.status == .complete }),
              !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError(message: "Aguarde uma resposta completa antes de salvar a anotação.")
        }
        guard let store else { throw ChatError(message: "O banco de anotações está indisponível. A resposta não foi salva.") }
        let resolved = resolvedAnchor(original)
        let comment = Comment(id: id, docPath: key, anchor: resolved ?? original,
                              body: message.content, isAIGenerated: true)
        try store.insert(comment)
        comments.append(comment)
        if let resolved { commentRanges[id] = resolved.range }
        onAnnotationsChanged()
        return id
    }

    // MARK: Highlights

    func highlight(_ range: NSRange, color: MarkColor) {
        guard let anchor = makeAnchor(range) else { return }
        if let same = highlights.first(where: { highlightRanges[$0.id] == range && $0.anchor.pdf == anchor.pdf }) {
            recolorHighlight(same.id, to: color)
            return
        }
        // A new highlight swallows the ones it covers entirely.
        for covered in highlights where !isPDF && highlightRanges[covered.id].map({ NSIntersectionRange($0, range) == $0 }) == true {
            removeHighlight(covered.id)
        }
        let highlight = Highlight(docPath: key, anchor: anchor, color: color)
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
        if let range, let anchor = makeAnchor(range) {
            composing = Composing(anchor: anchor)
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
        if let range = commentRanges[id] { scroll(to: range, anchor: comments.first { $0.id == id }?.anchor) }
    }
}
