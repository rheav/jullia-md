import AppKit
import JulliaCore
import PDFKit
import SwiftUI

struct PDFReader: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var password = ""

    var body: some View {
        if document.pdfLocked {
            VStack(spacing: 14) {
                Image(systemName: "lock.doc").font(.system(size: 36))
                Text("PDF protegido").font(.headline)
                SecureField("Senha do documento", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(unlock)
                if let error = document.passwordError { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Abrir PDF", action: unlock).buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(theme.text.color)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Página \(document.pdfPageNumber) de \(document.pdfDocument?.pageCount ?? 0)")
                        .monospacedDigit()
                    Spacer()
                    Button { document.zoomPDF(-1) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("Diminuir zoom (⌘−)")
                    Button("Ajustar") { document.zoomPDF(0) }.help("Ajustar à janela (⌘0)")
                    Button { document.zoomPDF(1) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("Aumentar zoom (⌘+)")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText.color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if !document.hasPDFText {
                    Text("Este PDF não tem texto selecionável. Você pode comentar o documento inteiro.")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText.color)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                DocumentPDFView(document: document, theme: theme, appModel: model)
            }
        }
    }

    private func unlock() {
        document.unlockPDF(password: password)
        password = ""
    }
}

struct DocumentPDFView: NSViewRepresentable {
    let document: DocumentModel
    let theme: Theme
    let appModel: AppModel

    func makeNSView(context: Context) -> AnnotatedPDFView {
        let view = AnnotatedPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 8
        view.installObservers()
        return view
    }

    func updateNSView(_ view: AnnotatedPDFView, context: Context) {
        view.update(model: document, theme: theme, appModel: appModel)
    }

    static func dismantleNSView(_ view: AnnotatedPDFView, coordinator: ()) {
        view.tearDown()
    }
}

/// PDFKit paints the pages; only Jullia's temporary annotations are added/removed here.
/// This view never serializes or writes its PDFDocument.
final class AnnotatedPDFView: PDFView {
    private(set) var model: DocumentModel?
    private weak var appModel: AppModel?
    private var theme: Theme = .polar
    private var decorations: [Decoration] = []
    private var marks: [PDFAnnotation] = []
    private var pill: NSHostingView<SelectionPill>?
    private var mouseMonitor: Any?
    private var scrollToken = 0
    private var zoomToken = 0
    private var updating = false
    /// Where the reader was last time this document was on screen, applied once the view has a size.
    private var pendingRestore: PDFPosition?
    /// The page the document opened on; leaving it keeps a preview tab.
    private var openedPage: Int?

    func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: self)
        center.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: self)
        center.addObserver(self, selector: #selector(viewportChanged), name: .PDFViewScaleChanged, object: self)
        // PDFKit's inner document view receives mouse events. Observe their completion without consuming them.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window, self.window != nil else { return }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return }
                if let pill = self.pill, !pill.isHidden, pill.frame.contains(point) { return }
                if event.type == .leftMouseUp {
                    DispatchQueue.main.async { [weak self] in self?.finishedSelection(at: point) }
                } else {
                    self.hidePill()
                }
            }
            return event
        }
    }

    func tearDown() {
        savePosition()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        NotificationCenter.default.removeObserver(self)
        removeMarks()
        pill?.removeFromSuperview()
        pill = nil
        model?.selectPDF(nil)
        model = nil
        document = nil
    }

    func update(model: DocumentModel, theme: Theme, appModel: AppModel) {
        updating = true
        defer { updating = false }
        self.model = model
        self.appModel = appModel
        if self.theme.id != theme.id { hidePill() }
        self.theme = theme
        backgroundColor = theme.background.ns
        if document !== model.pdfDocument {
            let firstAttach = document == nil
            let previousPage = currentPage.flatMap { document?.index(for: $0) } ?? 0
            removeMarks()
            document = model.pdfDocument
            if firstAttach, let saved = model.pdfPosition {
                pendingRestore = saved
                needsLayout = true
            } else if let document, let page = document.page(at: min(previousPage, max(0, document.pageCount - 1))) {
                go(to: page)
            }
            if firstAttach { openedPage = model.pdfPosition?.page ?? 0 }
            decorations = []
            hidePill()
            pageChanged()
        }
        let next = model.decorations(theme: theme)
        if decorations != next {
            removeMarks()
            decorations = next
            for decoration in next {
                guard let anchor = decoration.anchor, let lines = model.pdfIndex?.lines(for: anchor) else { continue }
                for line in lines {
                    for page in line.pages {
                        let bounds = line.bounds(for: page)
                        guard !bounds.isEmpty, !bounds.isInfinite else { continue }
                        if let fill = decoration.background { addMark(on: page, bounds: bounds, type: .highlight, color: fill) }
                        if let stroke = decoration.underline { addMark(on: page, bounds: bounds, type: .underline, color: stroke) }
                    }
                }
            }
        }
        if let request = model.scrollRequest, scrollToken != request.token {
            scrollToken = request.token
            if let anchor = request.anchor ?? model.pdfIndex?.anchor(for: request.range),
               let selection = model.pdfIndex?.selection(for: anchor) {
                go(to: selection)
                hidePill()
            }
        }
        if zoomToken != model.pdfZoomToken {
            zoomToken = model.pdfZoomToken
            switch model.pdfZoomDirection {
            case 1: zoomIn(nil)
            case -1: zoomOut(nil)
            default: autoScales = true
            }
            hidePill()
        }
    }

    private func addMark(on page: PDFPage, bounds: CGRect, type: PDFAnnotationSubtype, color: NSColor) {
        let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
        annotation.color = color
        page.addAnnotation(annotation)
        marks.append(annotation)
    }

    private func removeMarks() {
        for mark in marks { mark.page?.removeAnnotation(mark) }
        marks.removeAll()
    }

    @objc private func selectionChanged() {
        guard !updating else { return }
        model?.selectPDF(currentSelection)
        hidePill()
        // Keyboard selections also get the same actions as mouse selections.
        if NSEvent.pressedMouseButtons == 0 {
            DispatchQueue.main.async { [weak self] in self?.showSelectionPill() }
        }
    }

    @objc private func pageChanged() {
        guard let page = currentPage, let document else { return }
        let number = document.index(for: page) + 1
        let currentModel = model
        let navigated = pendingRestore == nil && openedPage.map { $0 != number - 1 } == true
        if navigated { openedPage = nil }
        DispatchQueue.main.async { [weak currentModel] in
            if currentModel?.pdfPageNumber != number { currentModel?.pdfPageNumber = number }
            if navigated { currentModel?.onNavigated() }
        }
        hidePill()
    }

    override func layout() {
        super.layout()
        restorePosition()
    }

    /// Back to where the reader was, once the view is laid out (a destination means nothing at zero size).
    private func restorePosition() {
        guard let saved = pendingRestore, bounds.width > 0, bounds.height > 0, let document, document.pageCount > 0,
              let page = document.page(at: min(saved.page, document.pageCount - 1)) else { return }
        pendingRestore = nil
        if !saved.autoScales {
            autoScales = false
            scaleFactor = saved.scale
        }
        go(to: PDFDestination(page: page, at: saved.point))
    }

    /// Remembers the page, the point at the top of the view and the zoom, for when the tab is shown again.
    private func savePosition() {
        guard let model, pendingRestore == nil, let document, let destination = currentDestination,
              let page = destination.page else { return }
        model.pdfPosition = PDFPosition(page: document.index(for: page), point: destination.point,
                                        scale: scaleFactor, autoScales: autoScales)
    }

    @objc private func viewportChanged() { hidePill() }

    private func finishedSelection(at point: NSPoint) {
        guard let model else { return }
        model.selectPDF(currentSelection)
        if model.hasSelection {
            showSelectionPill()
            return
        }
        appModel?.dismissPeek()
        if let comment = model.topLevelComments.last(where: {
            !$0.isResolved && model.commentRanges[$0.id] != nil && contains($0.anchor, point: point)
        }) {
            model.activeCommentID = comment.id
            appModel?.revealComments()
        } else {
            model.activeCommentID = nil
        }
        if let highlight = highlight(at: point) { showPill(anchor: highlight.anchor, highlight: highlight) }
    }

    private func contains(_ anchor: TextAnchor?, point: NSPoint) -> Bool {
        guard let anchor, let lines = model?.pdfIndex?.lines(for: anchor), let page = page(for: point, nearest: false) else { return false }
        let local = convert(point, to: page)
        return lines.contains { line in
            line.pages.contains { $0 === page } && line.bounds(for: page).insetBy(dx: -2, dy: -2).contains(local)
        }
    }

    private func highlight(at point: NSPoint) -> Highlight? {
        model?.highlights.last { model?.highlightRanges[$0.id] != nil && contains($0.anchor, point: point) }
    }

    private func showSelectionPill() {
        guard let currentSelection, let anchor = model?.pdfIndex?.anchor(for: currentSelection) else { return }
        showPill(anchor: anchor, highlight: nil)
    }

    private func showPill(anchor: TextAnchor, highlight: Highlight?) {
        guard let lines = model?.pdfIndex?.lines(for: anchor) else { return }
        let rects = lines.flatMap { line in
            line.pages.map { convert(line.bounds(for: $0), from: $0) }
        }
        guard let rect = rects.first(where: { bounds.intersects($0) }) else { return }
        let content = SelectionPill(
            theme: theme, current: highlight?.color,
            onColor: { [weak self] color in self?.mark(anchor, highlight: highlight, color: color) },
            onComment: { [weak self] in self?.comment(anchor) },
            onChat: { [weak self] in
                self?.model?.startChat(anchor: anchor)
                self?.hidePill()
            },
            onCopy: { [weak self] in self?.copy(anchor) },
            onRemove: { [weak self] in
                if let highlight { self?.model?.removeHighlight(highlight.id) }
                self?.hidePill()
            }
        )
        let host = pill ?? NSHostingView(rootView: content)
        host.rootView = content
        if pill == nil { addSubview(host); pill = host }
        let size = host.fittingSize
        // PDF pages keep their original colors, so the controls need their own contrasting surface.
        host.wantsLayer = true
        host.layer?.backgroundColor = theme.surface.ns.withAlphaComponent(0.94).cgColor
        host.layer?.cornerRadius = size.height / 2
        let x = min(max(rect.midX - size.width / 2, bounds.minX + 8), max(bounds.minX + 8, bounds.maxX - size.width - 8))
        let above = isFlipped ? rect.minY - size.height - 8 : rect.maxY + 8
        let y = min(max(above, bounds.minY + 8), max(bounds.minY + 8, bounds.maxY - size.height - 8))
        host.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        host.isHidden = false
    }

    private func hidePill() { pill?.isHidden = true }

    private func mark(_ anchor: TextAnchor, highlight: Highlight?, color: MarkColor) {
        appModel?.settings.lastColor = color
        if let highlight {
            model?.recolorHighlight(highlight.id, to: color)
        } else {
            model?.selectPDF(model?.pdfIndex?.selection(for: anchor))
            model?.highlight(anchor.range, color: color)
        }
        clearSelection()
        hidePill()
    }

    private func comment(_ anchor: TextAnchor) {
        model?.selectPDF(model?.pdfIndex?.selection(for: anchor))
        model?.startComment(on: anchor.range)
        appModel?.revealComments()
        clearSelection()
        hidePill()
    }

    private func copy(_ anchor: TextAnchor) {
        guard document?.allowsCopying == true, let text = model?.pdfIndex?.selection(for: anchor)?.string else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hidePill()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let selectedAnchor = currentSelection.flatMap { model?.pdfIndex?.anchor(for: $0) }
        let highlight = selectedAnchor == nil ? highlight(at: convert(event.locationInWindow, from: nil)) : nil
        let anchor = selectedAnchor ?? highlight?.anchor
        guard let anchor else { return menu }
        let colors = NSMenu()
        for color in MarkColor.allCases {
            colors.addItem(ActionMenuItem(title: color.displayName) { [weak self] in self?.mark(anchor, highlight: highlight, color: color) })
        }
        let item = NSMenuItem(title: highlight == nil ? "Destacar" : "Cor do destaque", action: nil, keyEquivalent: "")
        item.submenu = colors
        menu.addItem(item)
        menu.addItem(ActionMenuItem(title: "Comentar…") { [weak self] in self?.comment(anchor) })
        menu.addItem(ActionMenuItem(title: "Conversar sobre trecho") { [weak self] in
            self?.model?.startChat(anchor: anchor)
            self?.hidePill()
        })
        menu.addItem(ActionMenuItem(title: "Copiar") { [weak self] in self?.copy(anchor) })
        if let highlight {
            menu.addItem(ActionMenuItem(title: "Remover destaque") { [weak self] in
                self?.model?.removeHighlight(highlight.id)
                self?.hidePill()
            })
        }
        return menu
    }
}
