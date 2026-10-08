import AppKit
import MarknordCore
import Observation
import UniformTypeIdentifiers

/// The window's state: the folders in the sidebar, recent files, the open document and annotation counts.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings.shared
    @ObservationIgnored let store: AnnotationStore?
    private(set) var storeError: String?

    private(set) var roots: [FileNode] = []
    private(set) var recents: [URL] = []
    private(set) var document: DocumentModel?
    /// Annotations per document key, for the badges in the file sidebar.
    private(set) var counts: [String: Int] = [:]

    var showFiles = true
    var showComments = true
    var fileQuery = ""

    @ObservationIgnored private var folderWatchers: [URL: FolderWatcher] = [:]
    @ObservationIgnored private let defaults = UserDefaults.standard
    static let maxRecents = 8

    private init() {
        do {
            store = try AnnotationStore(url: AnnotationStore.defaultURL)
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
    }

    var renderOptions: RenderOptions {
        RenderOptions(theme: settings.theme, fontSize: settings.fontSize, baseURL: document?.url.deletingLastPathComponent())
    }

    // MARK: Opening

    /// Opens whatever was handed over: a folder goes to the sidebar, a Markdown file opens.
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
        let document = DocumentModel(url: url, store: store)
        document.onAnnotationsChanged = { [weak self] in self?.refreshCounts() }
        document.watch { [weak self] in self?.settings.liveReload ?? false }
        self.document = document
        document.apply(renderOptions)

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
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText, .folder]
        panel.message = "Escolha arquivos Markdown ou pastas"
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

    func addFolder(_ url: URL, persist: Bool = true) {
        let url = url.standardizedFileURL
        guard !roots.contains(where: { $0.url == url }) else { return }
        roots.append(FileTree.scan(url))
        folderWatchers[url] = FolderWatcher(url: url) { [weak self] in self?.rescan(url) }
        if persist { saveFolders() }
    }

    func removeFolder(_ url: URL) {
        roots.removeAll { $0.url == url }
        folderWatchers[url] = nil
        saveFolders()
    }

    func rescan(_ url: URL) {
        guard let index = roots.firstIndex(where: { $0.url == url }) else { return }
        let fresh = FileTree.scan(url)
        if fresh != roots[index] { roots[index] = fresh }
    }

    func rescanAll() {
        roots.map(\.url).forEach(rescan)
        refreshCounts()
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
        showComments = true
    }

    func commentWholeDocument() {
        document?.startComment(on: nil)
        showComments = true
    }
}
