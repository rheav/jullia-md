import AppKit
import Markdown

public struct RenderOptions: Sendable {
    public var theme: Theme
    public var fontSize: CGFloat
    /// The Markdown file's folder, for relative links and images.
    public var baseURL: URL?

    public init(theme: Theme, fontSize: CGFloat = 15, baseURL: URL? = nil) {
        self.theme = theme
        self.fontSize = fontSize
        self.baseURL = baseURL
    }
}

/// Markdown → attributed text for a TextKit 1 `NSTextView`.
///
/// The characters produced depend only on the source, never on the theme or font size, because highlight and
/// comment anchors are offsets into this text.
public enum MarkdownRenderer {
    public static func render(_ source: String, options: RenderOptions) -> NSAttributedString {
        let document = Document(parsing: source)
        let builder = Builder(options: options)
        builder.blocks(document.children, context: .init())
        return builder.output
    }

    /// The text `render` would produce, without styling — what anchors are measured against.
    public static func plainText(_ source: String) -> String {
        render(source, options: RenderOptions(theme: .polar)).string
    }
}

// MARK: - Builder

private final class Builder {
    struct Context {
        var textBlocks: [NSTextBlock] = []
        /// Left indent of the paragraph text.
        var indent: CGFloat = 0
        var listDepth = 0
        var inList = false
        var quoted = false
    }

    struct Inline {
        var bold = false
        var italic = false
        var code = false
        var strike = false
        var link: URL?
        var scale: CGFloat = 1
        var color: NSColor?
    }

    let output = NSMutableAttributedString()
    let theme: Theme
    let size: CGFloat
    let baseURL: URL?
    /// A list marker waiting for the first paragraph of its item.
    var pendingMarker: (text: String, indent: CGFloat)?

    init(options: RenderOptions) {
        theme = options.theme
        size = options.fontSize
        baseURL = options.baseURL
    }

    var markerWidth: CGFloat { size * 1.6 }

    // MARK: Blocks

    func blocks(_ children: some Sequence<Markup>, context: Context) {
        for child in children { block(child, context: context) }
    }

    func block(_ markup: Markup, context: Context) {
        switch markup {
        case let heading as Heading:
            let scales: [CGFloat] = [1.9, 1.5, 1.27, 1.12, 1.0, 0.92]
            let scale = scales[min(max(heading.level, 1), 6) - 1]
            paragraph(context: context, spacingBefore: output.length == 0 ? 0 : size * (heading.level <= 2 ? 1.2 : 0.9),
                      spacingAfter: size * 0.45, lineHeight: 1.15) { text in
                inlines(heading.children, style: Inline(bold: true, scale: scale, color: theme.heading.ns), into: text)
            }

        case let paragraph as Paragraph:
            self.paragraph(context: context, spacingAfter: context.inList ? size * 0.3 : size * 0.75) { text in
                inlines(paragraph.children, style: Inline(color: context.quoted ? theme.quoteText.ns : nil), into: text)
            }

        case let quote as BlockQuote:
            let block = QuoteTextBlock()
            block.bar = theme.quoteBar.ns
            block.setValue(100, type: .percentageValueType, for: .width)
            block.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
            block.setWidth(size * 1.1, type: .absoluteValueType, for: .padding, edge: .minX)
            block.setWidth(size * 0.15, type: .absoluteValueType, for: .margin, edge: .minY)
            block.setWidth(size * 0.6, type: .absoluteValueType, for: .margin, edge: .maxY)
            var inner = context
            inner.textBlocks.append(block)
            inner.indent = 0
            inner.quoted = true
            inner.inList = false
            blocks(quote.children, context: inner)
            trimTrailingSpacing(to: 0)

        case let code as CodeBlock:
            codeBlock(code.code, context: context)

        case let html as HTMLBlock:
            let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("<!--") { return }
            codeBlock(raw, context: context)

        case let list as UnorderedList:
            listItems(Array(list.listItems), ordered: nil, context: context)

        case let list as OrderedList:
            listItems(Array(list.listItems), ordered: Int(list.startIndex), context: context)

        case is ThematicBreak:
            let block = RuleTextBlock()
            block.line = theme.rule.ns
            block.setValue(100, type: .percentageValueType, for: .width)
            block.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
            var inner = context
            inner.textBlocks.append(block)
            inner.indent = 0
            self.paragraph(context: inner, spacingBefore: size * 0.4, spacingAfter: size * 1.0) { text in
                text.append(NSAttributedString(string: "\u{00A0}", attributes: [.font: NSFont.systemFont(ofSize: size * 0.5)]))
            }

        case let table as Table:
            self.table(table, context: context)

        default:
            // Unknown blocks (directives, …): render their children, if any.
            blocks(markup.children, context: context)
        }
    }

