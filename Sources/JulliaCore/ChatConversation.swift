import Foundation

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public enum Status: String, Codable, Sendable { case streaming, complete, interrupted, failed }
    public let id: String
    public var role: Role
    public var content: String
    public var status: Status

    public init(id: String = UUID().uuidString, role: Role, content: String, status: Status = .complete) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
    }
}

/// A local conversation keeps its original passage and message IDs independently of saved annotations.
public struct ChatConversation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var anchor: TextAnchor
    public var messages: [ChatMessage]
    public var contextWasTrimmed: Bool
    public var updatedAt: Date

    public init(id: String, anchor: TextAnchor, messages: [ChatMessage], contextWasTrimmed: Bool = false, updatedAt: Date = .now) {
        self.id = id
        self.anchor = anchor
        self.messages = messages
        self.contextWasTrimmed = contextWasTrimmed
        self.updatedAt = updatedAt
    }

    public var title: String {
        messages.first(where: { $0.role == .user })?.content ?? anchor.quote
    }
}
