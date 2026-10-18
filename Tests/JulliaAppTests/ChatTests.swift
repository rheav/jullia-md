import AppKit
import FoundationModels
import JulliaCore
import PDFKit
import SwiftUI
import Testing
@testable import Jullia

@MainActor
final class TestChatGenerator: PassageChatGenerating {
    var unavailabilityReason: String?
    var histories: [[ChatTurn]] = []
    var passages: [String] = []
    var failure: Error?
    var paused = false
    var continuation: CheckedContinuation<Void, Never>?
    var callback: (@MainActor (String) -> Void)?

    func respond(passage: String, history: [ChatTurn], question: String,
                 onUpdate: @escaping @MainActor (String) -> Void,
                 onHistoryTrimmed: @escaping @MainActor () -> Void) async throws {
        histories.append(history)
        passages.append(passage)
        callback = onUpdate
        onUpdate("Uma resposta")
        if paused { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        onUpdate("Uma resposta sobre: \(question)")
    }
}

@MainActor @Suite struct ChatTests {
    let anchor = TextAnchor(start: 0, end: 6, quote: "Trecho", prefix: "", suffix: "")

    @Test func followupsKeepSuccessfulTurnsAndCapturedPassage() async throws {
        let generator = TestChatGenerator()
        let chat = PassageChat(generator: generator)
        chat.start(anchor: anchor)
        chat.draft = "Explique."
        await chat.send()?.value
        chat.draft = "E o ponto principal?"
        await chat.send()?.value
        #expect(generator.histories.count == 2)
        #expect(generator.histories[1] == [ChatTurn(question: "Explique.", answer: "Uma resposta sobre: Explique.")])
        #expect(generator.passages == ["Trecho", "Trecho"])
        #expect(chat.messages.count == 4)
        #expect(!chat.isResponding)
        #expect(chat.error == nil)
        chat.start(anchor: anchor)
        #expect(chat.messages.count == 4, "Opening the same passage should keep its conversation")
    }

    @Test func historyReopensAndContinuesWithStableMessageIDs() async throws {
        let store = try AnnotationStore(url: nil)
        let chat = PassageChat(generator: TestChatGenerator(), store: store, docPath: "/a.md")
        chat.start(anchor: anchor)
        chat.draft = "Primeira pergunta"
        await chat.send()?.value
        let id = try #require(chat.currentID)
        let firstMessages = chat.messages
        chat.clear()
        #expect(chat.anchor == nil)
        #expect(chat.conversations.count == 1)
        chat.start(anchor: anchor)
        chat.draft = "Outra conversa, mesmo trecho"
        await chat.send()?.value
        #expect(chat.conversations.count == 2)
        #expect(chat.currentID != id)
        let generator = TestChatGenerator()
        let reopened = PassageChat(generator: generator, store: store, docPath: "/a.md")
        #expect(reopened.conversations.count == 2)
        reopened.openConversation(id)
        #expect(reopened.messages == firstMessages)
        #expect(reopened.anchor == anchor)
        reopened.draft = "Continue"
        await reopened.send()?.value
        #expect(generator.histories.first == [ChatTurn(question: "Primeira pergunta", answer: "Uma resposta sobre: Primeira pergunta")])
        #expect(try store.conversations(for: "/a.md").first?.messages.count == 4)
        #expect(reopened.persistenceError == nil)
        let other = PassageChat(generator: generator, store: store, docPath: "/b.md")
        #expect(other.conversations.isEmpty)
    }

    @Test func deletingActiveGenerationCannotResurrectConversation() async throws {
        let store = try AnnotationStore(url: nil)
        let generator = TestChatGenerator()
        generator.paused = true
        let chat = PassageChat(generator: generator, store: store, docPath: "/a.pdf")
        chat.start(anchor: anchor)
        chat.draft = "Explique"
        let task = try #require(chat.send())
        while generator.continuation == nil { await Task.yield() }
        let id = try #require(chat.currentID)
        #expect(try store.conversations(for: "/a.pdf").count == 1)
        chat.deleteConversation(id)
        generator.callback?("Chegou depois da exclusão")
        generator.continuation?.resume()
        await task.value
        #expect(chat.currentID == nil)
        #expect(chat.messages.isEmpty)
        #expect(chat.conversations.isEmpty)
        #expect(!chat.isResponding)
        #expect(try store.conversations(for: "/a.pdf").isEmpty)
        chat.cancel()
        #expect(try store.conversations(for: "/a.pdf").isEmpty)
    }

