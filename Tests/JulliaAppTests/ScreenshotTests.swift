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
        model.openFile(examples.appending(path: "Guia-de-leitura.md"), as: .permanent)
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

        // Zen with two PDFs side by side: the example texts typeset as PDF pages, so no personal document shows.
        let pdfFolder = FileManager.default.temporaryDirectory.appending(path: "jullia-zen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pdfFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pdfFolder) }
        let welcomePDF = pdfFolder.appending(path: "Boas-vindas.pdf")
        let guidePDF = pdfFolder.appending(path: "Guia-de-leitura.pdf")
        try typeset(file, to: welcomePDF)
        try typeset(examples.appending(path: "Guia-de-leitura.md"), to: guidePDF)
        model.openFile(welcomePDF, as: .permanent)
        model.openFile(guidePDF, as: .beside)
        model.setZen(true)
        #expect(model.workspace.panes.count == 2)
        // Past the "Esc to leave" note, which is only on screen for a moment.
        while model.zenHint { try await Task.sleep(for: .milliseconds(100)) }
        try await capture(model: model, to: output.appending(path: "zen.png"), settle: .milliseconds(900))
    }

    /// Lays a Markdown example out as US Letter PDF pages, in the Paper theme's text colours on white. TextKit 1, as
    /// in the reader, so tables and code blocks keep their shape.
    private func typeset(_ markdown: URL, to pdf: URL) throws {
        let source = try String(contentsOf: markdown, encoding: .utf8)
        let text = MarkdownRenderer.render(source, options: RenderOptions(theme: .paper, fontSize: 13, baseURL: markdown.deletingLastPathComponent()))
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin = CGSize(width: 64, height: 72)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: CGSize(width: page.width - 2 * margin.width, height: page.height - 2 * margin.height))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            containers.append(container)
            guard layout.glyphRange(for: container).length > 0 else { break }
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 20

        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &page, nil))
        for container in containers {
            let glyphs = layout.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let origin = CGPoint(x: margin.width, y: margin.height)
            layout.drawBackground(forGlyphRange: glyphs, at: origin)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: pdf)
    }

    private func capture(model: AppModel, to url: URL, settle: Duration = .milliseconds(300)) async throws {
        let size = NSSize(width: 1320, height: 880)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: model.settings.theme.isDark ? .darkAqua : .aqua)
        let view = NSHostingView(rootView: MainView().environment(model).environment(model.settings))
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: settle)
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
