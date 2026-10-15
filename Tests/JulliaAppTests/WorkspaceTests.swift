import AppKit
import Foundation
import JulliaCore
import PDFKit
import Testing
@testable import Jullia

@MainActor @Suite struct WorkspaceTests {
    private func makeFiles(_ names: [String]) throws -> (URL, [URL]) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jullia-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = try names.map { name in
            let url = folder.appending(path: name)
            try "# \(name)\n\nUm trecho para anotar.\n".write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        return (folder, urls)
    }

    private func makeModel(_ suite: String) throws -> (AppModel, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (AppModel(defaults: defaults, settings: AppSettings(defaults: defaults), storeURL: nil), defaults)
    }

    @Test func previewTabIsReplacedUntilKept() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md", "d.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = model.workspace

        model.openFile(files[0])
        model.openFile(files[1])
        #expect(workspace.tabs.map(\.name) == ["b.md"], "A second preview replaces the first")
        #expect(workspace.tabs.first?.isPreview == true)
        #expect(model.document?.url == files[1])

        model.openFile(files[1], as: .permanent)
        #expect(workspace.tabs.map(\.isPreview) == [false], "Opening it for good keeps the same tab")
        model.openFile(files[2])
        model.openFile(files[3])
        #expect(workspace.tabs.map(\.name) == ["b.md", "d.md"])

        // Annotating keeps the preview.
        let document = try #require(model.document)
        document.selection = document.text.range(of: "trecho")
        model.highlightSelection(color: .green)
        #expect(workspace.tabs.last?.isPreview == false)
        model.openFile(files[0])
        #expect(workspace.tabs.map(\.name) == ["b.md", "d.md", "a.md"])

        // Moving through the document keeps it too.
        model.openFile(files[2])
        #expect(workspace.tabs.map(\.name) == ["b.md", "d.md", "c.md"], "a.md was still a preview")
        model.document?.onNavigated()
        #expect(workspace.tabs.last?.isPreview == false)

        // An open file is not opened twice: its tab is selected.
        model.openFile(files[1])
        #expect(workspace.tabs.count == 3)
        #expect(model.document?.url == files[1])
        #expect(model.isOpen(files[3]))
    }

    @Test func newTabsGoAfterTheFocusedOneAndClosingPicksANeighbour() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md", "d.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = model.workspace
        for file in files.prefix(3) { model.openFile(file, as: .newTab) }
        workspace.selectTab(at: 0)
        model.openFile(files[3], as: .newTab)
        #expect(workspace.tabs.map(\.name) == ["a.md", "d.md", "b.md", "c.md"])

        model.closeFocusedTab()
        #expect(workspace.tabs.map(\.name) == ["a.md", "b.md", "c.md"])
        #expect(model.document?.url == files[1], "The tab to the right takes its place")
        workspace.selectTab(at: 2)
        model.closeFocusedTab()
        #expect(model.document?.url == files[1], "The last tab falls back to its left neighbour")
        workspace.selectAdjacentTab(1)
        #expect(model.document?.url == files[0], "Wraps around")
        workspace.closeOthers(than: try #require(workspace.focusedTab))
        #expect(workspace.tabs.map(\.name) == ["a.md"])
        model.closeFocusedTab()
        #expect(workspace.tabs.isEmpty)
        #expect(model.document == nil)
    }

    @Test func sessionRestoresTabsLazilyAndMigratesTheLastFile() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        model.openFile(files[0], as: .permanent)
        model.openFile(files[1], as: .permanent)
        model.openFile(files[2])
        model.workspace.selectTab(at: 1)
        model.prepareToQuit()

        try FileManager.default.removeItem(at: files[2])
        let (reopened, _) = try makeModel(suite)
        #expect(reopened.workspace.tabs.map(\.name) == ["a.md", "b.md"], "Files that are gone are left out")
        #expect(reopened.document?.url.lastPathComponent == "b.md")
        #expect(reopened.workspace.tabs.first?.document == nil, "Tabs not on screen load when shown")
        reopened.workspace.selectTab(at: 0)
        #expect(reopened.document?.url.lastPathComponent == "a.md")

        let legacySuite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let legacy = try #require(UserDefaults(suiteName: legacySuite))
        defer { legacy.removePersistentDomain(forName: legacySuite) }
        legacy.set(files[0].path, forKey: "lastFile")
        let migrated = AppModel(defaults: legacy, settings: AppSettings(defaults: legacy), storeURL: nil)
        #expect(migrated.workspace.tabs.map(\.name) == ["a.md"])
        #expect(migrated.workspace.tabs.first?.isPreview == false)
    }

    @Test func pdfViewSavesItsPlaceAndAPageChangeKeepsThePreview() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try PDFTests.writePDF(["Um", "Dois", "Três", "Quatro"], to: file)
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (app, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        app.openFile(file)
        let model = try #require(app.document)
        let tab = try #require(app.workspace.focusedTab)
        _ = NSApplication.shared

        let first = AnnotatedPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        first.displayMode = .singlePageContinuous
        first.installObservers()
        first.update(model: model, theme: .polar, appModel: app)
        first.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #expect(tab.isPreview, "Opening on the first page does not keep the tab")
        first.go(to: try #require(model.pdfDocument?.page(at: 2)))
        try await Task.sleep(for: .milliseconds(50))
        #expect(!tab.isPreview, "Going to another page keeps it")
        first.tearDown()
        #expect(model.pdfPosition?.page == 2)

        let second = AnnotatedPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        second.displayMode = .singlePageContinuous
        second.installObservers()
        defer { second.tearDown() }
        second.update(model: model, theme: .polar, appModel: app)
        second.layout()
        #expect(second.currentPage.flatMap { model.pdfDocument?.index(for: $0) } == 2, "Shown again, it is back on the same page")
    }
}