    @Test func openingHistoryInterruptsPreviousGenerationAndDeletionPreservesActiveChat() async throws {
        let store = try AnnotationStore(url: nil)
        let generator = TestChatGenerator()
        let chat = PassageChat(generator: generator, store: store, docPath: "/a.md")
        chat.start(anchor: anchor)
        chat.draft = "Primeira conversa"
        await chat.send()?.value
        let firstID = try #require(chat.currentID)
        chat.clear()
        chat.start(anchor: anchor)
        let secondID = try #require(chat.currentID)
        generator.paused = true
        chat.draft = "Segunda conversa"
        let task = try #require(chat.send())
        while generator.continuation == nil { await Task.yield() }
        chat.openConversation(firstID)
        generator.continuation?.resume()
        await task.value
        #expect(chat.currentID == firstID)
        #expect(chat.messages.first?.content == "Primeira conversa")
        #expect(try store.conversations(for: "/a.md").first { $0.id == secondID }?.messages.last?.status == .interrupted)
        chat.deleteConversation(secondID)
        #expect(chat.currentID == firstID)
        #expect(chat.messages.count == 2)
        #expect(chat.conversations.count == 1)
    }

    @Test func unfinishedPersistedResponsesRecoverAsInterrupted() throws {
        let store = try AnnotationStore(url: nil)
        try store.saveConversation(ChatConversation(id: "interrupted", anchor: anchor, messages: [
            .init(role: .user, content: "Pergunta"), .init(role: .assistant, content: "Parcial", status: .streaming)
        ]), for: "/a.md")
        let chat = PassageChat(generator: TestChatGenerator(), store: store, docPath: "/a.md")
        chat.openConversation("interrupted")
        #expect(chat.messages.last?.status == .interrupted)
        #expect(chat.messages.last?.content == "Parcial")
        #expect(chat.completedTurns.isEmpty)
        #expect(!chat.isResponding)
    }

    @Test func switchingPassageCancelsAndRejectsLateOutput() async throws {
        let generator = TestChatGenerator()
        generator.paused = true
        let chat = PassageChat(generator: generator)
        chat.start(anchor: anchor)
        chat.draft = "Explique."
        let task = try #require(chat.send())
        while generator.continuation == nil { await Task.yield() }
        #expect(chat.isResponding)
        #expect(chat.send() == nil, "Only one request per conversation")
        let next = TextAnchor(start: 10, end: 15, quote: "Outro", prefix: "", suffix: "")
        chat.start(anchor: next)
        generator.callback?("Resposta atrasada")
        generator.continuation?.resume()
        await task.value
        #expect(chat.anchor == next)
        #expect(chat.messages.isEmpty)
        #expect(!chat.isResponding)
    }

    @Test func failuresAndCancellationDoNotEnterFutureContext() async throws {
        let generator = TestChatGenerator()
        generator.failure = ChatError(message: "Falha de teste")
        let chat = PassageChat(generator: generator)
        chat.start(anchor: anchor)
        chat.draft = "Primeira pergunta"
        await chat.send()?.value
        #expect(chat.messages.last?.status == .failed)
        #expect(chat.error == "Falha de teste")
        #expect(chat.draft == "Primeira pergunta")
        #expect(chat.completedTurns.isEmpty)
        generator.failure = nil
        generator.paused = true
        let task = try #require(chat.send())
        while generator.continuation == nil { await Task.yield() }
        chat.cancel()
        generator.callback?("Não deve substituir a resposta parcial")
        generator.continuation?.resume()
        await task.value
        #expect(chat.messages.last?.status == .interrupted)
        #expect(chat.messages.last?.content == "Uma resposta")
        #expect(chat.completedTurns.isEmpty)
        generator.paused = false
        chat.draft = "Tentar de novo"
        await chat.send()?.value
        #expect(generator.histories.last?.isEmpty == true)
        #expect(chat.completedTurns.count == 1)
    }

    @Test func unavailableModelPreservesDraftAndCanRecover() async throws {
        let generator = TestChatGenerator()
        generator.unavailabilityReason = "Baixando modelo"
        let chat = PassageChat(generator: generator)
        chat.start(anchor: anchor)
        chat.draft = "Minha pergunta"
        #expect(chat.send() == nil)
        #expect(chat.messages.isEmpty)
        #expect(chat.draft == "Minha pergunta")
        generator.unavailabilityReason = nil
        await chat.send()?.value
        #expect(chat.completedTurns.count == 1)
    }

