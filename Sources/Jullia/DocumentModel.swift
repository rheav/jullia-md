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
    /// Brings the range to the top of the view, as a heading from the table of contents, instead of just into it.
    var atTop = false
}

/// A page of the PDF to show, and where on it (PDF coordinates), with a token so each request is carried out once.
struct PDFPageRequest: Equatable {
    var page: Int
    var point: CGPoint?
    var token: Int
}

/// One entry of the table of contents: a Markdown heading, or an item of the PDF's own outline.
struct OutlineItem: Identifiable, Equatable {
    enum Target: Equatable {
        case text(NSRange)
        case page(Int, CGPoint?)
    }

    let id: Int
    let title: String
    /// 1 for the top level.
    let level: Int
    let target: Target
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
    private(set) var pdfPageRequest: PDFPageRequest?
    /// The "Ir para a página" alert is up.
    var askingForPage = false
    var hasPDFText: Bool { pdfIndex?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    /// The PDF's find bar. Markdown uses the text view's own, through `findRequest`.
    let pdfFind = PDFFind()
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
    private(set) var findRequest: FindRequest?
    /// The table of contents.
    private(set) var outline: [OutlineItem] = []

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
    /// The window's undo stack, where every change to the annotations puts its inverse.
    @ObservationIgnored var undoManager: () -> UndoManager? = { nil }
    /// Called before one of this document's changes is undone or redone, so its tab comes forward.
    @ObservationIgnored var onUndo: () -> Void = {}
    /// Where the reader was, kept while the document's view is not on screen (another tab, another layout).
    @ObservationIgnored var pdfPosition: PDFPosition?
    @ObservationIgnored var textOffset: CGFloat?

    @ObservationIgnored private let store: AnnotationStore?
    @ObservationIgnored private var source = ""
    @ObservationIgnored private var options: RenderOptions?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var scrollToken = 0
    @ObservationIgnored private var findToken = 0
    @ObservationIgnored private var pageToken = 0

    var text: NSString { pdfIndex?.text ?? (rendered.string as NSString) }

    init(url: URL, store: AnnotationStore?, chatGenerator: (any PassageChatGenerating)? = nil) {
        self.url = url
        self.key = documentKey(for: url)
        self.store = store
        self.chat = PassageChat(generator: chatGenerator ?? ApplePassageChat(), store: store, docPath: self.key)
        highlights = (try? store?.highlights(for: key)) ?? []
        comments = (try? store?.comments(for: key)) ?? []
        pdfFind.startPage = { [weak self] in (self?.pdfPageNumber ?? 1) - 1 }
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
            pdfFind.attach(pdfDocument)
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
        if !isPDF {
            rendered = MarkdownRenderer.render(source, options: options)
            let headings = MarkdownRenderer.headings(in: rendered)
            outline = headings.enumerated().map { index, heading in
                OutlineItem(id: index, title: heading.title, level: heading.level, target: .text(heading.range))
            }
        }
        renderToken += 1
    }

    private func loadPDFText() {
        guard let pdfDocument else { return }
        guard pdfDocument.pageCount > 0 else {
            loadError = "Este PDF não contém páginas."
            return
        }
        pdfIndex = PDFTextIndex(document: pdfDocument)
        outline = Self.outline(of: pdfDocument)
    }

    /// The PDF's own outline, depth first, each item with its depth and destination. Items without one are kept as
    /// headings of the ones inside them, pointing at the first page.
    private static func outline(of document: PDFDocument) -> [OutlineItem] {
        var items: [OutlineItem] = []
        func walk(_ node: PDFOutline, level: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let page = destination?.page.map { document.index(for: $0) } ?? 0
                let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    items.append(OutlineItem(id: items.count, title: title, level: level, target: .page(page, destination?.point)))
                }
                walk(child, level: level + 1)
            }
        }
        if let root = document.outlineRoot { walk(root, level: 1) }
        return items
    }

    /// From the table of contents: a heading to the top of the text, an outline item to its place in the PDF.
    func go(to item: OutlineItem) {
        switch item.target {
        case .text(let range):
            scrollToken += 1
            scrollRequest = ScrollRequest(range: range, token: scrollToken, atTop: true)
        case .page(let page, let point):
            goToPDFPage(page, at: point)
        }
    }

    /// A page of the PDF, zero-based, kept within the document.
    func goToPDFPage(_ index: Int, at point: CGPoint? = nil) {
        guard let count = pdfDocument?.pageCount, count > 0 else { return }
        pageToken += 1
        pdfPageRequest = PDFPageRequest(page: min(max(index, 0), count - 1), point: point, token: pageToken)
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
        pdfFind.attach(pdfDocument)
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

    /// The Markdown as it goes on paper: rendered again with `options`, with the link colour, the highlights and the
    /// open comments' underlines set on the text itself. On screen they are the text view's temporary attributes,
    /// which are not printed.
    func printableText(options: RenderOptions) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: MarkdownRenderer.render(source, options: options))
        let length = text.length
        let theme = options.theme
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: length)) { link, range, _ in
            guard link != nil else { return }
            text.addAttributes([
                .foregroundColor: theme.link.ns,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: theme.link.ns.withAlphaComponent(0.4),
            ], range: range)
        }
        for highlight in highlights {
            guard let range = highlightRanges[highlight.id], NSMaxRange(range) <= length else { continue }
            text.addAttribute(.backgroundColor, value: theme.tone(highlight.color).fill.ns, range: range)
        }
        for comment in topLevelComments where !comment.isResolved {
            guard let range = commentRanges[comment.id], NSMaxRange(range) <= length else { continue }
            text.addAttributes([
                .underlineStyle: NSUnderlineStyle.thick.rawValue,
                .underlineColor: theme.tone(comment.color ?? .yellow).stroke.ns,
            ], range: range)
        }
        return text
    }

    /// ⌘F, ⌘G, ⇧⌘G and ⌘E.
    func find(_ action: FindAction) {
        if isPDF {
            pdfFind.perform(action, selectedText: hasSelection ? text.substring(with: selection) : nil)
        } else {
            findToken += 1
            findRequest = FindRequest(action: action, token: findToken)
        }
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
        registerUndo("Salvar resposta da IA") { $0.deleteComment(id) }
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
        insert(Highlight(docPath: key, anchor: anchor, color: color), named: "Destaque")
    }

    /// A new highlight, or one brought back by undo, with the same identifier.
    private func insert(_ highlight: Highlight, named name: String) {
        do {
            try store?.insert(highlight)
        } catch {
            return NSSound.beep()
        }
        highlights.append(highlight)
        if let anchor = resolvedAnchor(highlight.anchor) { highlightRanges[highlight.id] = anchor.range }
        registerUndo(name) { $0.removeHighlight(highlight.id) }
        onAnnotationsChanged()
    }

    func recolorHighlight(_ id: String, to color: MarkColor) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        let old = highlights[index].color
        try? store?.setColor(color, ofHighlight: id)
        highlights[index].color = color
        registerUndo("Cor do destaque") { $0.recolorHighlight(id, to: old) }
    }

    func removeHighlight(_ id: String) {
        guard let removed = highlights.first(where: { $0.id == id }) else { return }
        try? store?.deleteHighlight(id)
        highlights.removeAll { $0.id == id }
        highlightRanges[id] = nil
        registerUndo("Remover destaque") { $0.insert(removed, named: "Destaque") }
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
        guard insert([comment], named: "Comentário") else { return }
        self.composing = nil
        activeCommentID = comment.id
    }

    func reply(to id: String, body: String) {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        insert([Comment(docPath: key, parentID: id, anchor: nil, body: body)], named: "Resposta")
    }

    /// New comments, or a comment and its replies brought back by undo, with their identifiers. Undoing deletes the
    /// first, and the rest with it.
    @discardableResult
    private func insert(_ inserted: [Comment], named name: String) -> Bool {
        guard let first = inserted.first else { return false }
        do {
            for comment in inserted { try store?.insert(comment) }
        } catch {
            try? store?.deleteComment(first.id)
            NSSound.beep()
            return false
        }
        comments.append(contentsOf: inserted)
        for comment in inserted where comment.parentID == nil {
            if let anchor = comment.anchor.flatMap(resolvedAnchor) { commentRanges[comment.id] = anchor.range }
        }
        registerUndo(name) { $0.deleteComment(first.id) }
        onAnnotationsChanged()
        return true
    }

    func edit(_ id: String, body: String) {
        guard let index = comments.firstIndex(where: { $0.id == id }),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let old = comments[index].body
        try? store?.setBody(body, ofComment: id)
        comments[index].body = body
        comments[index].updatedAt = .now
        registerUndo("Edição do comentário") { $0.edit(id, body: old) }
    }

    func setResolved(_ id: String, _ resolved: Bool) {
        setResolved(id, at: resolved ? .now : nil)
    }

    /// Resolved at a date, or open again; undo puts the earlier date back.
    private func setResolved(_ id: String, at date: Date?) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let old = comments[index].resolvedAt
        try? store?.setResolved(date, ofComment: id)
        comments[index].resolvedAt = date
        if date != nil, activeCommentID == id { activeCommentID = nil }
        registerUndo(date != nil ? "Resolver comentário" : "Reabrir comentário") { $0.setResolved(id, at: old) }
        onAnnotationsChanged()
    }

    func recolorComment(_ id: String, to color: MarkColor?) {
        guard let index = comments.firstIndex(where: { $0.id == id }) else { return }
        let old = comments[index].color
        try? store?.setColor(color, ofComment: id)
        comments[index].color = color
        registerUndo("Cor do comentário") { $0.recolorComment(id, to: old) }
    }

    /// Deletes a comment and its replies; undo brings them all back.
    func deleteComment(_ id: String) {
        let removed = comments.filter { $0.id == id } + comments.filter { $0.parentID == id }
        guard !removed.isEmpty else { return }
        try? store?.deleteComment(id)
        comments.removeAll { $0.id == id || $0.parentID == id }
        commentRanges[id] = nil
        if activeCommentID == id { activeCommentID = nil }
        registerUndo("Excluir comentário") { $0.insert(removed, named: "Comentário") }
        onAnnotationsChanged()
    }

    // MARK: Undo

    /// Puts the inverse of a change on the window's undo stack, under the change's name. The inverse is itself a
    /// change, so it registers the redo, which keeps the same name. Undoing brings this document forward first.
    private func registerUndo(_ name: String, _ inverse: @escaping @MainActor (DocumentModel) -> Void) {
        guard let manager = undoManager() else { return }
        manager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.onUndo()
                inverse(document)
                document.undoManager()?.setActionName(name)
            }
        }
        manager.setActionName(name)
    }

    /// From the inspector: light the comment up and bring its passage into view.
    func focusComment(_ id: String) {
        activeCommentID = id
        if let range = commentRanges[id] { scroll(to: range, anchor: comments.first { $0.id == id }?.anchor) }
    }
}
