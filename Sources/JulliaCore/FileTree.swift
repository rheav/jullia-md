import Foundation

/// A folder, Markdown file or PDF in a folder opened in the sidebar. Folders without supported documents anywhere below are left out.
public struct FileNode: Identifiable, Hashable, Sendable {
    public var url: URL
    public var name: String
    /// `nil` for files, so `OutlineGroup` shows no disclosure triangle on them.
    public var children: [FileNode]?
    /// When the file or folder was last changed on disk, for sorting by date.
    public var modified: Date

    public var id: URL { url }
    public var isDirectory: Bool { children != nil }

    public init(url: URL, name: String, children: [FileNode]?, modified: Date = .distantPast) {
        self.url = url
        self.name = name
        self.children = children
        self.modified = modified
    }

    /// Every file below this node, depth first.
    public var files: [FileNode] {
        guard let children else { return [self] }
        return children.flatMap(\.files)
    }
}

/// How the sidebar orders a folder's contents. Folders always come before files.
public enum FileSort: String, CaseIterable, Sendable {
    case name
    /// Most recently changed first.
    case date
}

/// One visible line of a folder tree: a node and how deep it sits below the folder shown.
public struct FileTreeRow: Identifiable, Hashable, Sendable {
    public var node: FileNode
    public var depth: Int
    public var id: URL { node.url }
}

public enum FileTree {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    static let skipped: Set<String> = ["node_modules", ".build", "build", "dist", "DerivedData", "Pods"]
    /// Stops a runaway scan (a home folder opened by mistake) from freezing the app.
    public static let maxDepth = 12

    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isSupported(_ url: URL) -> Bool {
        isMarkdown(url) || url.pathExtension.lowercased() == "pdf"
    }

    public static func scan(_ root: URL, maxDepth: Int = maxDepth) -> FileNode {
        let modified = (try? root.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return FileNode(url: root, name: root.lastPathComponent, children: children(of: root, depth: 0, maxDepth: maxDepth),
                        modified: modified ?? .distantPast)
    }

    static func children(of directory: URL, depth: Int, maxDepth: Int) -> [FileNode] {
        guard depth < maxDepth else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if values?.isDirectory == true {
                guard !skipped.contains(entry.lastPathComponent) else { continue }
                let below = children(of: entry, depth: depth + 1, maxDepth: maxDepth)
                if !below.isEmpty {
                    folders.append(FileNode(url: entry, name: entry.lastPathComponent, children: below, modified: modified))
                }
            } else if isSupported(entry) {
                files.append(FileNode(url: entry, name: entry.lastPathComponent, children: nil, modified: modified))
            }
        }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }

    static func byName(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// The tree cut down to files whose name contains `query` (case and accent insensitive), keeping their folders.
    public static func filter(_ node: FileNode, query: String) -> FileNode? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return node }
        guard let children = node.children else {
            return matches(node, query) ? node : nil
        }
        let kept = children.compactMap { filter($0, query: query) }
        return kept.isEmpty ? nil : FileNode(url: node.url, name: node.name, children: kept, modified: node.modified)
    }

    /// The same tree in another order: folders first, then files, each group by name or newest first.
    public static func sorted(_ node: FileNode, by sort: FileSort) -> FileNode {
        guard let children = node.children else { return node }
        let order: (FileNode, FileNode) -> Bool = switch sort {
        case .name: byName
        case .date: { $0.modified == $1.modified ? byName($0, $1) : $0.modified > $1.modified }
        }
        let folders = children.filter(\.isDirectory).map { sorted($0, by: sort) }.sorted(by: order)
        let files = children.filter { !$0.isDirectory }.sorted(by: order)
        var copy = node
        copy.children = folders + files
        return copy
    }

    /// Whether `url` is `folder` itself or somewhere below it.
    public static func isWithin(_ url: URL, _ folder: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = folder.standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// The node for `url` inside `root`'s tree, if the scan kept it.
    public static func node(at url: URL, in root: FileNode) -> FileNode? {
        let target = url.standardizedFileURL.path
        if root.url.standardizedFileURL.path == target { return root }
        guard let children = root.children else { return nil }
        for child in children where isWithin(url, child.url) {
            return node(at: url, in: child)
        }
        return nil
    }

    /// The lines a folder shows: its children, and the children of every expanded folder below, in order.
    public static func rows(_ folder: FileNode, expanded: Set<URL>) -> [FileTreeRow] {
        var result: [FileTreeRow] = []
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                result.append(FileTreeRow(node: node, depth: depth))
                if let children = node.children, expanded.contains(node.url.standardizedFileURL) {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(folder.children ?? [], depth: 0)
        return result
    }

    /// Files in any of `roots` whose name contains `query` (case and accent insensitive), by name, at most `limit`.
    public static func search(_ roots: [FileNode], query: String, limit: Int = 300) -> [FileNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var seen = Set<URL>()
        let found = roots.flatMap(\.files).filter { matches($0, query) && seen.insert($0.url.standardizedFileURL).inserted }
        return Array(found.sorted(by: byName).prefix(limit))
    }

    static func matches(_ node: FileNode, _ query: String) -> Bool {
        node.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
