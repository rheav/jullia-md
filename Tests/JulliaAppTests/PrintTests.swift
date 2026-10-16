import AppKit
import PDFKit
import Testing
import JulliaCore
@testable import Jullia

@MainActor @Suite struct PrintTests {
    /// Runs a print operation into a PDF file, without panels, and reads it back.
    static func printed(_ operation: NSPrintOperation, to url: URL) throws -> PDFDocument {
        operation.printInfo.jobDisposition = .save
        operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        return try #require(PDFDocument(url: url))
    }

    @Test func darkThemesGoOnPaperInTheirLightSibling() {
        #expect(DocumentPrinter.paperTheme(for: .polar).id == .snow)
        #expect(DocumentPrinter.paperTheme(for: .ink).id == .paper)
        #expect(DocumentPrinter.paperTheme(for: .snow).id == .snow)
        #expect(DocumentPrinter.paperTheme(for: .paper).id == .paper)
    }

    @Test func markdownPrintsItsTextOnPagesWithHighlightsAndUnderlines() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "notes.md")
        let paragraphs = (1...80).map { "Parágrafo \($0) com texto suficiente para ocupar uma linha inteira na página." }
        try ("# Notas\n\n" + paragraphs.joined(separator: "\n\n") + "\n\nFrase final do documento. [Outro arquivo](outro.md)\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let store = try AnnotationStore(url: folder.appending(path: "annotations.sqlite"))
        let document = DocumentModel(url: file, store: store)
        document.apply(RenderOptions(theme: .polar, fontSize: 16))
        let highlighted = document.text.range(of: "Parágrafo 3 com")
        document.highlight(highlighted, color: .green)
        let commented = document.text.range(of: "Frase final")
        document.startComment(on: commented)
        document.submitComment(body: "Revisar.", color: .blue)

        let operation = try #require(DocumentPrinter.operation(for: document, theme: .polar, fontSize: 16))
        let view = try #require(operation.view as? NSTextView)
        let storage = try #require(view.textStorage)
        #expect(view.string == document.text as String)
        #expect(!view.drawsBackground)
        #expect(!operation.printInfo.isVerticallyCentered)
        #expect(storage.attribute(.backgroundColor, at: highlighted.location, effectiveRange: nil) as? NSColor
            == Theme.snow.tone(.green).fill.ns)
        #expect(storage.attribute(.underlineColor, at: commented.location, effectiveRange: nil) as? NSColor
            == Theme.snow.tone(.blue).stroke.ns)
        let link = document.text.range(of: "Outro arquivo")
        #expect(storage.attribute(.foregroundColor, at: link.location, effectiveRange: nil) as? NSColor == Theme.snow.link.ns)
        #expect(operation.printInfo.leftMargin == DocumentPrinter.paperMargin)
        #expect(operation.jobTitle == "notes")

        let pdf = try Self.printed(operation, to: folder.appending(path: "printed.pdf"))
        #expect(pdf.pageCount > 1)
        #expect(pdf.page(at: 0)?.string?.contains("Notas") == true)
        #expect(pdf.page(at: pdf.pageCount - 1)?.string?.contains("Frase final do documento.") == true)
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("# Notas"))
    }

    @Test func pdfPrintsItsOwnPages() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "reading.pdf")
        try PDFTests.writePDF(["Primeira página.", "Segunda página.", "Terceira página."], to: file)
        let original = try Data(contentsOf: file)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .ink))

        let operation = try #require(DocumentPrinter.operation(for: document, theme: .ink, fontSize: 16))
        let pdf = try Self.printed(operation, to: folder.appending(path: "printed.pdf"))
        #expect(pdf.pageCount == 3)
        #expect(pdf.page(at: 1)?.string?.contains("Segunda página.") == true)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func nothingToPrintWithoutReadableContent() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        let document = DocumentModel(url: missing, store: nil)
        document.apply(RenderOptions(theme: .snow))
        #expect(document.loadError != nil)
        #expect(DocumentPrinter.operation(for: document, theme: .snow, fontSize: 16) == nil)
    }
}
