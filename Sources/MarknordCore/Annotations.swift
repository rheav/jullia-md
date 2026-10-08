import Foundation

public struct Highlight: Identifiable, Hashable, Sendable {
    public var id: String
    public var docPath: String
    public var anchor: TextAnchor
    public var color: MarkColor
    public var createdAt: Date

    public init(id: String = UUID().uuidString, docPath: String, anchor: TextAnchor, color: MarkColor, createdAt: Date = .now) {
        self.id = id
        self.docPath = docPath
        self.anchor = anchor
        self.color = color
        self.createdAt = createdAt
    }
}

public struct Comment: Identifiable, Hashable, Sendable {
    public var id: String
    public var docPath: String
    /// Set on answers; answers carry no anchor of their own.
    public var parentID: String?
    /// `nil` on a comment about the whole document, and on answers.
    public var anchor: TextAnchor?
    public var body: String
    /// `nil` is the usual yellow underline and quiet card.
    public var color: MarkColor?
    public var resolvedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString, docPath: String, parentID: String? = nil, anchor: TextAnchor?,
        body: String, color: MarkColor? = nil, resolvedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.docPath = docPath
        self.parentID = parentID
        self.anchor = anchor
        self.body = body
        self.color = color
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isResolved: Bool { resolvedAt != nil }
}

/// The key annotations are stored under: the file's path with symlinks resolved.
public func documentKey(for url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}
