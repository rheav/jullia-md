import AppKit
import JulliaCore
import PDFKit

/// ⌘P: a document through the system print panel. A PDF prints its own pages, with Jullia's highlights on them;
/// Markdown is laid out again for paper, in the light theme closest to the one on screen, with its highlights and
/// comment underlines.
@MainActor
enum DocumentPrinter {
    /// Screen points to paper, as browsers print: 16 pt on screen comes out at 12 pt.
    static let paperScale: CGFloat = 0.75
    /// Wide enough for the widest image the renderer makes, scaled down with the rest.
    static let minLayoutWidth: CGFloat = 640
    /// 2 cm around the text. Page Setup has no margins, and the shared print info's are often zero, which would put
    /// the text against the printer's edge.
    static let paperMargin: CGFloat = 57

    /// The theme a document goes on paper in: a dark theme's light sibling with the same typeface.
    static func paperTheme(for theme: Theme) -> Theme {
        switch theme.id {
        case .polar: .snow
        case .ink: .paper
        case .snow, .paper: theme
        }
    }

    /// The print operation for a document, or nil when there is nothing to print (an unreadable or locked file).
    /// Starts from the shared print info, so Page Setup applies, without changing it.
    static func operation(
        for document: DocumentModel, theme: Theme, fontSize: CGFloat, printInfo: NSPrintInfo = .shared
    ) -> NSPrintOperation? {
        guard document.loadError == nil, let info = printInfo.copy() as? NSPrintInfo else { return nil }
        info.isVerticallyCentered = false
        let operation: NSPrintOperation?
        if document.isPDF {
            guard !document.pdfLocked, let pdf = document.pdfDocument else { return nil }
            operation = pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true)
        } else {
            operation = textOperation(for: document, theme: paperTheme(for: theme), fontSize: fontSize, info: info)
        }
        operation?.jobTitle = document.url.deletingPathExtension().lastPathComponent
        return operation
    }

    /// The text in an off-screen TextKit 1 view (code blocks and quotes are `NSTextBlock`s), as wide as the page at
    /// `paperScale`, fitted to the page width and cut into pages between lines.
    private static func textOperation(
        for document: DocumentModel, theme: Theme, fontSize: CGFloat, info: NSPrintInfo
    ) -> NSPrintOperation {
        let options = RenderOptions(theme: theme, fontSize: fontSize, baseURL: document.url.deletingLastPathComponent())
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.leftMargin = paperMargin
        info.rightMargin = paperMargin
        info.topMargin = paperMargin
        info.bottomMargin = paperMargin
        let pageWidth = info.paperSize.width - info.leftMargin - info.rightMargin
        let width = max(pageWidth / paperScale, minLayoutWidth)

        let view = NSTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        view.isEditable = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(document.printableText(options: options))
        if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
        view.sizeToFit()
        return NSPrintOperation(view: view, printInfo: info)
    }
}
