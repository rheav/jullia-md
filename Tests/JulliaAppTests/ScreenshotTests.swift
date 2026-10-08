import AppKit
import JulliaCore
import SwiftUI
import Testing
@testable import Jullia

/// Opt-in documentation snapshots of the production views, with an isolated demo session.
@MainActor @Suite struct ScreenshotTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JULLIA_SCREENSHOTS"] != nil))
    func captureDocumentation() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["JULLIA_SCREENSHOTS"]))
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let examples = root.appending(path: "examples", directoryHint: .isDirectory)
        let file = examples.appending(path: "Boas-vindas.md")
        let suite = "dev.rheav.jullia.screenshots.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.followSystem = false
        settings.fontSize = 17
        // Opaque surfaces keep documentation independent of the desktop behind the app.
        settings.windowGlass.enabled = false
        settings.filesGlass.enabled = false
        settings.commentsGlass.enabled = false
        let model = AppModel(defaults: defaults, settings: settings, storeURL: nil)
        model.addFolder(examples)
        model.openFile(examples.appending(path: "Guia-de-leitura.md"))
        model.openFile(file)
        let document = try #require(model.document)
        document.highlight(document.text.range(of: "Destaque o que importa."), color: .green)
        document.highlight(document.text.range(of: "sem alterar o Markdown original"), color: .yellow)
        document.startComment(on: document.text.range(of: "Boas ideias merecem um lugar para continuar a conversa."))
        document.submitComment(body: "Uma boa leitura continua nas margens. Vamos retomar esta ideia na próxima revisão?", color: .green)
        let thread = try #require(document.comments.first)
        document.reply(to: thread.id, body: "Sim! O contexto fica aqui, junto do trecho.")
        document.startComment(on: nil)
        document.submitComment(body: "Notas de leitura: separar ideias, registrar dúvidas e voltar com um olhar novo.", color: nil)
        document.activeCommentID = nil

        _ = NSApplication.shared
        let oldAppearance = NSApp.appearance
        defer { NSApp.appearance = oldAppearance }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for theme in ThemeID.allCases {
            settings.fixedTheme = theme
            model.rerender()
            try await capture(model: model, to: output.appending(path: "\(theme.rawValue).png"))
        }
        settings.fixedTheme = .polar
        model.filesCollapsed = true
        model.commentsCollapsed = true
        model.rerender()
        try await capture(model: model, to: output.appending(path: "focus.png"))
    }

    private func capture(model: AppModel, to url: URL) async throws {
        let size = NSSize(width: 1320, height: 880)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: model.settings.theme.isDark ? .darkAqua : .aqua)
        let view = NSHostingView(rootView: MainView().environment(model).environment(model.settings))
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        // Vibrant sidebar selections require the window-server compositor. Capture the
        // file list without a selection so offscreen snapshots don't get a black row.
        clearListSelection(in: view)
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        #expect(bitmap.pixelsWide >= 1320)
        #expect(bitmap.pixelsHigh >= 880)
    }

    private func clearListSelection(in view: NSView) {
        (view as? NSTableView)?.deselectAll(nil)
        for child in view.subviews { clearListSelection(in: child) }
    }
}