    @Test func savesAIProvenanceAndOriginalPassageAfterReload() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Trecho escolhido.\n\nOutro parágrafo.".write(to: file, atomically: true, encoding: .utf8)
        let store = try AnnotationStore(url: nil)
        let document = DocumentModel(url: file, store: store, chatGenerator: TestChatGenerator())
        document.apply(RenderOptions(theme: .polar))
        document.startChat(on: document.text.range(of: "Trecho escolhido."))
        document.chat.draft = "Explique"
        await document.chat.send()?.value
        let id = try #require(document.chat.messages.last?.id)
        let updated = "Introdução.\n\nTrecho escolhido.\n\nOutro parágrafo."
        try updated.write(to: file, atomically: true, encoding: .utf8)
        document.reload()
        document.selection = document.text.range(of: "Outro parágrafo.")
        try document.saveChatResponse(id)
        try document.saveChatResponse(id)
        #expect(document.comments.count == 1)
        #expect(document.comments[0].anchor?.quote == "Trecho escolhido.")
        #expect(document.commentRanges[id] == document.text.range(of: "Trecho escolhido."))
        document.edit(id, body: "Resposta revisada")
        let reopened = DocumentModel(url: file, store: store)
        #expect(reopened.comments.first?.isAIGenerated == true)
        #expect(reopened.comments.first?.body == "Resposta revisada")
        #expect(try String(contentsOf: file, encoding: .utf8) == updated)
        document.deleteComment(id)
        try document.saveChatResponse(id)
        #expect(document.comments.count == 1)
        let conversationID = try #require(document.chat.currentID)
        document.chat.deleteConversation(conversationID)
        #expect(document.comments.count == 1, "Deleting a chat must keep the explicitly saved annotation")
        #expect(try store.conversations(for: document.key).isEmpty)
    }

