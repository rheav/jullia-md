import Foundation
import SQLite3
import Testing
@testable import JulliaCore

@Suite struct ConversationStoreTests {
    @Test func conversationsSurviveReopeningAndDeletionIsScopedToDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "annotations.sqlite")
        var anchor = TextAnchor(start: 0, end: 6, quote: "Trecho", prefix: "", suffix: "")
        anchor.pdf = [PDFAnchorFragment(pageIndex: 2, text: anchor)]
        let response = ChatMessage(role: .assistant, content: "Uma explicação")
        let first = ChatConversation(id: "first", anchor: anchor, messages: [.init(role: .user, content: "Explique"), response], updatedAt: Date(timeIntervalSince1970: 100))
        var second = ChatConversation(id: "second", anchor: anchor, messages: [], updatedAt: Date(timeIntervalSince1970: 200))
        do {
            let store = try AnnotationStore(url: url)
            try store.saveConversation(first, for: "/a.pdf")
            try store.saveConversation(second, for: "/a.pdf")
            try store.saveConversation(ChatConversation(id: "other", anchor: anchor, messages: []), for: "/b.md")
            try store.insert(Comment(id: response.id, docPath: "/a.pdf", anchor: anchor, body: response.content, isAIGenerated: true))
        }
        let reopened = try AnnotationStore(url: url)
        #expect(try reopened.conversations(for: "/a.pdf") == [second, first])
        second.messages = [.init(role: .user, content: "Outra pergunta")]
        try reopened.saveConversation(second, for: "/a.pdf")
        #expect(try reopened.conversations(for: "/a.pdf").count == 2)
        #expect(try reopened.conversations(for: "/a.pdf")[0].messages == second.messages)
        try reopened.deleteConversation("first", for: "/b.md")
        #expect(try reopened.conversations(for: "/a.pdf").count == 2)
        try reopened.deleteConversation("first", for: "/a.pdf")
        #expect(try reopened.conversations(for: "/a.pdf").map(\.id) == ["second"])
        #expect(try reopened.conversations(for: "/b.md").map(\.id) == ["other"])
        #expect(try reopened.comments(for: "/a.pdf").first?.id == response.id)
        #expect(try reopened.annotationCounts() == ["/a.pdf": 1], "Chats are separate from annotation counts")
    }

    @Test func migrationFromVersionThreePreservesAIAnnotations() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "annotations.sqlite")
        let anchor = TextAnchor(start: 0, end: 6, quote: "Trecho", prefix: "", suffix: "")
        do {
            let store = try AnnotationStore(url: url)
            try store.insert(Comment(id: "saved", docPath: "/a.md", anchor: anchor, body: "Resposta salva", isAIGenerated: true))
        }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "DROP TABLE chat_conversations; PRAGMA user_version = 3;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let migrated = try AnnotationStore(url: url)
        #expect(try migrated.comments(for: "/a.md").first?.isAIGenerated == true)
        #expect(try migrated.conversations(for: "/a.md").isEmpty)
        try migrated.saveConversation(ChatConversation(id: "chat", anchor: anchor, messages: []), for: "/a.md")
        #expect(try migrated.conversations(for: "/a.md").first?.id == "chat")
    }
}
