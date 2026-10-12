import Foundation
import Testing
import SQLite3
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
            try store.insert(Comment(docPath: "/a.md", anchor: anchor, body: "Resposta da IA", isAIGenerated: true))
        }
        let reopened = try AnnotationStore(url: url)
        #expect(try reopened.highlights(for: "/a.md").count == 1)
        #expect(try reopened.comments(for: "/a.md").first?.isAIGenerated == true)
    }

    @Test func pdfFragmentsPersistForHighlightsAndComments() throws {
        let store = try AnnotationStore(url: nil)
        var pdfAnchor = anchor
        pdfAnchor.pdf = [PDFAnchorFragment(pageIndex: 2, text: anchor)]
        let highlight = Highlight(docPath: "/a.pdf", anchor: pdfAnchor, color: .pink)
        let comment = Comment(docPath: "/a.pdf", anchor: pdfAnchor, body: "PDF")
        try store.insert(highlight)
        try store.insert(comment)
        #expect(try store.highlights(for: "/a.pdf")[0].anchor == pdfAnchor)
        #expect(try store.comments(for: "/a.pdf")[0].anchor == pdfAnchor)
        pdfAnchor.pdf?[0].pageIndex = 4
        try store.setAnchor(pdfAnchor, ofHighlight: highlight.id)
        try store.setAnchor(pdfAnchor, ofComment: comment.id)
        #expect(try store.highlights(for: "/a.pdf")[0].anchor.pdf?.first?.pageIndex == 4)
        #expect(try store.comments(for: "/a.pdf")[0].anchor?.pdf?.first?.pageIndex == 4)
    }

    @Test(arguments: [1, 2]) func migratesOldSchemasWithoutLosingMarkdownAnnotations(version: Int) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE highlights (id TEXT PRIMARY KEY, doc_path TEXT NOT NULL, start INTEGER NOT NULL,
          "end" INTEGER NOT NULL, quote TEXT NOT NULL, prefix TEXT NOT NULL, suffix TEXT NOT NULL,
          color TEXT NOT NULL, created_at REAL NOT NULL);
        CREATE TABLE comments (id TEXT PRIMARY KEY, doc_path TEXT NOT NULL, parent_id TEXT REFERENCES comments(id) ON DELETE CASCADE,
          start INTEGER, "end" INTEGER, quote TEXT, prefix TEXT, suffix TEXT, body TEXT NOT NULL,
          color TEXT, resolved_at REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL);
        INSERT INTO highlights VALUES ('old', '/a.md', 0, 5, 'hello', '', '', 'green', 100);
        INSERT INTO comments VALUES ('thread', '/a.md', NULL, 0, 5, 'hello', '', '', 'original', NULL, NULL, 100, 100);
        PRAGMA user_version = 1;
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        if version == 2 {
            #expect(sqlite3_exec(db, "ALTER TABLE highlights ADD COLUMN pdf_anchor TEXT; ALTER TABLE comments ADD COLUMN pdf_anchor TEXT; PRAGMA user_version = 2;", nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_close(db)
        let store = try AnnotationStore(url: url)
        #expect(try store.highlights(for: "/a.md")[0].anchor.pdf == nil)
        #expect(try store.highlights(for: "/a.md")[0].anchor.quote == "hello")
        #expect(try store.comments(for: "/a.md")[0].body == "original")
        #expect(try store.comments(for: "/a.md")[0].isAIGenerated == false)
        var pdfAnchor = anchor
        pdfAnchor.pdf = [PDFAnchorFragment(pageIndex: 0, text: anchor)]
        try store.insert(Highlight(docPath: "/a.pdf", anchor: pdfAnchor, color: .blue))
        let reopened = try AnnotationStore(url: url)
        #expect(try reopened.highlights(for: "/a.pdf")[0].anchor == pdfAnchor)
        #expect(try reopened.annotationCounts() == ["/a.md": 2, "/a.pdf": 1])
    }
}
