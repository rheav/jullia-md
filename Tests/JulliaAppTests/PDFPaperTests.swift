import AppKit
import JulliaCore
import PDFKit
import Testing
@testable import Jullia

/// PDFs drawn on the spot, one kind of page each, so these tests depend on no personal document.
private enum Pages {
    static let box = CGRect(x: 0, y: 0, width: 600, height: 800)

    static func document(_ pages: [(CGContext) -> Void]) throws -> PDFDocument {
        let data = NSMutableData()
        var bounds = box
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for page in pages {
            context.beginPDFPage(nil)
            page(context)
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    static func text(_ context: CGContext) {
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for line in 0..<30 { context.fill(CGRect(x: 60, y: 90 + CGFloat(line) * 20, width: 460, height: 7)) }
    }

    static func black(_ context: CGContext) {
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        context.fill(box)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 60, y: 400, width: 300, height: 10))
    }

    /// A smooth run of mid-tones, as a photo has.
    static func photo(width: Int = 64, height: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            for y in 0..<height {
                let t = CGFloat(x + y) / CGFloat(width + height)
                context.setFillColor(CGColor(srgbRed: 0.25 + t * 0.4, green: 0.35 + t * 0.3, blue: 0.2 + t * 0.2, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    /// White with a few lines of text, as a screenshot of a table has.
    static func screenshot() -> CGImage {
        let context = CGContext(data: nil, width: 300, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        for line in 0..<4 { context.fill(CGRect(x: 20, y: 14 + line * 22, width: 240, height: 2)) }
        return context.makeImage()!
    }
}

@MainActor @Suite struct PDFPaperSettingsTests {
    private func settings() throws -> (AppSettings, UserDefaults) {
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        settings.followSystem = false
        return (settings, defaults)
    }

    @Test func startsOnThePanelPaper() throws {
        let (settings, _) = try settings()
        settings.fixedTheme = .polar
        #expect(settings.pdfDark)
        #expect(settings.pdfTone == 2)
        #expect(settings.pdfPaper?.name == "Painel")
    }

    @Test func offOrInALightThemeTheresNoPaper() throws {
        let (settings, _) = try settings()
        settings.fixedTheme = .snow
        #expect(settings.pdfPaper == nil)
        settings.fixedTheme = .polar
        settings.pdfDark = false
        #expect(settings.pdfPaper == nil)
    }

    @Test func theToneFollowsTheTheme() throws {
        let (settings, _) = try settings()
        settings.pdfTone = 1
        settings.fixedTheme = .polar
        #expect(settings.pdfPaper?.name == "Nord")
        settings.fixedTheme = .ink
        #expect(settings.pdfPaper?.name == "Grafite")
    }

    @Test func theChoiceSurvivesARestart() throws {
        let (settings, defaults) = try settings()
        settings.pdfDark = false
        settings.pdfTone = 3
        let reopened = AppSettings(defaults: defaults)
        #expect(!reopened.pdfDark)
        #expect(reopened.pdfTone == 3)
    }
}

@MainActor @Suite struct PDFPageSurveyTests {
    @Test func aPageOfTextTakesThePaper() throws {
        let page = try #require(try Pages.document([Pages.text]).page(at: 0))
        let survey = PDFPageSurvey(page: page)
        #expect(survey.recolors)
        #expect(survey.pictures.isEmpty)
        #expect(survey.size == CGSize(width: 600, height: 800))
    }

    @Test func aDarkPageKeepsItsPixels() throws {
        let page = try #require(try Pages.document([Pages.black]).page(at: 0))
        #expect(!PDFPageSurvey(page: page).recolors)
    }

    @Test func aPageThatIsAllPictureKeepsItsPixels() throws {
        let image = Pages.photo()
        let document = try Pages.document([{ $0.draw(image, in: Pages.box) }])
        #expect(!PDFPageSurvey(page: try #require(document.page(at: 0))).recolors)
    }

    @Test func aPhotoOnALightPageKeepsItsPixels() throws {
        let image = Pages.photo()
        let rect = CGRect(x: 60, y: 300, width: 300, height: 200)
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: rect)
        }])
        let survey = PDFPageSurvey(page: try #require(document.page(at: 0)))
        #expect(survey.recolors)
        #expect(survey.pictures.count == 1)
        #expect(close(try #require(survey.pictures.first), rect))
    }

    @Test func aScreenshotOfATableIsRecoloured() throws {
        let image = Pages.screenshot()
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: CGRect(x: 60, y: 300, width: 460, height: 150))
        }])
        let survey = PDFPageSurvey(page: try #require(document.page(at: 0)))
        #expect(survey.recolors)
        #expect(survey.pictures.isEmpty)
    }

    @Test func aPictureInsideAFormIsFound() throws {
        let image = Pages.photo()
        let rect = CGRect(x: 60, y: 300, width: 300, height: 200)
        let inner = try Pages.document([{ $0.draw(image, in: rect) }])
        let reference = try #require(inner.page(at: 0)?.pageRef)
        // Drawing one PDF's page into another embeds it as a form.
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.drawPDFPage(reference)
        }])
        let survey = PDFPageSurvey(page: try #require(document.page(at: 0)))
        #expect(close(try #require(survey.pictures.first), rect))
    }

    @Test func aPictureUnderATransformIsFound() throws {
        let image = Pages.photo()
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.saveGState()
            context.translateBy(x: 100, y: 200)
            context.scaleBy(x: 2, y: 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
            context.restoreGState()
        }])
        let survey = PDFPageSurvey(page: try #require(document.page(at: 0)))
        #expect(close(try #require(survey.pictures.first), CGRect(x: 100, y: 200, width: 200, height: 200)))
    }

    @Test func tinyPicturesAreNotWorthAHole() throws {
        let image = Pages.photo(width: 8, height: 8)
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: CGRect(x: 60, y: 300, width: 16, height: 16))
        }])
        #expect(PDFPageSurvey(page: try #require(document.page(at: 0))).pictures.isEmpty)
    }

    @Test func aRotatedPagePutsThePictureWhereItIsShown() throws {
        let image = Pages.photo()
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: CGRect(x: 40, y: 40, width: 200, height: 100))
        }])
        let page = try #require(document.page(at: 0))
        page.rotation = 90
        let survey = PDFPageSurvey(page: page)
        #expect(survey.size == CGSize(width: 800, height: 600))
        // A quarter turn clockwise takes the lower left corner to the upper left.
        #expect(close(try #require(survey.pictures.first), CGRect(x: 40, y: 360, width: 100, height: 200)))
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}

