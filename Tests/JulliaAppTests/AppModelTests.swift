import Foundation
import JulliaCore
import Testing
@testable import Jullia

@MainActor @Suite struct AppModelTests {
    @Test func isolatedSessionPersistsAnnotationsWithoutChangingMarkdown() throws {
        let suite = "dev.rheav.jullia.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "reading.md")
        let source = "# Reading\n\nA passage worth remembering.\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let storeURL = folder.appending(path: "annotations.sqlite")
        let model = AppModel(defaults: defaults, settings: settings, storeURL: storeURL)
        model.addFolder(folder)
        model.openFile(file)
        let document = try #require(model.document)
        document.selection = document.text.range(of: "passage worth remembering")
        model.highlightSelection(color: .green)
        model.commentSelection()
        document.submitComment(body: "Keep this idea.", color: .blue)
        #expect(model.count(for: file) == 2)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)

        model.filesCollapsed = true
        let reopened = AppModel(defaults: defaults, settings: settings, storeURL: storeURL)
        #expect(reopened.filesCollapsed)
        #expect(reopened.roots.map(\.url) == [folder.standardizedFileURL])
        #expect(reopened.document?.url == file)
        #expect(reopened.document?.highlights.first?.color == .green)
        #expect(reopened.document?.comments.first?.body == "Keep this idea.")
        #expect(reopened.count(for: file) == 2)
    }

    @Test func reloadMovesAnnotationsAndThemeChangesPreserveThem() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "jullia-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try "# Notes\n\nRemember this passage.\n".write(to: file, atomically: true, encoding: .utf8)
        let document = DocumentModel(url: file, store: try AnnotationStore(url: nil))
        document.apply(RenderOptions(theme: .polar))
        let original = document.text.range(of: "Remember this passage.")
        document.highlight(original, color: .yellow)
        let id = try #require(document.highlights.first?.id)
        try "# Notes\n\nNew introduction.\n\nRemember this passage.\n".write(to: file, atomically: true, encoding: .utf8)
        document.reload()
        let moved = try #require(document.highlightRanges[id])
        #expect(moved.location > original.location)
        #expect(document.text.substring(with: moved) == "Remember this passage.")
        document.apply(RenderOptions(theme: .paper, fontSize: 22))
        #expect(document.highlightRanges[id] == moved)
    }
}
