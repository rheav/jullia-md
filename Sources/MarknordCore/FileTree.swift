import Foundation

/// A folder or Markdown file in a folder opened in the sidebar. Folders without Markdown anywhere below are left out.
public struct FileNode: Identifiable, Hashable, Sendable {
    public var url: URL
    public var name: String
    /// `nil` for files, so `OutlineGroup` shows no disclosure triangle on them.
    public var children: [FileNode]?

    public var id: URL { url }
    public var isDirectory: Bool { children != nil }

    public init(url: URL, name: String, children: [FileNode]?) {
        self.url = url
        self.name = name
        self.children = children
    }

    /// Every file below this node, depth first.
    public var files: [FileNode] {
        guard let children else { return [self] }
        return children.flatMap(\.files)
    }
}

public enum FileTree {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let skipped: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods"]
    /// Stops a runaway scan (a home folder opened by mistake) from freezing the app.
    static let maxDepth = 12

    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    public static func scan(_ root: URL) -> FileNode {
        FileNode(url: root, name: root.lastPathComponent, children: children(of: root, depth: 0))
    }

    static func children(of directory: URL, depth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                guard !skipped.contains(entry.lastPathComponent) else { continue }
                let below = children(of: entry, depth: depth + 1)
                if !below.isEmpty {
                    folders.append(FileNode(url: entry, name: entry.lastPathComponent, children: below))
                }
            } else if isMarkdown(entry) {
                files.append(FileNode(url: entry, name: entry.lastPathComponent, children: nil))
            }
        }
        let order: (FileNode, FileNode) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders.sorted(by: order) + files.sorted(by: order)
    }

    /// The tree cut down to files whose name contains `query` (case and accent insensitive), keeping their folders.
    public static func filter(_ node: FileNode, query: String) -> FileNode? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return node }
        guard let children = node.children else {
            return node.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil ? node : nil
        }
        let kept = children.compactMap { filter($0, query: query) }
        return kept.isEmpty ? nil : FileNode(url: node.url, name: node.name, children: kept)
    }
}
