import AppKit
import JulliaCore
import SwiftUI

/// The rendered Markdown in a read-only TextKit 1 `NSTextView`, with highlights, comment underlines and the
/// floating glass pill for marking text.
struct DocumentTextView: NSViewRepresentable {
    let document: DocumentModel
    let rendered: NSAttributedString
    let renderToken: Int
    let decorations: [Decoration]
    let scrollRequest: ScrollRequest?
    let theme: Theme
    let readingWidth: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.drawsBackground = false

        let textView = MarkTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.coordinator = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkTextView else { return }

        textView.theme = theme
        textView.readingWidth = readingWidth
        textView.selectedTextAttributes = [.backgroundColor: theme.selection.ns]
        textView.linkTextAttributes = [
            .foregroundColor: theme.link.ns,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: theme.link.ns.withAlphaComponent(0.4),
            .cursor: NSCursor.pointingHand,
        ]

        if coordinator.renderToken != renderToken {
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.selectedRange()
            let sameText = textView.string == rendered.string
            textView.textStorage?.setAttributedString(rendered)
            if coordinator.renderToken != nil {
                // Same document re-rendered (theme, font, file changed on disk): stay where the reader was.
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                scrollView.contentView.scroll(to: origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                // A selection only means the same thing if the text didn't move under it.
                if sameText { textView.setSelectedRange(selection) }
            }
            coordinator.renderToken = renderToken
            coordinator.decorations = nil
            textView.hidePill()
        }

        if coordinator.decorations != decorations {
            textView.apply(decorations)
            coordinator.decorations = decorations
        }

        if let request = scrollRequest, request.token != coordinator.scrollToken,
           NSMaxRange(request.range) <= textView.string.utf16.count {
            coordinator.scrollToken = request.token
            textView.scrollRangeToVisible(request.range)
            textView.showFindIndicator(for: request.range)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocumentTextView?
        weak var textView: MarkTextView?
        var renderToken: Int?
        var decorations: [Decoration]?
        var scrollToken = 0

        var document: DocumentModel? { parent?.document }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            document?.selection = textView.selectedRange()
            if !textView.isTracking { textView.updatePill() }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            if url.isFileURL, FileTree.isMarkdown(url) {
                AppModel.shared.openFile(url)
            } else {
                NSWorkspace.shared.open(url)
            }
            return true
        }

        // MARK: Actions from the pill and the context menu

        func highlight(_ range: NSRange, color: MarkColor) {
            AppModel.shared.settings.lastColor = color
            document?.highlight(range, color: color)
            textView?.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            textView?.hidePill()
        }

        func recolor(highlight id: String, color: MarkColor) {
            AppModel.shared.settings.lastColor = color
            document?.recolorHighlight(id, to: color)
            textView?.hidePill()
        }

        func remove(highlight id: String) {
            document?.removeHighlight(id)
            textView?.hidePill()
        }

        func comment(_ range: NSRange) {
            document?.startComment(on: range)
            AppModel.shared.revealComments()
            textView?.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            textView?.hidePill()
        }

        func copy(_ range: NSRange) {
            guard let textView else { return }
            let text = (textView.string as NSString).substring(with: range).replacingOccurrences(of: "\u{2028}", with: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            textView.hidePill()
        }

        /// A plain click (no selection): a highlight under it gets the pill, a commented passage lights its card.
        func clicked(at location: Int?) {
            guard let textView, let document else { return }
            AppModel.shared.dismissPeek()
            guard let location else {
                document.activeCommentID = nil
                return
            }
            if let comment = document.comment(at: location) {
                document.activeCommentID = comment.id
                AppModel.shared.revealComments()
            } else {
                document.activeCommentID = nil
            }
            if let highlight = document.highlight(at: location), let range = document.highlightRanges[highlight.id] {
                textView.showPill(for: range, mode: .highlight(id: highlight.id, color: highlight.color))
            }
        }
    }
}

/// The text view: tracks the mouse so the pill appears after a selection is made, not during the drag, and adds
/// marking commands to the context menu.
final class MarkTextView: NSTextView {
    weak var coordinator: DocumentTextView.Coordinator?
    var theme: Theme = .polar
    var readingWidth: Double = 760 { didSet { if oldValue != readingWidth { updateInsets() } } }
    private(set) var isTracking = false
    private var pill: NSHostingView<SelectionPill>?

