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

    @Test func layoutsFillAndDropPanesAndFocusFollowsTheTab() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md", "d.md", "e.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = model.workspace
        for file in files.prefix(4) { model.openFile(file, as: .newTab) }
        workspace.selectTab(at: 0)

        workspace.setLayout(.three)
        #expect(workspace.panes.count == 3)
        #expect(workspace.panes.map { workspace.tab($0.tabID)?.name } == ["a.md", "b.md", "c.md"], "New panes take the next hidden tabs")
        #expect(model.document?.url == files[0])

        // A tab already in a pane focuses that pane instead of moving.
        workspace.select(try #require(workspace.tab(for: files[2])))
        #expect(workspace.focusedPane == 2)
        #expect(model.document?.url == files[2])
        workspace.focus(1)
        #expect(model.document?.url == files[1])

        // A hidden tab goes into the focused pane.
        workspace.select(try #require(workspace.tab(for: files[3])))
        #expect(workspace.focusedPane == 1)
        #expect(workspace.panes.map { workspace.tab($0.tabID)?.name } == ["a.md", "d.md", "c.md"])

        // Beside: a new pane right of the focused one, up to four.
        model.openFile(files[4], as: .beside)
        #expect(workspace.layout == .four)
        #expect(workspace.panes.map { workspace.tab($0.tabID)?.name } == ["a.md", "d.md", "e.md", "c.md"])
        #expect(workspace.focusedPane == 2)

        workspace.setLayout(.grid)
        #expect(workspace.panes.count == 4)
        workspace.setLayout(.two)
        #expect(workspace.panes.count == 2)
        #expect(workspace.tabs.count == 5, "Dropped panes leave their tabs in the bar")
        #expect(workspace.focusedPane == 1)

        // Closing a pane keeps its tab; closing the only tab of a pane closes the pane.
        workspace.closePane(0)
        #expect(workspace.layout == .one)
        #expect(workspace.tabs.count == 5)
        workspace.setLayout(.two)
        let second = try #require(workspace.tab(workspace.panes[1].tabID))
        for tab in workspace.tabs where tab.id != second.id && !workspace.isVisible(tab) { workspace.close(tab) }
        workspace.close(second)
        #expect(workspace.panes.count == 1, "A split pane left with nothing to show closes")
        #expect(workspace.layout == .one)
    }

    @Test func sessionKeepsLayoutPanesAndSizes() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for file in files { model.openFile(file, as: .newTab) }
        model.workspace.selectTab(at: 0)
        model.workspace.setLayout(.two)
        model.workspace.setFractions([0.3, 0.7], for: .two)
        model.workspace.focus(1)
        model.prepareToQuit()

        let (reopened, _) = try makeModel(suite)
        let workspace = reopened.workspace
        #expect(workspace.layout == .two)
        #expect(workspace.panes.map { workspace.tab($0.tabID)?.name } == ["a.md", "b.md"])
        #expect(workspace.focusedPane == 1)
        #expect(workspace.fractions[.two] == [0.3, 0.7])
        #expect(reopened.document?.url.lastPathComponent == "b.md")
        #expect(workspace.tab(for: files[2])?.document == nil)
    }

    @Test func pdfFitsANarrowPaneButNeverGrowsPastItsSize() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        try PDFTests.writePDF(["Uma página larga o bastante"], to: file)
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (app, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        app.openFile(file)
        let model = try #require(app.document)
        _ = NSApplication.shared

        func makeView(width: CGFloat) -> AnnotatedPDFView {
            let view = AnnotatedPDFView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
            view.displayMode = .singlePageContinuous
            // As the app does: the limits turn PDFKit's autoScales off.
            view.minScaleFactor = 0.1
            view.maxScaleFactor = 8
            view.installObservers()
            view.update(model: model, theme: .polar, appModel: app)
            view.layout()
            return view
        }

        let narrow = makeView(width: 320)
        defer { narrow.tearDown() }
        #expect(narrow.scaleFactor < 0.6, "A 600 pt page fits a 320 pt pane")
        #expect(abs(narrow.scaleFactor - narrow.scaleFactorForSizeToFit) < 0.01)
        narrow.setFrameSize(NSSize(width: 450, height: 700))
        narrow.layout()
        #expect(abs(narrow.scaleFactor - narrow.scaleFactorForSizeToFit) < 0.01, "It follows the pane when it is resized")

        let wide = makeView(width: 1800)
        defer { wide.tearDown() }
        #expect(wide.scaleFactor == 1, "A wide pane keeps the page at its own size")

        model.zoomPDF(1)
        wide.update(model: model, theme: .polar, appModel: app)
        #expect(!wide.fitsPane, "Zooming stops the fitting")
        #expect(wide.scaleFactor > 1)
    }

    @Test func droppingAFileOnAPaneOpensItThereOrBesideIt() throws {
        let (folder, files) = try makeFiles(["a.md", "b.md", "c.md", "d.md", "e.md", "f.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = model.workspace
        func shown() -> [String?] { workspace.panes.map { workspace.tab($0.tabID)?.name } }

        model.openFile(files[0])
        model.beginFileDrag(files[1])
        #expect(model.draggedFile == files[1], "The panes show drop targets while a file is dragged")
        model.dropFile(files[1], on: 0, side: .trailing)
        #expect(model.draggedFile == nil)
        #expect(workspace.layout == .two)
        #expect(shown() == ["a.md", "b.md"])
        #expect(workspace.focusedPane == 1)
        #expect(workspace.tabs.allSatisfy { !$0.isPreview || $0.name == "a.md" }, "A dropped file is kept")

        model.dropFile(files[2], on: 0, side: .leading)
        #expect(shown() == ["c.md", "a.md", "b.md"])
        #expect(workspace.focusedPane == 0)

        model.dropFile(files[3], on: 1, side: .center)
        #expect(shown() == ["c.md", "d.md", "b.md"], "The center replaces the pane's file; its tab stays in the bar")
        #expect(workspace.tab(for: files[0]) != nil)

        model.dropFile(files[4], on: 2, side: .trailing)
        #expect(workspace.layout == .four)
        model.dropFile(files[5], on: 3, side: .trailing)
        #expect(workspace.panes.count == 4, "With four panes a side drop replaces the file")
        #expect(shown() == ["c.md", "d.md", "b.md", "f.md"])

        // A file already on screen is not shown twice: its pane is focused.
        model.dropFile(files[2], on: 3, side: .center)
        #expect(shown() == ["c.md", "d.md", "b.md", "f.md"])
        #expect(workspace.focusedPane == 0)

        let note = folder.appending(path: "notas.txt")
        try "x".write(to: note, atomically: true, encoding: .utf8)
        let before = workspace.tabs.count
        model.dropFile(note, on: 0, side: .center)
        #expect(workspace.tabs.count == before, "Only Markdown and PDF files open")
    }

    @Test func dropTargetZones() {
        let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        #expect(view.side(at: NSPoint(x: 20, y: 200)) == .leading)
        #expect(view.side(at: NSPoint(x: 150, y: 200)) == .center)
        #expect(view.side(at: NSPoint(x: 280, y: 200)) == .trailing)
        #expect(view.rect(for: .trailing).minX >= 150)
        view.allowsSides = false
        #expect(view.side(at: NSPoint(x: 280, y: 200)) == .center, "No room for another pane: the whole pane is the target")
        #expect(view.registeredDraggedTypes.contains(.fileURL))
    }

    @Test func zenShowsOnlyTheDocumentsAndCommentingOrChatLeavesIt() async throws {
        let (folder, files) = try makeFiles(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "dev.rheav.jullia.tabs.\(UUID().uuidString)"
        let (model, defaults) = try makeModel(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        model.toggleZen()
        #expect(!model.zen, "Nothing open: nothing for zen to show")

        model.openFile(files[0], as: .permanent)
        model.toggleZen()
        #expect(model.zen)
        #expect(model.zenHint, "The way out is announced")
        model.toggleZen()
        #expect(!model.zen)
        #expect(!model.zenHint)

        // Writing a comment needs the panel: zen ends and the panel opens.
        model.commentsCollapsed = true
        model.setZen(true)
        model.commentWholeDocument()
        #expect(!model.zen)
        #expect(!model.commentsCollapsed)
        model.document?.composing = nil

        model.setZen(true)
        model.revealChat()
        #expect(!model.zen)

        // A click on a commented passage does not end it.
        model.setZen(true)
        model.selectCommentsTab()
        #expect(model.zen)

        // Not saved: the next launch opens in the normal view.
        model.prepareToQuit()
        let (reopened, _) = try makeModel(suite)
        #expect(!reopened.zen)

        // Closing the last tab ends it.
        model.closeFocusedTab()
        #expect(!model.zen)
    }
}