    @Test func deletedPassageSavesAsOrphanAndMissingStoreReportsFailure() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Trecho escolhido.".write(to: file, atomically: true, encoding: .utf8)
        let document = DocumentModel(url: file, store: try AnnotationStore(url: nil), chatGenerator: TestChatGenerator())
        document.apply(RenderOptions(theme: .polar))
        document.startChat(on: document.text.range(of: "Trecho escolhido."))
        document.chat.draft = "Explique"
        await document.chat.send()?.value
        let id = try #require(document.chat.messages.last?.id)
        try "Conteúdo inteiramente diferente.".write(to: file, atomically: true, encoding: .utf8)
        document.reload()
        try document.saveChatResponse(id)
        #expect(document.orphanComments.first?.id == id)
        let unsaved = DocumentModel(url: file, store: nil, chatGenerator: TestChatGenerator())
        unsaved.apply(RenderOptions(theme: .polar))
        unsaved.startChat(on: unsaved.text.range(of: "Conteúdo"))
        unsaved.chat.draft = "Explique"
        await unsaved.chat.send()?.value
        let unsavedID = try #require(unsaved.chat.messages.last?.id)
        #expect(throws: ChatError.self) { try unsaved.saveChatResponse(unsavedID) }
        #expect(unsaved.comments.isEmpty)
    }

    @Test func pdfChatPreservesDisjointFragmentsAndSavesWithoutWritingPDF() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try PDFTests.writePDF(["primeiro omitido último", "Outra página final"], to: file)
        let original = try Data(contentsOf: file)
        let store = try AnnotationStore(url: nil)
        let document = DocumentModel(url: file, store: store, chatGenerator: TestChatGenerator())
        document.apply(RenderOptions(theme: .polar))
        let pdf = try #require(document.pdfDocument)
        let selection = PDFSelection(document: pdf)
        for word in ["primeiro", "último", "final"] {
            selection.add(try #require(pdf.findString(word, withOptions: []).first))
        }
        document.selectPDF(selection)
        document.startChat(on: document.selection)
        let anchor = try #require(document.chat.anchor)
        #expect(anchor.pdf?.count == 3)
        #expect(!anchor.quote.contains("omitido"))
        document.selectPDF(nil)
        document.chat.draft = "Explique."
        await document.chat.send()?.value
        try document.saveChatResponse(try #require(document.chat.messages.last?.id))
        #expect(try store.comments(for: document.key).first?.anchor == anchor)
        #expect(try store.comments(for: document.key).first?.isAIGenerated == true)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func contextTrimsWholeTurnsAndAlwaysKeepsPassage() async throws {
        let history = [ChatTurn(question: "Pergunta antiga", answer: "Antiga"), ChatTurn(question: "Pergunta recente", answer: "Recente")]
        var counts = 0
        let context = try await ApplePassageChat.prepareContext(passage: "Trecho fixo", history: history, question: "Continuação", base: [], limit: 4096) { entries in
            counts += 1
            return entries.count > 3 ? 4000 : 500
        }
        #expect(counts == 2)
        #expect(context.trimmed)
        #expect(context.entries.count == 2)
        guard case .prompt(let first) = context.entries[0], case .text(let text) = first.segments[0] else {
            Issue.record("Missing reference passage in trimmed transcript"); return
        }
        #expect(text.content.contains("Trecho fixo"))
        #expect(text.content.contains("Pergunta recente"))
        #expect(!text.content.contains("Pergunta antiga"))
        #expect(context.prompt == "Continuação")
        await #expect(throws: ChatError.self) {
            try await ApplePassageChat.prepareContext(passage: "Muito grande", history: [], question: "Pergunta", base: [], limit: 4096) { _ in 4000 }
        }
    }

    @Test func selectingPassageRevealsChatAndCommentActionsRestoreCommentsTab() throws {
        let suite = "dev.rheav.jullia.chat-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "Uma leitura interessante.".write(to: file, atomically: true, encoding: .utf8)
        let app = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)
        app.openFile(file)
        let document = try #require(app.document)
        document.selection = document.text.range(of: "leitura")
        app.commentsCollapsed = true
        app.chatSelection()
        #expect(app.inspectorTab == .chat)
        #expect(!app.commentsCollapsed)
        #expect(document.chat.anchor?.quote == "leitura")
        app.commentSelection()
        #expect(app.inspectorTab == .comments)

        _ = NSApplication.shared
        let textView = MarkTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        textView.textStorage?.setAttributedString(document.rendered)
        let coordinator = DocumentTextView.Coordinator()
        coordinator.parent = DocumentTextView(document: document, rendered: document.rendered, renderToken: document.renderToken,
                                              decorations: [], scrollRequest: nil, findRequest: nil, theme: .polar, readingWidth: 600)
        coordinator.textView = textView
        textView.coordinator = coordinator
        let range = document.text.range(of: "interessante")
        textView.showPill(for: range, mode: .selection)
        let pill = try #require(textView.subviews.compactMap { $0 as? NSHostingView<SelectionPill> }.first)
        pill.rootView.onChat()
        #expect(document.chat.anchor?.quote == "interessante")
        #expect(app.inspectorTab == .chat)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JULLIA_CHAT_SCREENSHOTS"] != nil))
    func renderChatSidebar() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["JULLIA_CHAT_SCREENSHOTS"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "dev.rheav.jullia.chat-screenshot.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.commentsGlass.enabled = false
        let app = AppModel(defaults: defaults, settings: settings, storeURL: nil)
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        let source = "Boas ideias merecem um lugar para continuar a conversa."
        try source.write(to: file, atomically: true, encoding: .utf8)
        let generator = TestChatGenerator()
        let document = DocumentModel(url: file, store: try AnnotationStore(url: nil), chatGenerator: generator)
        document.apply(RenderOptions(theme: .polar))
        document.startChat(on: document.text.range(of: source))
        document.chat.draft = "Qual é a ideia principal?"
        await document.chat.send()?.value
        let saved = try #require(document.chat.messages.last?.id)
        try document.saveChatResponse(saved)
        document.chat.draft = "Pode explicar de outra forma?"
        await document.chat.send()?.value
        let conversationID = try #require(document.chat.currentID)
        document.chat.clear()
        document.startChat(on: document.text.range(of: source))
        document.chat.draft = "Como posso aplicar essa ideia nas minhas anotações?"
        await document.chat.send()?.value
        _ = NSApplication.shared
        for theme in [Theme.polar, Theme.paper] {
            for (name, tab, history) in [("chat", AppModel.InspectorTab.chat, false), ("history", .chat, true), ("comments", .comments, false)] {
                if history { document.chat.clear() } else { document.chat.openConversation(conversationID) }
                app.inspectorTab = tab
                let size = CGSize(width: Layout.inspectorWidths.upperBound, height: 800)
                let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
                let view = NSHostingView(rootView: InspectorSidebar(document: document, theme: theme)
                    .background(theme.background.color).environment(app).environment(settings))
                window.contentView = view
                view.frame = CGRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(300))
                view.layoutSubtreeIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appending(path: "\(theme.id.rawValue)-\(name).png"))
                window.close()
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JULLIA_TEST_APPLE_INTELLIGENCE"] == "1"))
    func nativeModelSmoke() async throws {
        let generator = ApplePassageChat()
        if let reason = generator.unavailabilityReason {
            print("APPLE_INTELLIGENCE_UNAVAILABLE: \(reason)")
            return
        }
        var answer = ""
        try await generator.respond(passage: "A reunião será em Lisboa, na terça-feira, às 10h.", history: [], question: "Em qual cidade será a reunião?") {
            answer = $0
        } onHistoryTrimmed: {}
        print("APPLE_INTELLIGENCE_RESPONSE: \(answer)")
        #expect(answer.localizedCaseInsensitiveContains("Lisboa"))
        let first = ChatTurn(question: "Em qual cidade será a reunião?", answer: answer)
        try await generator.respond(passage: "A reunião será em Lisboa, na terça-feira, às 10h.", history: [first], question: "E a que horas?") {
            answer = $0
        } onHistoryTrimmed: {}
        print("APPLE_INTELLIGENCE_FOLLOWUP: \(answer)")
        #expect(answer.contains("10"))
    }
}