@MainActor @Suite struct PDFPaperOverlayTests {
    private let polarPaper = Theme.polar.pdfPapers[2]

    private func filter() throws -> CIFilter { try #require(polarPaper.filter) }

    /// The sRGB bytes at a point counted from the top left. `NSBitmapImageRep.colorAt` converts them on the way out.
    private func colour(in image: NSImage, x: Int, y: Int) throws -> RGBA {
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                             space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (y * cg.width + x) * 4
        return RGBA(red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255, blue: Double(bytes[offset + 2]) / 255)
    }

    private func isClose(_ colour: RGBA, to expected: RGBA) -> Bool {
        abs(colour.red - expected.red) < 3 / 255 && abs(colour.green - expected.green) < 3 / 255
            && abs(colour.blue - expected.blue) < 3 / 255
    }

    /// A reader on a generated PDF, with a highlight on its text, and its window so PDFKit shows the overlays.
    private func reader(_ pages: [(CGContext) -> Void]) throws -> (AnnotatedPDFView, DocumentModel, AppModel, NSWindow, URL) {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "paper.pdf")
        try #require(try Pages.document(pages).dataRepresentation()).write(to: file)
        let store = try AnnotationStore(url: folder.appending(path: "annotations.sqlite"))
        let document = DocumentModel(url: file, store: store)
        document.apply(RenderOptions(theme: .polar))
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let app = AppModel(defaults: try #require(UserDefaults(suiteName: suite)), settings: AppSettings(defaults: try #require(UserDefaults(suiteName: suite))), storeURL: nil)
        let view = AnnotatedPDFView(frame: NSRect(x: 0, y: 0, width: 620, height: 820))
        view.minScaleFactor = 0.1
        view.maxScaleFactor = 8
        view.pageOverlayViewProvider = view
        view.installObservers()
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return (view, document, app, window, folder)
    }

    @Test func clicksGoThroughToThePage() throws {
        let page = try #require(try Pages.document([Pages.text]).page(at: 0))
        let overlay = PDFPaperOverlay(page: page)
        overlay.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        #expect(overlay.hitTest(NSPoint(x: 100, y: 100)) == nil)
    }

    @Test func aPageOfTextTakesTheFilterAndGivesItBack() throws {
        let page = try #require(try Pages.document([Pages.text]).page(at: 0))
        let overlay = PDFPaperOverlay(page: page)
        overlay.show(try filter())
        #expect(overlay.layer?.backgroundFilters?.count == 1)
        #expect(overlay.layer?.mask == nil)
        overlay.show(nil)
        #expect(overlay.layer?.backgroundFilters?.isEmpty != false)
    }

    @Test func aDarkPageStaysAsItIs() throws {
        let page = try #require(try Pages.document([Pages.black]).page(at: 0))
        let overlay = PDFPaperOverlay(page: page)
        overlay.show(try filter())
        #expect(overlay.layer?.backgroundFilters?.isEmpty != false)
    }

    @Test func aPhotoIsCutOutOfTheFilter() throws {
        let image = Pages.photo()
        let rect = CGRect(x: 60, y: 300, width: 300, height: 200)
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: rect)
        }])
        let overlay = PDFPaperOverlay(page: try #require(document.page(at: 0)))
        overlay.show(try filter())
        let mask = try #require(overlay.layer?.mask as? CAShapeLayer)
        let path = try #require(mask.path)
        #expect(path.contains(CGPoint(x: 20, y: 20), using: .evenOdd))
        #expect(!path.contains(CGPoint(x: rect.midX, y: rect.midY), using: .evenOdd))
    }

    @Test func thePaperReachesOverlaysAlreadyOnScreen() throws {
        let (view, document, app, window, folder) = try reader([Pages.text])
        defer {
            window.close()
            view.tearDown()
            try? FileManager.default.removeItem(at: folder)
        }
        view.update(model: document, theme: .polar, appModel: app)
        let page = try #require(document.pdfDocument?.page(at: 0))
        let overlay = try #require(view.pdfView(view, overlayViewFor: page) as? PDFPaperOverlay)
        view.pdfView(view, willDisplayOverlayView: overlay, for: page)
        #expect(overlay.layer?.backgroundFilters?.isEmpty != false)
        #expect(view.pageShadowsEnabled)

        view.update(model: document, theme: .polar, appModel: app, paper: polarPaper)
        #expect(overlay.layer?.backgroundFilters?.count == 1)
        #expect(!view.pageShadowsEnabled)

        view.update(model: document, theme: .polar, appModel: app)
        #expect(overlay.layer?.backgroundFilters?.isEmpty != false)
        #expect(view.pageShadowsEnabled)

        view.pdfView(view, willEndDisplayingOverlayView: overlay, for: page)
        view.update(model: document, theme: .polar, appModel: app, paper: polarPaper)
        #expect(overlay.layer?.backgroundFilters?.isEmpty != false)
    }

    @Test func anOverlayComingBackTakesTheCurrentPaper() throws {
        let (view, document, app, window, folder) = try reader([Pages.text])
        defer {
            window.close()
            view.tearDown()
            try? FileManager.default.removeItem(at: folder)
        }
        view.update(model: document, theme: .polar, appModel: app, paper: polarPaper)
        let page = try #require(document.pdfDocument?.page(at: 0))
        let overlay = try #require(view.pdfView(view, overlayViewFor: page) as? PDFPaperOverlay)
        view.pdfView(view, willDisplayOverlayView: overlay, for: page)
        #expect(overlay.layer?.backgroundFilters?.count == 1)
    }

    @Test func marksUseLightColoursOnThePaperThatDarkensThem() throws {
        let (view, document, app, window, folder) = try reader([{ context in
            let text = NSAttributedString(string: "Um trecho para marcar", attributes: [.font: NSFont.systemFont(ofSize: 18)])
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(location: 0, length: 0),
                                                 CGPath(rect: Pages.box.insetBy(dx: 40, dy: 60), transform: nil), nil)
            CTFrameDraw(frame, context)
        }])
        defer {
            window.close()
            view.tearDown()
            try? FileManager.default.removeItem(at: folder)
        }
        let pdf = try #require(document.pdfDocument)
        document.selectPDF(try #require(pdf.findString("trecho", withOptions: []).first))
        document.highlight(document.selection, color: .yellow)
        let page = try #require(pdf.page(at: 0))
        func fill() throws -> NSColor { try #require(page.annotations.first?.color.usingColorSpace(.sRGB)) }

        view.update(model: document, theme: .polar, appModel: app)
        #expect(abs(try fill().alphaComponent - Theme.polar.tone(.yellow).fill.alpha) < 0.01)
        view.update(model: document, theme: .polar, appModel: app, paper: polarPaper)
        #expect(abs(try fill().alphaComponent - Theme.snow.tone(.yellow).fill.alpha) < 0.01)
        view.update(model: document, theme: .polar, appModel: app)
        #expect(abs(try fill().alphaComponent - Theme.polar.tone(.yellow).fill.alpha) < 0.01)
    }

    @Test func aThumbnailTakesThePaperAndKeepsThePhoto() throws {
        let image = Pages.photo()
        let rect = CGRect(x: 150, y: 300, width: 300, height: 200)
        let document = try Pages.document([{ context in
            Pages.text(context)
            context.draw(image, in: rect)
        }])
        let page = try #require(document.page(at: 0))
        let size = NSSize(width: 300, height: 400)
        let dark = page.thumbnail(of: size, on: polarPaper)
        let original = page.thumbnail(of: size, on: nil)
        let corner = try colour(in: dark, x: 4, y: 4)
        #expect(isClose(corner, to: polarPaper.paper))
        #expect(isClose(try colour(in: original, x: 4, y: 4), to: RGBA(0xFFFFFF)))
        let cg = try #require(dark.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let scale = cg.width / 300
        let (x, y) = (150 * scale, 200 * scale)
        let kept = try colour(in: dark, x: x, y: y), source = try colour(in: original, x: x, y: y)
        #expect(isClose(kept, to: source))
    }

    @Test func aDarkPageKeepsItsThumbnail() throws {
        let page = try #require(try Pages.document([Pages.black]).page(at: 0))
        let size = NSSize(width: 300, height: 400)
        let dark = page.thumbnail(of: size, on: polarPaper), original = page.thumbnail(of: size, on: nil)
        let a = try colour(in: dark, x: 4, y: 4), b = try colour(in: original, x: 4, y: 4)
        #expect(isClose(a, to: b))
    }
}
