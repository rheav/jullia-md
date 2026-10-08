import Foundation
import SQLite3

public struct StoreError: Error, CustomStringConvertible {
    public var description: String
}

/// Highlights and comments, in one SQLite file. The Markdown files themselves are never written.
public final class AnnotationStore {
    private var db: OpaquePointer?

    public static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Jullia", directoryHint: .isDirectory).appending(path: "annotations.sqlite")
    }

    /// Opens (creating if needed) the store at `url`; `nil` opens a throwaway in-memory store.
    public init(url: URL?) throws {
        let path: String
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            path = url.path
        } else {
            path = ":memory:"
        }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError(description: "Não foi possível abrir \(path)")
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try migrate()
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: Highlights

    public func highlights(for docPath: String) throws -> [Highlight] {
        try query(
            "SELECT id, start, \"end\", quote, prefix, suffix, color, created_at FROM highlights WHERE doc_path = ? ORDER BY start",
            [.text(docPath)]
        ) { row in
            Highlight(
                id: row.text(0)!, docPath: docPath,
                anchor: TextAnchor(start: row.int(1)!, end: row.int(2)!, quote: row.text(3)!, prefix: row.text(4)!, suffix: row.text(5)!),
                color: MarkColor(rawValue: row.text(6)!) ?? .yellow,
                createdAt: row.date(7)!
            )
        }
    }

    public func insert(_ highlight: Highlight) throws {
        let a = highlight.anchor
        try run(
            "INSERT INTO highlights (id, doc_path, start, \"end\", quote, prefix, suffix, color, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
            [.text(highlight.id), .text(highlight.docPath), .int(a.start), .int(a.end), .text(a.quote), .text(a.prefix),
             .text(a.suffix), .text(highlight.color.rawValue), .date(highlight.createdAt)]
        )
    }

    public func setColor(_ color: MarkColor, ofHighlight id: String) throws {
        try run("UPDATE highlights SET color = ? WHERE id = ?", [.text(color.rawValue), .text(id)])
    }

    public func setAnchor(_ anchor: TextAnchor, ofHighlight id: String) throws {
        try run("UPDATE highlights SET start = ?, \"end\" = ? WHERE id = ?", [.int(anchor.start), .int(anchor.end), .text(id)])
    }

    public func deleteHighlight(_ id: String) throws {
        try run("DELETE FROM highlights WHERE id = ?", [.text(id)])
    }

    // MARK: Comments

    /// Every comment and answer on a document, oldest first.
    public func comments(for docPath: String) throws -> [Comment] {
        try query(
            """
            SELECT id, parent_id, start, "end", quote, prefix, suffix, body, color, resolved_at, created_at, updated_at
            FROM comments WHERE doc_path = ? ORDER BY created_at, rowid
            """,
            [.text(docPath)]
        ) { row in
            var anchor: TextAnchor?
            if let start = row.int(2), let end = row.int(3) {
                anchor = TextAnchor(start: start, end: end, quote: row.text(4) ?? "", prefix: row.text(5) ?? "", suffix: row.text(6) ?? "")
            }
            return Comment(
                id: row.text(0)!, docPath: docPath, parentID: row.text(1), anchor: anchor, body: row.text(7)!,
                color: row.text(8).flatMap(MarkColor.init(rawValue:)), resolvedAt: row.date(9),
                createdAt: row.date(10)!, updatedAt: row.date(11)!
            )
        }
    }

    public func insert(_ comment: Comment) throws {
        let a = comment.anchor
        try run(
            """
            INSERT INTO comments (id, doc_path, parent_id, start, "end", quote, prefix, suffix, body, color, resolved_at, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            [.text(comment.id), .text(comment.docPath), .optionalText(comment.parentID),
             a.map { .int($0.start) } ?? .null, a.map { .int($0.end) } ?? .null,
             .optionalText(a?.quote), .optionalText(a?.prefix), .optionalText(a?.suffix),
             .text(comment.body), .optionalText(comment.color?.rawValue), comment.resolvedAt.map { .date($0) } ?? .null,
             .date(comment.createdAt), .date(comment.updatedAt)]
        )
    }

    public func setBody(_ body: String, ofComment id: String) throws {
        try run("UPDATE comments SET body = ?, updated_at = ? WHERE id = ?", [.text(body), .date(.now), .text(id)])
    }

    public func setResolved(_ resolvedAt: Date?, ofComment id: String) throws {
        try run("UPDATE comments SET resolved_at = ?, updated_at = ? WHERE id = ?",
                [resolvedAt.map { .date($0) } ?? .null, .date(.now), .text(id)])
    }

    public func setColor(_ color: MarkColor?, ofComment id: String) throws {
        try run("UPDATE comments SET color = ? WHERE id = ?", [.optionalText(color?.rawValue), .text(id)])
    }

    public func setAnchor(_ anchor: TextAnchor, ofComment id: String) throws {
        try run("UPDATE comments SET start = ?, \"end\" = ? WHERE id = ?", [.int(anchor.start), .int(anchor.end), .text(id)])
    }

    /// Deletes a comment and, with it, its answers.
    public func deleteComment(_ id: String) throws {
        try run("DELETE FROM comments WHERE id = ?", [.text(id)])
    }

    // MARK: Counts

    /// Highlights plus open top-level comments, per document — the number the file sidebar shows.
    public func annotationCounts() throws -> [String: Int] {
        let rows = try query(
            """
            SELECT doc_path, COUNT(*) FROM (
              SELECT doc_path FROM highlights
              UNION ALL
              SELECT doc_path FROM comments WHERE parent_id IS NULL AND resolved_at IS NULL
            ) GROUP BY doc_path
            """,
            []
        ) { row in (row.text(0)!, row.int(1)!) }
        return Dictionary(uniqueKeysWithValues: rows)
    }

    // MARK: Schema

    private func migrate() throws {
        let version = try query("PRAGMA user_version", []) { $0.int(0)! }.first ?? 0
        if version < 1 {
            try execute("""
                CREATE TABLE highlights (
                  id TEXT PRIMARY KEY,
                  doc_path TEXT NOT NULL,
                  start INTEGER NOT NULL,
                  "end" INTEGER NOT NULL,
                  quote TEXT NOT NULL,
                  prefix TEXT NOT NULL,
                  suffix TEXT NOT NULL,
                  color TEXT NOT NULL,
                  created_at REAL NOT NULL
                );
                CREATE INDEX highlights_doc ON highlights(doc_path);
                CREATE TABLE comments (
                  id TEXT PRIMARY KEY,
                  doc_path TEXT NOT NULL,
                  parent_id TEXT REFERENCES comments(id) ON DELETE CASCADE,
                  start INTEGER,
                  "end" INTEGER,
                  quote TEXT,
                  prefix TEXT,
                  suffix TEXT,
                  body TEXT NOT NULL,
                  color TEXT,
                  resolved_at REAL,
                  created_at REAL NOT NULL,
                  updated_at REAL NOT NULL
                );
                CREATE INDEX comments_doc ON comments(doc_path);
                PRAGMA user_version = 1;
                """)
        }
    }

    // MARK: SQLite plumbing

    enum Value {
        case text(String), int(Int), double(Double), null

        static func date(_ date: Date) -> Value { .double(date.timeIntervalSince1970) }
        static func optionalText(_ text: String?) -> Value { text.map(Value.text) ?? .null }
    }

    struct Row {
        let statement: OpaquePointer

        func text(_ column: Int32) -> String? {
            guard sqlite3_column_type(statement, column) != SQLITE_NULL, let raw = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: raw)
        }

        func int(_ column: Int32) -> Int? {
            sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
        }

        func date(_ column: Int32) -> Date? {
            sqlite3_column_type(statement, column) == SQLITE_NULL
                ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, column))
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &message) != SQLITE_OK {
            let text = message.map { String(cString: $0) } ?? "erro desconhecido"
            sqlite3_free(message)
            throw StoreError(description: text)
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError(description: String(cString: sqlite3_errmsg(db)))
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
            case .int(let int): sqlite3_bind_int64(statement, index, Int64(int))
            case .double(let double): sqlite3_bind_double(statement, index, double)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError(description: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query<T>(_ sql: String, _ values: [Value], _ map: (Row) throws -> T) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw StoreError(description: String(cString: sqlite3_errmsg(db))) }
            results.append(try map(Row(statement: statement)))
        }
        return results
    }
}
