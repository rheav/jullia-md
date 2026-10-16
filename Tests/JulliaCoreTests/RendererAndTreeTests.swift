import AppKit
import Foundation
import Testing
@testable import JulliaCore

@Suite struct MarkdownRendererTests {
    let source = """
        # Título

        Um parágrafo com **negrito**, *itálico*, `código` e [link](https://example.com).

        > Uma citação.

        - item um
        - item dois
          1. sub
        - [x] feito

        ```swift
        let x = 1
        let y = 2
        ```

        | A | B |
        |---|--:|
        | 1 | 2 |

        ---

        Fim.
        """

    @Test func headingsAreFoundWithTheirLevelsAndPlaces() {
        let source = "# Livro\n\nIntrodução.\n\n## Parte *um*\n\nTexto.\n\n> ### Citado\n\n#### Fundo\n"
        let rendered = MarkdownRenderer.render(source, options: RenderOptions(theme: .snow))
        let headings = MarkdownRenderer.headings(in: rendered)
        #expect(headings.map(\.title) == ["Livro", "Parte um", "Citado", "Fundo"])
        #expect(headings.map(\.level) == [1, 2, 3, 4])
        let text = rendered.string as NSString
        #expect(headings.map { text.substring(with: $0.range) } == ["Livro", "Parte um", "Citado", "Fundo"])
        #expect(rendered.string == MarkdownRenderer.plainText(source))
        #expect(MarkdownRenderer.headings(in: MarkdownRenderer.render("Sem títulos.", options: RenderOptions(theme: .snow))).isEmpty)
    }

    @Test func textDoesNotDependOnThemeOrSize() {
        let polar = MarkdownRenderer.render(source, options: RenderOptions(theme: .polar, fontSize: 15)).string
        let paper = MarkdownRenderer.render(source, options: RenderOptions(theme: .paper, fontSize: 21)).string
        #expect(polar == paper)
    }

    @Test func rendersReadableText() {
        let text = MarkdownRenderer.plainText(source)
        #expect(text.hasPrefix("Título\n"))
        #expect(text.contains("Um parágrafo com negrito, itálico, código e link."))
        #expect(text.contains("Uma citação.\n"))
        #expect(text.contains("•\titem um\n"))
        #expect(text.contains("1.\tsub\n"))
        #expect(text.contains("☑︎\tfeito\n"))
        #expect(text.contains("let x = 1\u{2028}let y = 2\n"))
        #expect(text.contains("Fim.\n"))
        #expect(!text.contains("**"))
        #expect(!text.contains("```"))
    }

    @Test func stylesInlineRuns() {
        let rendered = MarkdownRenderer.render(source, options: RenderOptions(theme: .polar))
        let text = rendered.string as NSString
        let bold = rendered.attribute(.font, at: text.range(of: "negrito").location, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let link = rendered.attribute(.link, at: text.range(of: "link").location, effectiveRange: nil) as? URL
        #expect(link?.absoluteString == "https://example.com")
        let code = rendered.attribute(.font, at: text.range(of: "let x").location, effectiveRange: nil) as? NSFont
        #expect(code?.isFixedPitch == true)
    }

    @Test func tableCellsSitInATextTable() {
        let rendered = MarkdownRenderer.render(source, options: RenderOptions(theme: .snow))
        let text = rendered.string as NSString
        let style = rendered.attribute(.paragraphStyle, at: text.range(of: "2\n", options: .backwards).location, effectiveRange: nil) as? NSParagraphStyle
        let block = style?.textBlocks.last as? NSTextTableBlock
        #expect(block?.table.numberOfColumns == 2)
        #expect(block?.startingColumn == 1)
    }

    @Test func htmlCommentsAreHidden() {
        let text = MarkdownRenderer.plainText("Antes\n\n<!-- segredo -->\n\nDepois")
        #expect(!text.contains("segredo"))
    }
}

@Suite struct FileTreeTests {
    @Test func scansMarkdownOnlyAndPrunesEmptyFolders() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jullia-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for dir in ["docs/specs", "empty", "node_modules/pkg", ".hidden"] {
            try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        for file in ["README.md", "notes.txt", "docs/b.md", "docs/A.markdown", "docs/specs/c.md", "node_modules/pkg/x.md", ".hidden/y.md", "empty/z.txt"] {
            try "x".write(to: root.appending(path: file), atomically: true, encoding: .utf8)
        }

        let tree = FileTree.scan(root)
        #expect(tree.children?.map(\.name) == ["docs", "README.md"])
        let docs = tree.children![0]
        #expect(docs.children?.map(\.name) == ["specs", "A.markdown", "b.md"])
        #expect(tree.files.map(\.name) == ["c.md", "A.markdown", "b.md", "README.md"])

        let filtered = FileTree.filter(tree, query: "C")
        #expect(filtered?.files.map(\.name) == ["c.md"])
        #expect(FileTree.filter(tree, query: "nada") == nil)
    }

    @Test func sortsFindsNodesFlattensAndSearches() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jullia-tree-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "Curso/Bônus"), withIntermediateDirectories: true)
        let files = ["a-old.pdf", "b-new.md", "Curso/Aula.pdf", "Curso/Bônus/Extra.md"]
        for (index, file) in files.enumerated() {
            let url = root.appending(path: file)
            try "x".write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000 + Double(index) * 100)], ofItemAtPath: url.path)
        }

        let tree = FileTree.scan(root)
        #expect(tree.children?.map(\.name) == ["Curso", "a-old.pdf", "b-new.md"])
        let byDate = FileTree.sorted(tree, by: .date)
        #expect(byDate.children?.map(\.name) == ["Curso", "b-new.md", "a-old.pdf"], "Folders first, then newest files")

        let curso = try #require(FileTree.node(at: root.appending(path: "Curso"), in: tree))
        #expect(curso.children?.map(\.name) == ["Bônus", "Aula.pdf"])
        #expect(FileTree.node(at: root.appending(path: "Nada"), in: tree) == nil)

        #expect(FileTree.rows(tree, expanded: []).map(\.node.name) == ["Curso", "a-old.pdf", "b-new.md"])
        let expanded: Set<URL> = [root.appending(path: "Curso").standardizedFileURL, root.appending(path: "Curso/Bônus").standardizedFileURL]
        let rows = FileTree.rows(tree, expanded: expanded)
        #expect(rows.map(\.node.name) == ["Curso", "Bônus", "Extra.md", "Aula.pdf", "a-old.pdf", "b-new.md"])
        #expect(rows.map(\.depth) == [0, 1, 2, 1, 0, 0])

        #expect(FileTree.search([tree], query: "AULA").map(\.name) == ["Aula.pdf"])
        #expect(FileTree.search([tree, tree], query: "extra").count == 1, "The same file is listed once")
        #expect(FileTree.search([tree], query: ".", limit: 2).count == 2)
        #expect(FileTree.search([tree], query: "  ").isEmpty)
        #expect(FileTree.scan(root, maxDepth: 1).children?.map(\.name) == ["a-old.pdf", "b-new.md"], "Folders past the depth are left out")
        #expect(FileTree.isWithin(root.appending(path: "Curso/Aula.pdf"), root))
        #expect(!FileTree.isWithin(URL(fileURLWithPath: root.path + "-other"), root))
    }
}
