import Foundation
import JulliaCore
import Observation

/// Where the file sidebar is: the folder whose tree it shows, which subfolders are open in it, and how it is ordered.
@MainActor @Observable
final class FileBrowser {
    enum Mode: Equatable {
        /// The tree of `folder`.
        case folder
        /// The recently opened files.
        case recents
    }

    /// The folder at the top of the tree. Standardized, like everything stored here.
    private(set) var folder: URL?
    private(set) var mode: Mode = .folder
    private(set) var expanded: Set<URL> = []
    var sort: FileSort { didSet { defaults.set(sort.rawValue, forKey: "fileSort") } }

    /// Told when `folder` changes, so the owner can scan a folder that is not under any of the sidebar's roots.
    @ObservationIgnored var onFolderChange: () -> Void = {}
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sort = FileSort(rawValue: defaults.string(forKey: "fileSort") ?? "") ?? .name
    }

    /// Shows the tree of `folder`.
    func show(_ folder: URL?) {
        mode = .folder
        let folder = folder?.standardizedFileURL
        guard folder != self.folder else { return }
        self.folder = folder
        onFolderChange()
    }

    func showRecents() {
        mode = .recents
    }

    func isExpanded(_ url: URL) -> Bool {
        expanded.contains(url.standardizedFileURL)
    }

    func toggle(_ url: URL) {
        let url = url.standardizedFileURL
        if expanded.contains(url) { expanded.remove(url) } else { expanded.insert(url) }
    }

    /// Follows the focused document: opens the path down to it when it is inside the folder shown, otherwise shows
    /// its own folder. A folder picked by hand stays until the next document.
    func reveal(_ file: URL) {
        let parent = file.deletingLastPathComponent().standardizedFileURL
        guard let folder, FileTree.isWithin(parent, folder) else {
            show(parent)
            return
        }
        var directory = parent
        while directory.path != folder.path, FileTree.isWithin(directory, folder) {
            expanded.insert(directory)
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// The folders from `root` down to the folder shown, for the breadcrumb. Never above `root`, so going up never
    /// scans past what the reader opened.
    func trail(from root: URL?) -> [URL] {
        guard let folder else { return [] }
        guard let root = root?.standardizedFileURL, FileTree.isWithin(folder, root) else { return [folder] }
        var trail: [URL] = []
        var directory = folder
        while FileTree.isWithin(directory, root) {
            trail.insert(directory, at: 0)
            if directory.path == root.path { break }
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }
        return trail
    }
}
