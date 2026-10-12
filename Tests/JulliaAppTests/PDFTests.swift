import AppKit
import PDFKit
import SwiftUI
import Testing
import JulliaCore
@testable import Jullia

@MainActor @Suite struct PDFTests {
    static func writePDF(_ pages: [String], to url: URL) throws {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for text in pages {
            context.beginPDFPage(nil)
            let attributed = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: bounds.insetBy(dx: 40, dy: 60), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
    }

    @Test func opensAndPersistsPDFAnnotationsWithoutWritingSource() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "reading.pdf")
        try Self.writePDF(["Primeira página: ação e café.", "Segunda página: lembrar este trecho."], to: file)
        let original = try Data(contentsOf: file)
        let store = try AnnotationStore(url: folder.appending(path: "annotations.sqlite"))
        let document = DocumentModel(url: file, store: store)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.loadError == nil)
        let pdf = try #require(document.pdfDocument)
        #expect(pdf.pageCount == 2)
        let selection = try #require(pdf.findString("lembrar este trecho", withOptions: []).first)
        document.selectPDF(selection)
        document.highlight(document.selection, color: .green)
        document.startComment(on: document.selection)
        document.submitComment(body: "Uma observação", color: .blue)
        let comment = try #require(document.comments.first)
        document.reply(to: comment.id, body: "Uma resposta")
        document.focusComment(comment.id)
        #expect(document.scrollRequest?.anchor?.pdf?.first?.pageIndex == 1)
        #expect(document.highlights.first?.anchor.pdf?.first?.pageIndex == 1)
        let reopened = DocumentModel(url: file, store: store)
        reopened.apply(RenderOptions(theme: .paper))
        #expect(reopened.highlights.count == 1)
        #expect(reopened.orphanHighlights.isEmpty)
        #expect(reopened.listedComments(resolved: false).count == 1)
        #expect(reopened.replies(to: comment.id).count == 1)
        #expect(try Data(contentsOf: file) == original)
        #expect(FileTree.scan(folder).files.map(\.name) == ["reading.pdf"])
    }

    @Test func disjointAndCrossPageSelectionsRoundTripExactly() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.writePDF(["ação café omitido fim", "", "Outra página final"], to: file)
        let pdf = try #require(PDFDocument(url: file))
        let index = PDFTextIndex(document: pdf)
        let selected = PDFSelection(document: pdf)
        for word in ["ação", "fim", "final"] {
            selected.add(try #require(pdf.findString(word, withOptions: []).last))
        }
        let anchor = try #require(index.anchor(for: selected))
        #expect(anchor.pdf?.map(\.pageIndex) == [0, 0, 2])
        let restored = try #require(index.selection(for: anchor))
        #expect(restored.string?.contains("omitido") == false)
        #expect(restored.string?.contains("ação") == true)
        #expect(restored.string?.contains("final") == true)
        #expect(index.anchor(for: restored)?.pdf == anchor.pdf)
    }

    @Test func reloadReanchorsMovedPagesAndOrphansMissingPassages() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.writePDF(["Trecho especial para lembrar."], to: file)
        let document = DocumentModel(url: file, store: try AnnotationStore(url: nil))
        document.apply(RenderOptions(theme: .polar))
        document.highlight(document.text.range(of: "Trecho especial"), color: .yellow)
        try Self.writePDF(["Uma página inserida.", "Introdução. Trecho especial para lembrar."], to: file)
        document.reload()
        #expect(document.highlights.first?.anchor.pdf?.first?.pageIndex == 1)
        #expect(document.orphanHighlights.isEmpty)
        document.apply(RenderOptions(theme: .paper, fontSize: 22))
        #expect(document.orphanHighlights.isEmpty)
        try Self.writePDF(["O trecho foi removido."], to: file)
        document.reload()
        #expect(document.orphanHighlights.count == 1)
    }

    @Test func invalidAndImageOnlyPDFsHaveHonestStates() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a PDF".utf8).write(to: file)
        let invalid = DocumentModel(url: file, store: nil)
        #expect(invalid.loadError != nil)
        try Self.writePDF([""], to: file)
        let blank = DocumentModel(url: file, store: nil)
        blank.apply(RenderOptions(theme: .polar))
        #expect(blank.loadError == nil)
        #expect(blank.pdfDocument?.pageCount == 1)
        #expect(blank.hasPDFText == false)
        blank.startComment(on: nil)
        blank.submitComment(body: "Sobre o documento", color: nil)
        #expect(blank.comments.count == 1)
    }

    @Test func protectedPDFUnlocksWithoutSavingPasswordOrChangingFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.writePDF(["Conteúdo protegido"], to: file)
        let pdf = try #require(PDFDocument(url: file))
        let encrypted = try #require(pdf.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner", PDFDocumentWriteOption.userPasswordOption: "secret"]))
        try encrypted.write(to: file)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.pdfLocked)
        #expect(document.pdfIndex == nil)
        document.unlockPDF(password: "wrong")
        #expect(document.pdfLocked)
        #expect(document.passwordError != nil)
        document.unlockPDF(password: "secret")
        #expect(!document.pdfLocked)
        #expect(document.text.contains("Conteúdo protegido"))
        document.highlight(document.text.range(of: "protegido"), color: .blue)
        #expect(document.highlights.count == 1)
        #expect(try Data(contentsOf: file) == encrypted)
    }

    @Test func nativeViewSelectionActionsAndDecorationsPreserveOriginalAnnotations() async throws {
        let suite = "dev.rheav.jullia.pdf-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.writePDF(["PDF no Jullia\n\nSelecione este trecho para destacar e comentar.\n\nAção, café e leitura.", "A segunda página também pode receber comentários."], to: file)
        let original = try Data(contentsOf: file)
        let settings = AppSettings(defaults: defaults)
        let app = AppModel(defaults: defaults, settings: settings, storeURL: nil)
        app.openFile(file)
        let model = try #require(app.document)
        let pdf = try #require(model.pdfDocument)
        let page = try #require(pdf.page(at: 0))
        let originalNote = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 20, height: 20), forType: .text, withProperties: nil)
        page.addAnnotation(originalNote)
        _ = NSApplication.shared
        let view = AnnotatedPDFView(frame: CGRect(x: 0, y: 0, width: 650, height: 760))
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        view.installObservers()
        defer { view.tearDown() }
        view.update(model: model, theme: .polar, appModel: app)
        view.layoutSubtreeIfNeeded()
        let selection = try #require(pdf.findString("Selecione este trecho", withOptions: []).first)
        view.setCurrentSelection(selection, animate: false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.hasSelection)
        let pill = try #require(view.subviews.compactMap { $0 as? NSHostingView<SelectionPill> }.first)
        #expect(!pill.isHidden)
        app.commentsCollapsed = true
        pill.rootView.onChat()
        #expect(model.chat.anchor?.quote == "Selecione este trecho")
        #expect(model.chat.anchor?.pdf?.first?.pageIndex == 0)
        #expect(app.inspectorTab == .chat)
        #expect(!app.commentsCollapsed)
        pill.rootView.onColor(.green)
        view.update(model: model, theme: .polar, appModel: app)
        #expect(model.highlights.first?.color == .green)
        #expect(page.annotations.contains { $0.type == "Highlight" })
        #expect(page.annotations.contains { $0 === originalNote })
        view.setCurrentSelection(selection, animate: false)
        try await Task.sleep(for: .milliseconds(100))
        let selectedBounds = selection.bounds(for: page)
        let click = view.convert(CGPoint(x: selectedBounds.midX, y: selectedBounds.midY), from: page)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: click, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        #expect(view.menu(for: event)?.items.first?.title == "Destacar", "A current selection must take precedence over an existing highlight under the pointer")
        #expect(view.menu(for: event)?.items.contains { $0.title == "Conversar sobre trecho" } == true)
        pill.rootView.onComment()
        #expect(model.composing?.anchor?.quote == "Selecione este trecho")
        model.submitComment(body: "Comentário no PDF, vinculado ao trecho selecionado.", color: .blue)
        view.update(model: model, theme: .polar, appModel: app)
        #expect(page.annotations.contains { $0.type == "Underline" })
        let comment = try #require(model.comments.first)
        model.setResolved(comment.id, true)
        view.update(model: model, theme: .polar, appModel: app)
        #expect(!page.annotations.contains { $0.type == "Underline" })
        model.setResolved(comment.id, false)
        model.focusComment(comment.id)
        view.update(model: model, theme: .paper, appModel: app)
        #expect(page.annotations.contains { $0.type == "Underline" })
        #expect(try Data(contentsOf: file) == original)
        let thumbnail = page.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
        let tiff = try #require(thumbnail.tiffRepresentation)
        let pixels = try #require(NSBitmapImageRep(data: tiff))
        let bounds = selection.bounds(for: page)
        let scale = Double(pixels.pixelsWide) / 600
        var coloredPixels = 0
        for x in Int(bounds.minX * scale)..<Int(bounds.maxX * scale) {
            for y in Int((800 - bounds.maxY) * scale)..<Int((800 - bounds.minY) * scale) {
                if let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.05 { coloredPixels += 1 }
            }
        }
        #expect(coloredPixels > 0, "PDF annotations must actually render, not just exist in the page's annotation list")
        view.tearDown()
        #expect(page.annotations.allSatisfy { $0 === originalNote || $0 === originalNote.popup })
        #expect(page.annotations.contains { $0 === originalNote })

        if let path = ProcessInfo.processInfo.environment["JULLIA_PDF_SCREENSHOT"] {
            let pagePath = URL(fileURLWithPath: path).deletingPathExtension().path + "-page.png"
            try #require(pixels.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: pagePath))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1320, height: 880), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: MainView().environment(app).environment(settings))
            window.contentView = host
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            if let reader = findPDFView(in: host) {
                reader.setCurrentSelection(selection, animate: false)
                try await Task.sleep(for: .milliseconds(100))
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    private func findPDFView(in view: NSView) -> AnnotatedPDFView? {
        if let pdf = view as? AnnotatedPDFView { return pdf }
        for child in view.subviews {
            if let pdf = findPDFView(in: child) { return pdf }
        }
        return nil
    }

    @Test func disjointDecorationsDoNotCoverUnselectedText() throws {
        let suite = "dev.rheav.jullia.pdf-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.writePDF(["ação café omitido fim"], to: file)
        let app = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)
        app.openFile(file)
        let model = try #require(app.document)
        let pdf = try #require(model.pdfDocument)
        let page = try #require(pdf.page(at: 0))
        let selection = PDFSelection(document: pdf)
        selection.add(try #require(pdf.findString("ação", withOptions: []).first))
        selection.add(try #require(pdf.findString("fim", withOptions: []).first))
        model.selectPDF(selection)
        model.highlight(model.selection, color: .green)
        let view = AnnotatedPDFView()
        defer { view.tearDown() }
        view.update(model: model, theme: .polar, appModel: app)
        let omitted = try #require(pdf.findString("omitido", withOptions: []).first).bounds(for: page)
        #expect(page.annotations.filter { $0.type == "Highlight" }.count == 2)
        #expect(!page.annotations.contains { $0.bounds.contains(CGPoint(x: omitted.midX, y: omitted.midY)) })
    }
}
