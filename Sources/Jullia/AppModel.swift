import AppKit
import JulliaCore
import Observation
import UniformTypeIdentifiers

/// The window's state: the folders in the sidebar, recent files, the open document and annotation counts.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let settings: AppSettings
    @ObservationIgnored let store: AnnotationStore?
    private(set) var storeError: String?

    private(set) var roots: [FileNode] = []
    private(set) var recents: [URL] = []
    private(set) var document: DocumentModel?
    /// Annotations per document key, for the badges in the file sidebar.
    private(set) var counts: [String: Int] = [:]

    /// A folded panel shrinks to a rail of icons.
    var filesCollapsed: Bool { didSet { defaults.set(filesCollapsed, forKey: "filesCollapsed") } }
    var commentsCollapsed: Bool {
        didSet {
            defaults.set(commentsCollapsed, forKey: "commentsCollapsed")
            if !commentsCollapsed { commentsPeek = nil }
        }
    }
    /// The comments panel floated out of its folded rail: on hover, or held open until dismissed.
    var commentsPeek: Peek?
    enum InspectorTab: String, CaseIterable { case comments = "Comentários", chat = "Chat com IA" }
    var inspectorTab: InspectorTab = .comments
    var fileQuery = ""
    let browser: FileBrowser
    /// The folder the browser shows when it is not under any root: scanned on its own, a few levels deep.
    private(set) var looseTree: FileNode?

    enum Peek { case hover, pinned }

    @ObservationIgnored private var folderWatchers: [URL: FolderWatcher] = [:]
    @ObservationIgnored private var looseWatcher: FolderWatcher?
    @ObservationIgnored private let defaults: UserDefaults
    static let maxRecents = 8
    /// How deep a folder outside the roots is scanned: enough for a course folder, not a whole home folder.
    static let looseDepth = 4

    init(
        defaults: UserDefaults = .standard,
        settings: AppSettings = .shared,
        storeURL: URL? = AnnotationStore.defaultURL
    ) {
        self.defaults = defaults
        self.settings = settings
        filesCollapsed = defaults.bool(forKey: "filesCollapsed")
        commentsCollapsed = defaults.bool(forKey: "commentsCollapsed")
        browser = FileBrowser(defaults: defaults)
        do {
            store = try AnnotationStore(url: storeURL)
        } catch {
            store = nil
            storeError = "As anotações não serão salvas: \(error)"
        }
        refreshCounts()
        recents = (defaults.stringArray(forKey: "recents") ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if settings.reopenFolders {
            for path in defaults.stringArray(forKey: "folders") ?? [] {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                if FileManager.default.fileExists(atPath: url.path) { addFolder(url, persist: false) }
            }
            if let last = defaults.string(forKey: "lastFile"), FileManager.default.fileExists(atPath: last) {
                openFile(URL(fileURLWithPath: last))
            }
        }
        browser.onFolderChange = { [weak self] in self?.syncLooseFolder() }
        if browser.folder == nil { browser.show(roots.first?.url) }
        syncLooseFolder()
    }

    var renderOptions: RenderOptions {
        RenderOptions(theme: settings.theme, fontSize: settings.fontSize, baseURL: document?.url.deletingLastPathComponent())
    }

    // MARK: Opening

    /// Opens whatever was handed over: a folder goes to the sidebar, a Markdown or PDF file opens.
    func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            addFolder(url)
        } else {
            openFile(url)
        }
    }

    func openFile(_ url: URL) {
        guard document?.url != url else { return }
        document?.chat.cancel()
        let document = DocumentModel(url: url, store: store)
        document.onAnnotationsChanged = { [weak self] in self?.refreshCounts() }
        document.onChatStarted = { [weak self] in self?.revealChat() }
        document.watch { [weak self] in self?.settings.liveReload ?? false }
        self.document = document
        document.apply(renderOptions)
        browser.reveal(url)

        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        defaults.set(recents.map(\.path), forKey: "recents")
        defaults.set(url.path, forKey: "lastFile")
    }

    /// Re-renders the open document after a theme or font change.
    func rerender() {
        document?.apply(renderOptions)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText, .pdf, .folder]
        panel.message = "Escolha arquivos Markdown, PDF ou pastas"
        if panel.runModal() == .OK { panel.urls.forEach(open) }
    }

    func presentFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Abrir pasta"
        if panel.runModal() == .OK { panel.urls.forEach { addFolder($0) } }
    }

    // MARK: Folders

    /// Adds a folder to the sidebar's roots. Added by hand, it is also shown.
    func addFolder(_ url: URL, persist: Bool = true) {
        let url = url.standardizedFileURL
        guard !roots.contains(where: { $0.url == url }) else {
            if persist { browser.show(url) }
            return
        }
        roots.append(FileTree.scan(url))
        folderWatchers[url] = FolderWatcher(url: url) { [weak self] in self?.rescan(url) }
        if persist {
            saveFolders()
            browser.show(url)
        }
        syncLooseFolder()
    }

    func removeFolder(_ url: URL) {
        roots.removeAll { $0.url == url }
        folderWatchers[url] = nil
        saveFolders()
        if let folder = browser.folder, FileTree.isWithin(folder, url) {
            browser.show(document?.url.deletingLastPathComponent() ?? roots.first?.url)
        }
        syncLooseFolder()
    }

    func rescan(_ url: URL) {
        guard let index = roots.firstIndex(where: { $0.url == url }) else { return }
        let fresh = FileTree.scan(url)
        if fresh != roots[index] { roots[index] = fresh }
    }

    func rescanAll() {
        roots.map(\.url).forEach(rescan)
        rescanLoose()
        refreshCounts()
    }

    /// The root the folder or file sits in, the innermost one if roots are nested.
    func root(containing url: URL) -> FileNode? {
        roots.filter { FileTree.isWithin(url, $0.url) }.max { $0.url.path.count < $1.url.path.count }
    }

    /// The tree the browser shows, in the chosen order.
    var browserTree: FileNode? {
        guard let folder = browser.folder else { return nil }
        let tree = root(containing: folder).flatMap { FileTree.node(at: folder, in: $0) } ?? looseTree
        return tree.map { FileTree.sorted($0, by: browser.sort) }
    }

    /// Whether the folder shown is outside every root.
    var browsingLooseFolder: Bool { looseTree != nil }

    /// Every file the search can find: the roots, and the folder shown when it is outside them.
    var searchableTrees: [FileNode] { roots + (looseTree.map { [$0] } ?? []) }

    /// Scans the folder shown when no root has it, and watches it; drops that scan when a root covers it.
    private func syncLooseFolder() {
        guard let folder = browser.folder else { return dropLoose() }
        if let root = root(containing: folder), FileTree.node(at: folder, in: root) != nil { return dropLoose() }
        guard FileManager.default.fileExists(atPath: folder.path) else {
            dropLoose()
            if let first = roots.first?.url, first != folder { browser.show(first) }
            return
        }
        if looseTree?.url.standardizedFileURL != folder {
            looseTree = FileTree.scan(folder, maxDepth: Self.looseDepth)
            looseWatcher = FolderWatcher(url: folder) { [weak self] in self?.rescanLoose() }
        }
    }

    private func rescanLoose() {
        guard let url = looseTree?.url else { return }
        let fresh = FileTree.scan(url, maxDepth: Self.looseDepth)
        if fresh != looseTree { looseTree = fresh }
    }

    private func dropLoose() {
        looseTree = nil
        looseWatcher = nil
    }

    private func saveFolders() {
        defaults.set(roots.map(\.url.path), forKey: "folders")
    }

    // MARK: Annotations

    func refreshCounts() {
        counts = (try? store?.annotationCounts()) ?? [:]
    }

    func count(for url: URL) -> Int {
        counts[documentKey(for: url)] ?? 0
    }

    func highlightSelection(color: MarkColor? = nil) {
        guard let document, document.selection.length > 0 else { return NSSound.beep() }
        let color = color ?? settings.lastColor
        settings.lastColor = color
        document.highlight(document.selection, color: color)
    }

    func commentSelection() {
        guard let document else { return }
        document.startComment(on: document.selection.length > 0 ? document.selection : nil)
        revealComments()
    }

    func commentWholeDocument() {
        document?.startComment(on: nil)
        revealComments()
    }

    /// Brings the comments into view: floats them out of the rail when it is folded.
    func revealComments() {
        inspectorTab = .comments
        if commentsCollapsed { commentsPeek = .pinned }
    }

    func revealChat() {
        inspectorTab = .chat
        commentsCollapsed = false
        commentsPeek = nil
    }

    func chatSelection() {
        guard let document, document.hasSelection else { return }
        document.startChat(on: document.selection)
    }

    /// A click in the text puts a floated-out panel away, unless a comment is being written in it.
    func dismissPeek() {
        guard commentsPeek != nil, document?.composing == nil else { return }
        commentsPeek = nil
    }
}