    enum PillMode: Equatable {
        case selection
        case highlight(id: String, color: MarkColor)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    private func updateInsets() {
        let horizontal = max(36, (bounds.width - readingWidth) / 2)
        let inset = NSSize(width: horizontal.rounded(), height: 30)
        if textContainerInset != inset {
            textContainerInset = inset
            hidePill()
        }
    }

    // MARK: Decorations

    func apply(_ decorations: [Decoration]) {
        guard let layoutManager else { return }
        let all = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
        for decoration in decorations where NSMaxRange(decoration.range) <= all.length {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let background = decoration.background { attributes[.backgroundColor] = background }
            if let underline = decoration.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.thick.rawValue
                attributes[.underlineColor] = underline
            }
            layoutManager.addTemporaryAttributes(attributes, forCharacterRange: decoration.range)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        hidePill()
        isTracking = true
        super.mouseDown(with: event) // Runs its own tracking loop until the mouse goes up.
        isTracking = false

        if selectedRange().length > 0 {
            updatePill()
        } else if event.clickCount == 1 {
            coordinator?.clicked(at: characterIndex(at: convert(event.locationInWindow, from: nil)))
        }
    }

    /// The character drawn under a point, or nil over margins and empty space.
    func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    // MARK: Pill

    func updatePill() {
        let range = selectedRange()
        if range.length > 0 {
            showPill(for: range, mode: .selection)
        } else {
            hidePill()
        }
    }

    func showPill(for range: NSRange, mode: PillMode) {
        guard let coordinator, let layoutManager, let textContainer else { return }
        let content = SelectionPill(
            theme: theme,
            current: { if case .highlight(_, let color) = mode { color } else { nil } }(),
            onColor: { color in
                switch mode {
                case .selection: coordinator.highlight(range, color: color)
                case .highlight(let id, _): coordinator.recolor(highlight: id, color: color)
                }
            },
            onComment: { coordinator.comment(range) },
            onCopy: { coordinator.copy(range) },
            onRemove: { if case .highlight(let id, _) = mode { coordinator.remove(highlight: id) } }
        )
        let host: NSHostingView<SelectionPill>
        if let pill {
            host = pill
            host.rootView = content
        } else {
            host = NSHostingView(rootView: content)
            addSubview(host)
            pill = host
        }
        host.isHidden = false
        let size = host.fittingSize

        // Above the first line of the range; below the last if there's no room above.
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var firstLine = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &firstLine)
        let firstRect = layoutManager.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, firstLine), in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        var origin = NSPoint(x: firstRect.midX - size.width / 2, y: firstRect.minY - size.height - 8)
        if origin.y < visibleRect.minY + 4 {
            let whole = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            origin.y = whole.maxY + 8
        }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        host.frame = NSRect(origin: origin, size: size)
    }

    func hidePill() {
        pill?.isHidden = true
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let coordinator, let document = coordinator.document else { return menu }
        var items: [NSMenuItem] = []
        let selection = selectedRange()

        if selection.length > 0 {
            let submenu = NSMenu()
            for color in MarkColor.allCases {
                submenu.addItem(ActionMenuItem(title: color.displayName, image: swatch(color)) {
                    coordinator.highlight(selection, color: color)
                })
            }
            let highlight = NSMenuItem(title: "Destacar", action: nil, keyEquivalent: "")
            highlight.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
            highlight.submenu = submenu
            items.append(highlight)
            items.append(ActionMenuItem(title: "Comentar…", image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)) {
                coordinator.comment(selection)
            })
        }

        let point = convert(event.locationInWindow, from: nil)
        if let location = characterIndex(at: point), let highlight = document.highlight(at: location) {
            let submenu = NSMenu()
            for color in MarkColor.allCases {
                let item = ActionMenuItem(title: color.displayName, image: swatch(color)) {
                    coordinator.recolor(highlight: highlight.id, color: color)
                }
                item.state = color == highlight.color ? .on : .off
                submenu.addItem(item)
            }
            let recolor = NSMenuItem(title: "Cor do destaque", action: nil, keyEquivalent: "")
            recolor.submenu = submenu
            items.append(recolor)
            items.append(ActionMenuItem(title: "Remover destaque", image: NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)) {
                coordinator.remove(highlight: highlight.id)
            })
        }

        guard !items.isEmpty else { return menu }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        return menu
    }

    private func swatch(_ color: MarkColor) -> NSImage {
        let fill = theme.tone(color).fill.alpha(1).ns
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, image: NSImage? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        self.target = self
        self.image = image
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}
