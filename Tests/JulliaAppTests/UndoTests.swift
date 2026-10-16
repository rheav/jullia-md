import Foundation
import JulliaCore
import Testing
@testable import Jullia

@MainActor @Suite struct UndoTests {
    /// A session with two Markdown files open, the first focused, and an undo stack grouped by hand as the run loop
    /// would group one event.
    @MainActor final class Session {
        let folder: URL
        let first: URL
        let second: URL
        let store: AnnotationStore
        let model: AppModel
        let undo: UndoManager
        private let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"

        init() throws {
            folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            first = folder.appending(path: "primeiro.md")
            second = folder.appending(path: "segundo.md")
            try "# Primeiro\n\nUm trecho para marcar e outro para comentar.\n".write(to: first, atomically: true, encoding: .utf8)
            try "# Segundo\n\nOutro arquivo aberto.\n".write(to: second, atomically: true, encoding: .utf8)
            let defaults = try #require(UserDefaults(suiteName: suite))
            let storeURL = folder.appending(path: "annotations.sqlite")
            model = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: storeURL)
            store = try AnnotationStore(url: storeURL)
            undo = UndoManager()
            undo.groupsByEvent = false
            model.undoManager = undo
            model.openFile(second, as: .permanent)
            model.openFile(first, as: .permanent)
        }

        deinit {
            UserDefaults().removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        var document: DocumentModel { model.document! }

        func step(_ change: () -> Void) {
            undo.beginUndoGrouping()
            change()
            undo.endUndoGrouping()
        }

        func range(_ text: String) -> NSRange { document.text.range(of: text) }
    }

    @Test func highlightsUndoAndRedoWithTheirNames() throws {
        let session = try Session()
        let document = session.document
        session.step { document.highlight(session.range("Um trecho"), color: .green) }
        let id = try #require(document.highlights.first?.id)
        #expect(session.undo.undoActionName == "Destaque")
        session.undo.undo()
        #expect(document.highlights.isEmpty)
        #expect(try session.store.highlights(for: document.key).isEmpty)
        #expect(session.undo.redoActionName == "Destaque")
        session.undo.redo()
        #expect(document.highlights.map(\.id) == [id])
        #expect(document.highlightRanges[id] == session.range("Um trecho"))
        #expect(try session.store.highlights(for: document.key).map(\.id) == [id])

        session.step { document.recolorHighlight(id, to: .pink) }
        #expect(session.undo.undoActionName == "Cor do destaque")
        session.undo.undo()
        #expect(document.highlights.first?.color == .green)
        #expect(try session.store.highlights(for: document.key).first?.color == .green)

        session.step { document.removeHighlight(id) }
        #expect(session.undo.undoActionName == "Remover destaque")
        session.undo.undo()
        #expect(document.highlights.first?.id == id)
        #expect(document.highlightRanges[id] == session.range("Um trecho"))
        #expect(session.model.count(for: session.first) == 1)
    }

    @Test func aHighlightThatSwallowsOthersComesBackAsOneStep() throws {
        let session = try Session()
        let document = session.document
        session.step { document.highlight(session.range("trecho"), color: .yellow) }
        let inner = try #require(document.highlights.first?.id)
        session.step { document.highlight(session.range("Um trecho para marcar"), color: .blue) }
        #expect(document.highlights.count == 1)
        #expect(session.undo.undoActionName == "Destaque")
        session.undo.undo()
        #expect(document.highlights.map(\.id) == [inner])
        #expect(document.highlights.first?.color == .yellow)
    }

    @Test func commentsUndoTheirWholeLife() throws {
        let session = try Session()
        let document = session.document
        session.step {
            document.startComment(on: session.range("outro para comentar"))
            document.submitComment(body: "Primeira ideia.", color: .blue)
        }
        let id = try #require(document.comments.first?.id)
        #expect(session.undo.undoActionName == "Comentário")
        session.undo.undo()
        #expect(document.comments.isEmpty)
        session.undo.redo()
        #expect(document.comments.map(\.id) == [id])
        #expect(document.commentRanges[id] == session.range("outro para comentar"))

        session.step { document.reply(to: id, body: "Uma resposta.") }
        #expect(session.undo.undoActionName == "Resposta")
        session.step { document.edit(id, body: "Ideia revista.") }
        #expect(session.undo.undoActionName == "Edição do comentário")
        session.undo.undo()
        #expect(document.comments.first { $0.id == id }?.body == "Primeira ideia.")
        #expect(try session.store.comments(for: document.key).first { $0.id == id }?.body == "Primeira ideia.")

        session.step { document.recolorComment(id, to: .orange) }
        #expect(session.undo.undoActionName == "Cor do comentário")
        session.undo.undo()
        #expect(document.comments.first { $0.id == id }?.color == .blue)

        session.step { document.setResolved(id, true) }
        #expect(session.undo.undoActionName == "Resolver comentário")
        session.undo.undo()
        #expect(document.comments.first { $0.id == id }?.resolvedAt == nil)
        session.undo.redo()
        let resolvedAt = try #require(document.comments.first { $0.id == id }?.resolvedAt)
        session.step { document.setResolved(id, false) }
        #expect(session.undo.undoActionName == "Reabrir comentário")
        session.undo.undo()
        #expect(document.comments.first { $0.id == id }?.resolvedAt == resolvedAt)
        session.step { document.setResolved(id, false) }

        session.step { document.deleteComment(id) }
        #expect(session.undo.undoActionName == "Excluir comentário")
        #expect(document.comments.isEmpty)
        session.undo.undo()
        #expect(document.topLevelComments.map(\.id) == [id])
        #expect(document.replies(to: id).map(\.body) == ["Uma resposta."])
        #expect(document.commentRanges[id] == session.range("outro para comentar"))
        #expect(try session.store.comments(for: document.key).count == 2)
        session.undo.redo()
        #expect(document.comments.isEmpty)
        #expect(try session.store.comments(for: document.key).isEmpty)
    }

    @Test func undoingAnotherTabsChangeBringsThatTabForward() throws {
        let session = try Session()
        let document = session.document
        session.step { document.highlight(session.range("Um trecho"), color: .green) }
        session.model.openFile(session.second, as: .permanent)
        #expect(session.model.document?.url == session.second)
        session.undo.undo()
        #expect(session.model.document?.url == session.first)
        #expect(document.highlights.isEmpty)
    }

    @Test func closingATabDropsItsChangesFromTheStack() throws {
        let session = try Session()
        session.step { session.document.highlight(session.range("Um trecho"), color: .green) }
        #expect(session.undo.canUndo)
        session.model.closeFocusedTab()
        #expect(!session.undo.canUndo)
        #expect(session.model.document?.url == session.second)
    }
}
