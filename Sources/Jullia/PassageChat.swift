import Foundation
import JulliaCore
import Observation

struct ChatTurn: Equatable, Sendable {
    var question: String
    var answer: String
}

/// The single native model boundary; injectable so lifecycle tests don't require Apple Intelligence.
@MainActor
protocol PassageChatGenerating {
    var unavailabilityReason: String? { get }
    func respond(passage: String, history: [ChatTurn], question: String,
                 onUpdate: @escaping @MainActor (String) -> Void,
                 onHistoryTrimmed: @escaping @MainActor () -> Void) async throws
}

struct ChatError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Saved conversations are independent of the answers explicitly saved as annotations.
@MainActor @Observable
final class PassageChat {
    private(set) var anchor: TextAnchor?
    private(set) var currentID: String?
    private(set) var conversations: [ChatConversation] = []
    private(set) var persistenceError: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    private(set) var contextWasTrimmed = false
    private(set) var unavailableReason: String?
    var error: String?
    var draft = ""
    @ObservationIgnored private let generator: any PassageChatGenerating
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private let store: AnnotationStore?
    @ObservationIgnored private let docPath: String
    @ObservationIgnored private var lastCheckpoint = ContinuousClock.now

    init(generator: any PassageChatGenerating = ApplePassageChat(), store: AnnotationStore? = nil, docPath: String = "") {
        self.generator = generator
        self.store = store
        self.docPath = docPath
        do {
            conversations = try store?.conversations(for: docPath) ?? []
            // A process may have quit while a response was streaming. It cannot resume that request.
            for index in conversations.indices {
                for messageIndex in conversations[index].messages.indices
                    where conversations[index].messages[messageIndex].status == .streaming {
                    conversations[index].messages[messageIndex].status = .interrupted
                }
            }
        } catch {
            persistenceError = "Não foi possível carregar o histórico: \(error.localizedDescription)"
        }
    }

    deinit { task?.cancel() }

    func refreshAvailability() { unavailableReason = generator.unavailabilityReason }

    func start(anchor: TextAnchor) {
        guard self.anchor != anchor else { return }
        cancel()
        currentID = UUID().uuidString
        self.anchor = anchor
        messages = []
        draft = ""
        error = nil
        contextWasTrimmed = false
        refreshAvailability()
    }

    func clear() {
        cancel()
        resetCurrentConversation()
    }

    private func resetCurrentConversation() {
        currentID = nil
        anchor = nil
        messages = []
        draft = ""
        error = nil
        contextWasTrimmed = false
    }

    func openConversation(_ id: String) {
        guard currentID != id else { return }
        cancel()
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        currentID = conversation.id
        anchor = conversation.anchor
        messages = conversation.messages
        contextWasTrimmed = conversation.contextWasTrimmed
        draft = ""
        error = nil
        refreshAvailability()
    }

    func deleteConversation(_ id: String) {
        do {
            try store?.deleteConversation(id, for: docPath)
            if currentID == id {
                cancel(persist: false)
                resetCurrentConversation()
            }
            conversations.removeAll { $0.id == id }
            persistenceError = nil
        } catch {
            persistenceError = "Não foi possível excluir a conversa: \(error.localizedDescription)"
        }
    }

    private func saveCurrentConversation() {
        guard let currentID, let anchor, !messages.isEmpty else { return }
        let conversation = ChatConversation(id: currentID, anchor: anchor, messages: messages, contextWasTrimmed: contextWasTrimmed)
        conversations.removeAll { $0.id == currentID }
        conversations.insert(conversation, at: 0)
        do {
            guard let store else { throw ChatError(message: "O banco local está indisponível.") }
            try store.saveConversation(conversation, for: docPath)
            persistenceError = nil
        } catch {
            persistenceError = "Esta conversa ainda não foi salva no histórico. \(error.localizedDescription)"
        }
        lastCheckpoint = .now
    }

    /// Only complete question/answer pairs may become context for a later turn.
    var completedTurns: [ChatTurn] {
        var result: [ChatTurn] = []
        for index in messages.indices where messages[index].role == .assistant && messages[index].status == .complete {
            guard index > 0, messages[index - 1].role == .user else { continue }
            result.append(ChatTurn(question: messages[index - 1].content, answer: messages[index].content))
        }
        return result
    }

    @discardableResult
    func send() -> Task<Void, Never>? {
        guard !isResponding, let anchor else { return nil }
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return nil }
        refreshAvailability()
        guard unavailableReason == nil else { return nil }
        let history = completedTurns
        let id = UUID()
        requestID = id
        error = nil
        draft = ""
        messages.append(ChatMessage(role: .user, content: question))
        let response = ChatMessage(role: .assistant, content: "", status: .streaming)
        messages.append(response)
        isResponding = true
        saveCurrentConversation()
        task = Task { [weak self, generator] in
            do {
                try await generator.respond(passage: anchor.quote, history: history, question: question) { [weak self] content in
                    guard let self, self.requestID == id,
                          let index = self.messages.firstIndex(where: { $0.id == response.id }) else { return }
                    self.messages[index].content = content
                    if self.lastCheckpoint.duration(to: .now) >= .seconds(1) { self.saveCurrentConversation() }
                } onHistoryTrimmed: { [weak self] in
                    guard self?.requestID == id else { return }
                    self?.contextWasTrimmed = true
                }
                try Task.checkCancellation()
                guard let self, self.requestID == id, let index = self.messages.firstIndex(where: { $0.id == response.id }) else { return }
                guard !self.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatError(message: "O modelo não retornou uma resposta. Tente reformular a pergunta.")
                }
                self.messages[index].status = .complete
            } catch {
                guard let self, self.requestID == id, let index = self.messages.firstIndex(where: { $0.id == response.id }) else { return }
                self.messages[index].status = error is CancellationError ? .interrupted : .failed
                self.error = error is CancellationError ? nil : ApplePassageChat.message(for: error)
                if self.draft.isEmpty { self.draft = question }
                self.refreshAvailability()
            }
            guard let self, self.requestID == id else { return }
            self.isResponding = false
            self.saveCurrentConversation()
            self.task = nil
            self.requestID = nil
        }
        return task
    }

    func cancel(persist: Bool = true) {
        task?.cancel()
        task = nil
        requestID = nil
        if let index = messages.lastIndex(where: { $0.status == .streaming }) {
            messages[index].status = .interrupted
        }
        isResponding = false
        if persist { saveCurrentConversation() }
    }
}
