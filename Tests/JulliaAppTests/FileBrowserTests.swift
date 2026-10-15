import Foundation
import JulliaCore
import Testing
@testable import Jullia

@MainActor @Suite struct FileBrowserTests {
    /// A temporary folder with `Downloads/Curso/Aula.pdf`, `Downloads/solto.md` and `Fora/nota.md`.
    private func makeFolders() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appending(path: "jullia-browser-\(UUID().uuidString)")
        for file in ["Downloads/Curso/Aula.pdf", "Downloads/Curso/Extra/Leitura.md", "Downloads/solto.md", "Fora/nota.md"] {
            let url = base.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# x".write(to: url, atomically: true, encoding: .utf8)
        }
        return base
    }

    private func makeModel() throws -> (AppModel, UserDefaults, String) {
        let suite = "dev.rheav.jullia.browser-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil), defaults, suite)
    }

    @Test func followsTheFocusedDocumentAndClimbsNoHigherThanItsRoot() throws {
        let base = try makeFolders()
        defer { try? FileManager.default.removeItem(at: base) }
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let downloads = base.appending(path: "Downloads").standardizedFileURL
        model.addFolder(downloads)
        #expect(model.browser.folder == downloads, "A folder added by hand is shown")
        #expect(model.browserTree?.children?.map(\.name) == ["Curso", "solto.md"])

        // Inside the folder shown: the path to the file opens, the folder stays.
        model.openFile(downloads.appending(path: "Curso/Extra/Leitura.md"))
        #expect(model.browser.folder == downloads)
        #expect(model.browser.isExpanded(downloads.appending(path: "Curso")))
        #expect(model.browser.isExpanded(downloads.appending(path: "Curso/Extra")))
        let rows = FileTree.rows(try #require(model.browserTree), expanded: model.browser.expanded).map(\.node.name)
        #expect(rows == ["Curso", "Extra", "Leitura.md", "Aula.pdf", "solto.md"])

        // Entering a folder makes it the top; the trail climbs back only as far as the root.
        model.browser.show(downloads.appending(path: "Curso/Extra"))
        #expect(model.browser.trail(from: downloads).map(\.lastPathComponent) == ["Downloads", "Curso", "Extra"])
        #expect(model.browserTree?.children?.map(\.name) == ["Leitura.md"])

        // Outside the folder shown: its own folder is shown.
        model.openFile(downloads.appending(path: "solto.md"))
        #expect(model.browser.folder == downloads)
        #expect(!model.browsingLooseFolder)
    }

    @Test func aFileOutsideTheRootsShowsItsFolderAndCanJoinThem() throws {
        let base = try makeFolders()
        defer { try? FileManager.default.removeItem(at: base) }
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        model.addFolder(base.appending(path: "Downloads"))
        let fora = base.appending(path: "Fora").standardizedFileURL
        model.openFile(fora.appending(path: "nota.md"))
        #expect(model.browser.folder == fora)
        #expect(model.browsingLooseFolder)
        #expect(model.browserTree?.children?.map(\.name) == ["nota.md"])
        #expect(model.browser.trail(from: nil) == [fora])
        #expect(FileTree.search(model.searchableTrees, query: "nota").count == 1, "The loose folder is searched too")

        model.addFolder(fora)
        #expect(!model.browsingLooseFolder)
        #expect(model.roots.map(\.url).contains(fora))
        #expect(model.browserTree?.children?.map(\.name) == ["nota.md"])

        model.removeFolder(fora)
        #expect(model.browser.folder == fora, "The open document's folder stays shown, scanned on its own")
        #expect(model.browsingLooseFolder)
    }

    @Test func recentsModeSortAndPersistence() throws {
        let base = try makeFolders()
        defer { try? FileManager.default.removeItem(at: base) }
        let (model, defaults, suite) = try makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }
        let downloads = base.appending(path: "Downloads").standardizedFileURL
        model.addFolder(downloads)
        model.browser.showRecents()
        #expect(model.browser.mode == .recents)
        model.browser.show(model.browser.folder)
        #expect(model.browser.mode == .folder)
        #expect(model.browser.folder == downloads)
        model.browser.sort = .date
        let reopened = AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil)
        #expect(reopened.browser.sort == .date)
        #expect(reopened.browser.folder == downloads, "With no document, the first root is shown")
    }
}
