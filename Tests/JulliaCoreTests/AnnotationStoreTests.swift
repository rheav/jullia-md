import Foundation
import Testing
@testable import JulliaCore

@Suite struct AnnotationStoreTests {
    let anchor = TextAnchor(start: 3, end: 8, quote: "hello", prefix: "ab ", suffix: " world")

    @Test func highlightsRoundTrip() throws {
        let store = try AnnotationStore(url: nil)
        let highlight = Highlight(docPath: "/a.md", anchor: anchor, color: .green)
        try store.insert(highlight)
        try store.insert(Highlight(docPath: "/b.md", anchor: anchor, color: .blue))

        let loaded = try store.highlights(for: "/a.md")
        #expect(loaded.count == 1)
        #expect(loaded[0].id == highlight.id)
        #expect(loaded[0].anchor == anchor)
        #expect(loaded[0].color == .green)

        try store.setColor(.pink, ofHighlight: highlight.id)
        try store.setAnchor(TextAnchor(start: 10, end: 15, quote: "hello", prefix: "", suffix: ""), ofHighlight: highlight.id)
        let updated = try store.highlights(for: "/a.md")[0]
        #expect(updated.color == .pink)
        #expect(updated.anchor.start == 10)
        #expect(updated.anchor.prefix == "ab ", "only offsets move; the saved context stays")

        try store.deleteHighlight(highlight.id)
        #expect(try store.highlights(for: "/a.md").isEmpty)
    }

    @Test func commentsWithAnswersAndWholeDocument() throws {
        let store = try AnnotationStore(url: nil)
        let passage = Comment(docPath: "/a.md", anchor: anchor, body: "sobre o trecho", color: .purple)
        let whole = Comment(docPath: "/a.md", anchor: nil, body: "sobre tudo")
        try store.insert(passage)
        try store.insert(whole)
        try store.insert(Comment(docPath: "/a.md", parentID: passage.id, anchor: nil, body: "resposta"))

        var loaded = try store.comments(for: "/a.md")
        #expect(loaded.count == 3)
        #expect(loaded.first { $0.id == passage.id }?.anchor == anchor)
        #expect(loaded.first { $0.id == passage.id }?.color == .purple)
        #expect(loaded.first { $0.id == whole.id }?.anchor == nil)

        try store.setBody("editado", ofComment: whole.id)
        try store.setResolved(Date(timeIntervalSince1970: 100), ofComment: whole.id)
        try store.setColor(nil, ofComment: passage.id)
        loaded = try store.comments(for: "/a.md")
        #expect(loaded.first { $0.id == whole.id }?.body == "editado")
        #expect(loaded.first { $0.id == whole.id }?.isResolved == true)
        #expect(loaded.first { $0.id == passage.id }?.color == nil)

        try store.deleteComment(passage.id)
        loaded = try store.comments(for: "/a.md")
        #expect(loaded.map(\.id) == [whole.id], "deleting a comment deletes its answers")
    }

    @Test func countsHighlightsAndOpenTopLevelComments() throws {
        let store = try AnnotationStore(url: nil)
        try store.insert(Highlight(docPath: "/a.md", anchor: anchor, color: .yellow))
        let open = Comment(docPath: "/a.md", anchor: anchor, body: "aberto")
        try store.insert(open)
        try store.insert(Comment(docPath: "/a.md", parentID: open.id, anchor: nil, body: "resposta"))
        try store.insert(Comment(docPath: "/a.md", anchor: nil, body: "resolvido", resolvedAt: .now))
        try store.insert(Comment(docPath: "/b.md", anchor: nil, body: "outro"))

        #expect(try store.annotationCounts() == ["/a.md": 2, "/b.md": 1])
    }

    @Test func persistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "jullia-\(UUID().uuidString)/a.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let store = try AnnotationStore(url: url)
            try store.insert(Highlight(docPath: "/a.md", anchor: anchor, color: .orange))
        }
        let reopened = try AnnotationStore(url: url)
        #expect(try reopened.highlights(for: "/a.md").count == 1)
    }
}
