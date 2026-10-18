import AppKit
import PDFKit
import Testing
import JulliaCore
@testable import Jullia

@MainActor @Suite struct OutlineTests {
    /// Three pages and an outline, written by Core Graphics as a real file would carry it: Introdução (page 1),
    /// Parte um (page 2) with Seção inside it (page 3). PDFKit does not write an outline built in memory.
    static func pdfWithOutline() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for text in ["Começo.", "Meio.", "Fim."] {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)]))
            context.textPosition = CGPoint(x: 40, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        func item(_ title: String, page: Int, top: CGFloat, children: [[String: Any]] = []) -> [String: Any] {
            var entry: [String: Any] = [
                kCGPDFOutlineTitle as String: title,
                kCGPDFOutlineDestination as String: page,
                kCGPDFOutlineDestinationRect as String: CGRect(x: 0, y: top, width: 0, height: 0).dictionaryRepresentation,
            ]
            if !children.isEmpty { entry[kCGPDFOutlineChildren as String] = children }
            return entry
        }
        let outline: [String: Any] = [kCGPDFOutlineChildren as String: [
            item("Introdução", page: 1, top: 780),
            item("Parte um", page: 2, top: 780, children: [item("Seção", page: 3, top: 400)]),
        ]]
        CGPDFContextSetOutline(context, outline as CFDictionary)
        context.closePDF()
        try (data as Data).write(to: file)
        return file
    }

    /// A PDF without an outline whose first page prints a table of contents, followed by `pages` pages. Each line is
    /// drawn at its indent, and a line with a page is linked to it, as an exported book links its contents.
    static func pdfWithLinkedContents(_ lines: [(text: String, indent: CGFloat, page: Int?)], pages: Int) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        func draw(_ text: String, at point: CGPoint) -> CGFloat {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
            context.textPosition = point
            CTLineDraw(line, context)
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        context.beginPDFPage(nil)
        for (row, line) in lines.enumerated() {
            let origin = CGPoint(x: 40 + line.indent, y: 720 - CGFloat(row) * 24)
            let width = draw(line.text, at: origin)
            if let page = line.page {
                context.setDestination("p\(page)" as CFString, for: CGRect(x: origin.x, y: origin.y - 4, width: width, height: 20))
            }
        }
        context.endPDFPage()
        for page in 1...pages {
            context.beginPDFPage(nil)
            context.addDestination("p\(page)" as CFString, at: CGPoint(x: 0, y: 780))
            _ = draw("Página \(page).", at: CGPoint(x: 40, y: 700))
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: file)
        return file
    }

    @Test func markdownOutlineIsTheHeadingsAndGoesToThemAtTheTop() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Livro\n\nTexto.\n\n## Parte\n\nMais texto.\n\n### Detalhe\n".write(to: file, atomically: true, encoding: .utf8)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.map(\.title) == ["Livro", "Parte", "Detalhe"])
        #expect(document.outline.map(\.level) == [1, 2, 3])
        let part = try #require(document.outline.first { $0.title == "Parte" })
        document.go(to: part)
        let request = try #require(document.scrollRequest)
        #expect(document.text.substring(with: request.range) == "Parte")
        #expect(request.atTop)

        try "# Livro\n\nTexto novo.\n".write(to: file, atomically: true, encoding: .utf8)
        document.reload()
        #expect(document.outline.map(\.title) == ["Livro"])
    }

    @Test func pdfOutlineFollowsTheFilesOutlineWithItsDepth() throws {
        let file = try Self.pdfWithOutline()
        defer { try? FileManager.default.removeItem(at: file) }
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.map(\.title) == ["Introdução", "Parte um", "Seção"])
        #expect(document.outline.map(\.level) == [1, 1, 2])
        let section = try #require(document.outline.last)
        guard case .page(2, let point) = section.target else { Issue.record("\(section.target)"); return }
        #expect(point?.y == 400)
        document.go(to: section)
        #expect(document.pdfPageRequest?.page == 2)
    }

    @Test func pdfWithoutAnOutlineReadsItsLinkedContentsWithTheLinesAboveThemAsChapters() throws {
        let file = try Self.pdfWithLinkedContents([
            ("Sumário", 200, nil),
            ("Capítulo 1: Começo", 0, nil),
            ("Primeira seção", 20, 1),
            ("Segunda seção", 20, 2),
            ("Capítulo 2: Fim", 0, nil),
            ("Terceira seção", 20, 3),
            ("Quarta seção", 20, 4),
        ], pages: 4)
        defer { try? FileManager.default.removeItem(at: file) }
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.map(\.title) == [
            "Capítulo 1: Começo", "Primeira seção", "Segunda seção", "Capítulo 2: Fim", "Terceira seção", "Quarta seção",
        ])
        #expect(document.outline.map(\.level) == [1, 2, 2, 1, 2, 2])
        let chapter = try #require(document.outline.first { $0.title == "Capítulo 2: Fim" })
        document.go(to: chapter)
        #expect(document.pdfPageRequest?.page == 3)
        document.go(to: try #require(document.outline.last))
        #expect(document.pdfPageRequest?.page == 4)
    }

    @Test func linkedContentsTakeTheirLevelsFromTheIndentAndLeaveOutLeadersAndPageNumbers() throws {
        let file = try Self.pdfWithLinkedContents([
            ("Índice", 0, nil),
            ("Introdução .......... 2", 0, 1),
            ("Parte um .......... 3", 0, 2),
            ("Uma seção .......... 3", 20, 2),
            ("Parte dois, com um título", 0, 3),
            ("que continua .......... 4", 0, 3),
        ], pages: 3)
        defer { try? FileManager.default.removeItem(at: file) }
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.map(\.title) == ["Introdução", "Parte um", "Uma seção", "Parte dois, com um título que continua"])
        #expect(document.outline.map(\.level) == [1, 1, 2, 1])
    }

    @Test func linksThatDoNotRunInOrderAreNotContents() throws {
        let file = try Self.pdfWithLinkedContents([
            ("Como mostra a terceira página,", 0, 3),
            ("depois de voltar à primeira,", 0, 1),
            ("e da quarta, que vem antes", 0, 4),
            ("da segunda.", 0, 2),
        ], pages: 4)
        defer { try? FileManager.default.removeItem(at: file) }
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.isEmpty)
    }

    @Test func goingToAPageStaysWithinTheDocument() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try PDFTests.writePDF(["Um.", "Dois.", "Três."], to: file)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.outline.isEmpty)
        document.goToPDFPage(1)
        let first = try #require(document.pdfPageRequest)
        #expect(first.page == 1)
        document.goToPDFPage(99)
        #expect(document.pdfPageRequest?.page == 2)
        #expect(document.pdfPageRequest?.token == first.token + 1)
        document.goToPDFPage(-4)
        #expect(document.pdfPageRequest?.page == 0)
    }

    @Test func thePDFViewGoesToTheRequestedPageButANewViewDoesNotRepeatIt() async throws {
        let file = try Self.pdfWithOutline()
        defer { try? FileManager.default.removeItem(at: file) }
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)

        let view = AnnotatedPDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.installObservers()
        view.update(model: document, theme: .polar, appModel: model)
        document.goToPDFPage(2)
        view.update(model: document, theme: .polar, appModel: model)
        #expect(view.currentPage.flatMap { document.pdfDocument?.index(for: $0) } == 2)
        view.tearDown()

        document.pdfPosition = nil
        let again = AnnotatedPDFView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        again.installObservers()
        defer { again.tearDown() }
        again.update(model: document, theme: .polar, appModel: model)
        again.go(to: try #require(document.pdfDocument?.page(at: 0)))
        again.update(model: document, theme: .polar, appModel: model)
        #expect(again.currentPage.flatMap { document.pdfDocument?.index(for: $0) } == 0)
    }

    @Test func revealingTheOutlineOpensItsTabAndLeavesZen() throws {
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Um\n".write(to: file, atomically: true, encoding: .utf8)
        let model = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)
        model.openFile(file, as: .permanent)
        model.commentsCollapsed = true
        model.setZen(true)
        model.revealOutline()
        #expect(model.inspectorTab == .outline)
        #expect(!model.commentsCollapsed)
        #expect(!model.zen)
    }
}