    func listItems(_ items: [ListItem], ordered start: Int?, context: Context) {
        let bullets = ["•", "◦", "▪︎"]
        var inner = context
        inner.indent = context.indent + markerWidth
        inner.listDepth = context.listDepth + 1
        inner.inList = true
        for (offset, item) in items.enumerated() {
            let marker: String
            switch item.checkbox {
            case .checked?: marker = "☑︎"
            case .unchecked?: marker = "☐"
            case nil: marker = start.map { "\($0 + offset)." } ?? bullets[context.listDepth % bullets.count]
            }
            pendingMarker = (marker, context.indent)
            blocks(item.children, context: inner)
            if pendingMarker != nil {
                // An item with nothing in it still shows its marker.
                pendingMarker = (marker, context.indent)
                paragraph(context: inner, spacingAfter: size * 0.3) { _ in }
            }
        }
        if !context.inList { trimTrailingSpacing(to: size * 0.75) }
    }

    func codeBlock(_ code: String, context: Context) {
        let block = CodeTextBlock()
        block.fill = theme.codeBackground.ns
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        block.setWidth(size * 0.2, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(size * 0.8, type: .absoluteValueType, for: .margin, edge: .maxY)
        block.setWidth(size * 0.9, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(size * 0.9, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setWidth(size * 0.65, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(size * 0.65, type: .absoluteValueType, for: .padding, edge: .maxY)
        var inner = context
        inner.textBlocks.append(block)
        inner.indent = 0
        var body = code
        while body.hasSuffix("\n") { body.removeLast() }
        let font = NSFont.monospacedSystemFont(ofSize: size * 0.86, weight: .regular)
        // One paragraph for the whole block: line breaks inside are line separators, so the block stays one piece.
        paragraph(context: inner, spacingAfter: 0, lineHeight: 1.18) { text in
            text.append(NSAttributedString(
                string: body.replacingOccurrences(of: "\n", with: "\u{2028}"),
                attributes: [.font: font, .foregroundColor: theme.codeText.ns]
            ))
        }
    }

    func table(_ table: Table, context: Context) {
        let columns = max(table.maxColumnCount, 1)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.collapsesBorders = true
        textTable.setValue(100, type: .percentageValueType, for: .width)
        textTable.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        textTable.setWidth(size * 0.9, type: .absoluteValueType, for: .margin, edge: .maxY)

        var rows: [(cells: [Table.Cell], header: Bool)] = [(Array(table.head.cells), true)]
        rows += table.body.rows.map { (Array($0.cells), false) }
        let alignments = table.columnAlignments

        for (rowIndex, row) in rows.enumerated() {
            for column in 0..<columns {
                let cell = column < row.cells.count ? row.cells[column] : nil
                let block = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setBorderColor(theme.rule.ns)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(size * 0.6, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(size * 0.6, type: .absoluteValueType, for: .padding, edge: .maxX)
                block.setWidth(size * 0.35, type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(size * 0.35, type: .absoluteValueType, for: .padding, edge: .maxY)
                if row.header { block.backgroundColor = theme.codeBackground.ns.withAlphaComponent(0.6) }
                var inner = context
                inner.textBlocks.append(block)
                inner.indent = 0
                let alignment: NSTextAlignment = switch column < alignments.count ? alignments[column] : nil {
                case .center?: .center
                case .right?: .right
                default: .natural
                }
                paragraph(context: inner, spacingAfter: 0, lineHeight: 1.15, alignment: alignment) { text in
                    if let cell {
                        inlines(cell.children, style: Inline(bold: row.header), into: text)
                    }
                }
            }
        }
    }

    // MARK: Paragraphs

    func paragraph(
        context: Context, spacingBefore: CGFloat = 0, spacingAfter: CGFloat, lineHeight: CGFloat = 1.3,
        alignment: NSTextAlignment = .natural, content: (NSMutableAttributedString) -> Void
    ) {
        let text = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacing = spacingAfter
        style.paragraphSpacingBefore = spacingBefore
        style.alignment = alignment
        style.textBlocks = context.textBlocks
        style.headIndent = context.indent
        style.firstLineHeadIndent = context.indent

        if let marker = pendingMarker {
            pendingMarker = nil
            style.firstLineHeadIndent = marker.indent
            style.tabStops = [NSTextTab(textAlignment: .left, location: context.indent)]
            style.defaultTabInterval = markerWidth
            text.append(NSAttributedString(string: marker.text + "\t", attributes: [
                .font: bodyFont(size: size, bold: false, italic: false),
                .foregroundColor: theme.secondaryText.ns,
            ]))
        }

        content(text)
        text.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont(size: size, bold: false, italic: false)]))
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        output.append(text)
    }

    /// Sets the spacing after the last paragraph written, so a list or quote ends with block spacing, not item spacing.
    func trimTrailingSpacing(to spacing: CGFloat) {
        guard output.length > 0 else { return }
        let nsString = output.string as NSString
        let last = nsString.paragraphRange(for: NSRange(location: output.length - 1, length: 0))
        guard let style = output.attribute(.paragraphStyle, at: last.location, effectiveRange: nil) as? NSParagraphStyle,
              let copy = style.mutableCopy() as? NSMutableParagraphStyle else { return }
        copy.paragraphSpacing = spacing
        output.addAttribute(.paragraphStyle, value: copy, range: last)
    }

    // MARK: Inlines

    func inlines(_ children: some Sequence<Markup>, style: Inline, into text: NSMutableAttributedString) {
        for child in children { inline(child, style: style, into: text) }
    }

    func inline(_ markup: Markup, style: Inline, into text: NSMutableAttributedString) {
        switch markup {
        case let plain as Markdown.Text:
            text.append(run(plain.string, style: style))
        case let emphasis as Emphasis:
            var inner = style
            inner.italic = true
            inlines(emphasis.children, style: inner, into: text)
        case let strong as Strong:
            var inner = style
            inner.bold = true
            inlines(strong.children, style: inner, into: text)
        case let strike as Strikethrough:
            var inner = style
            inner.strike = true
            inlines(strike.children, style: inner, into: text)
        case let code as InlineCode:
            var inner = style
            inner.code = true
            text.append(run(code.code, style: inner))
        case let link as Markdown.Link:
            var inner = style
            inner.link = link.destination.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            inlines(link.children, style: inner, into: text)
        case let image as Markdown.Image:
            text.append(self.image(image, style: style))
        case is SoftBreak:
            text.append(run(" ", style: style))
        case is LineBreak:
            text.append(run("\u{2028}", style: style))
        case let html as InlineHTML:
            var inner = style
            inner.color = theme.secondaryText.ns
            text.append(run(html.rawHTML, style: inner))
        default:
            inlines(markup.children, style: style, into: text)
        }
    }

    func run(_ string: String, style: Inline) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [:]
        if style.code {
            attributes[.font] = NSFont.monospacedSystemFont(ofSize: size * style.scale * 0.86, weight: style.bold ? .semibold : .regular)
            attributes[.foregroundColor] = theme.codeText.ns
            attributes[.backgroundColor] = theme.codeBackground.ns
        } else {
            attributes[.font] = bodyFont(size: size * style.scale, bold: style.bold, italic: style.italic)
            attributes[.foregroundColor] = style.color ?? theme.text.ns
        }
        if style.strike {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let link = style.link {
            attributes[.link] = link
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    func image(_ image: Markdown.Image, style: Inline) -> NSAttributedString {
        let alt = image.plainText
        if let source = image.source, let url = URL(string: source, relativeTo: baseURL)?.absoluteURL, url.isFileURL,
           let picture = NSImage(contentsOf: url), picture.size.width > 0 {
            let attachment = NSTextAttachment()
            attachment.image = picture
            let maxWidth: CGFloat = 640
            let scale = min(1, maxWidth / picture.size.width)
            attachment.bounds = NSRect(x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
            return NSAttributedString(attachment: attachment)
        }
        var inner = style
        inner.color = theme.secondaryText.ns
        inner.italic = true
        return run("[\(alt.isEmpty ? "imagem" : alt)]", style: inner)
    }

    func bodyFont(size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var descriptor = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
        if theme.serif, let serif = descriptor.withDesign(.serif) {
            descriptor = serif
        }
        if italic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic))
        }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }
}
