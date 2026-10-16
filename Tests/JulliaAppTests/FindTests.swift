import AppKit
import PDFKit
import Testing
import JulliaCore
@testable import Jullia

@MainActor @Suite struct FindTests {
    static func pdfDocument(_ pages: [String]) throws -> (DocumentModel, URL) {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try PDFTests.writePDF(pages, to: file)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        document.pdfFind.pasteboard = .withUniqueName()
        return (document, file)
    }

    @Test func markdownFindCommandsGoToTheTextFinder() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Título\n\nUm texto para buscar.\n".write(to: file, atomically: true, encoding: .utf8)
        let document = DocumentModel(url: file, store: nil)
        document.apply(RenderOptions(theme: .polar))
        #expect(document.findRequest == nil)
        document.find(.show)
        let shown = try #require(document.findRequest)
        #expect(shown.action.textFinderAction == .showFindInterface)
        document.find(.next)
        #expect(document.findRequest?.action.textFinderAction == .nextMatch)
        #expect(document.findRequest?.token == shown.token + 1)
        document.find(.previous)
        #expect(document.findRequest?.action.textFinderAction == .previousMatch)
        document.find(.useSelection)
        #expect(document.findRequest?.action.textFinderAction == .setSearchString)
        #expect(!document.pdfFind.isVisible)
    }

    @Test func pdfFindIgnoresCaseAndAccentsAndWrapsAround() throws {
        let (document, file) = try Self.pdfDocument(["Ação na primeira.", "Outra AÇÃO aqui.", "Sem nada.", "acao no fim."])
        defer { try? FileManager.default.removeItem(at: file) }
        let find = document.pdfFind
        document.find(.show)
        #expect(find.isVisible)
        #expect(find.focusToken == 1)
        find.query = "acao"
        #expect(find.matches.count == 3)
        #expect(find.current == 0)
        let revealed = find.revealToken
        document.find(.next)
        #expect(find.current == 1)
        #expect(find.revealToken == revealed + 1)
        document.find(.next)
        document.find(.next)
        #expect(find.current == 0)
        document.find(.previous)
        #expect(find.current == 2)
        find.query = "inexistente"
        #expect(find.matches.isEmpty)
        #expect(find.current == nil)
        find.close()
        #expect(!find.isVisible)
        #expect(find.query == "inexistente")
    }

    @Test func pdfSearchStartsOnTheReadersPage() throws {
        let (document, file) = try Self.pdfDocument(["palavra um", "nada", "palavra dois", "palavra três"])
        defer { try? FileManager.default.removeItem(at: file) }
        document.pdfPageNumber = 2
        document.pdfFind.query = "palavra"
        #expect(document.pdfFind.matches.count == 3)
        let current = try #require(document.pdfFind.current)
        let page = try #require(document.pdfFind.matches[current].pages.first)
        #expect(document.pdfDocument?.index(for: page) == 2)
    }

    @Test func pdfFindSharesTheQueryThroughTheFindPasteboard() throws {
        let (document, file) = try Self.pdfDocument(["Um trecho marcado aqui.", "Outro trecho."])
        defer { try? FileManager.default.removeItem(at: file) }
        let find = document.pdfFind
        let pdf = try #require(document.pdfDocument)
        document.selectPDF(try #require(pdf.findString("trecho", withOptions: []).first))
        document.find(.useSelection)
        #expect(find.query == "trecho")
        #expect(find.matches.count == 2)
        #expect(find.pasteboard.string(forType: .string) == "trecho")

        let (other, otherFile) = try Self.pdfDocument(["Outro trecho."])
        defer { try? FileManager.default.removeItem(at: otherFile) }
        other.pdfFind.pasteboard = find.pasteboard
        other.find(.show)
        #expect(other.pdfFind.query == "trecho")
        #expect(other.pdfFind.matches.count == 1)
    }

    @Test func pdfViewLightsTheMatchesAndSelectsTheCurrentOne() async throws {
        let (document, file) = try Self.pdfDocument(["Uma palavra aqui.", "Outra palavra ali.", "E palavra no fim."])
        defer { try? FileManager.default.removeItem(at: file) }
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)
        let view = AnnotatedPDFView(frame: NSRect(x: 0, y: 0, width: 700, height: 900))
        view.installObservers()
        defer { view.tearDown() }
        view.update(model: document, theme: .polar, appModel: model)
        document.find(.show)
        document.pdfFind.query = "palavra"
        document.find(.next)
        view.update(model: document, theme: .polar, appModel: model)
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.highlightedSelections?.count == 3)
        #expect(view.currentSelection?.pages.first.flatMap { document.pdfDocument?.index(for: $0) } == 1)
        #expect(document.text.substring(with: document.selection) == "palavra")
        document.pdfFind.close()
        view.update(model: document, theme: .polar, appModel: model)
        #expect(view.highlightedSelections == nil)
    }

    @Test func pdfFindSearchesTheReloadedDocument() throws {
        let (document, file) = try Self.pdfDocument(["alfa", "beta"])
        defer { try? FileManager.default.removeItem(at: file) }
        document.find(.show)
        document.pdfFind.query = "gama"
        #expect(document.pdfFind.matches.isEmpty)
        try PDFTests.writePDF(["alfa", "gama", "gama"], to: file)
        document.reload()
        #expect(document.pdfFind.matches.count == 2)
        #expect(document.pdfFind.matches.first?.pages.first?.document === document.pdfDocument)
    }
}
