import AppKit
import Foundation
import Testing
@testable import MarknordCore

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
        let root = FileManager.default.temporaryDirectory.appending(path: "marknord-tree-\(UUID().uuidString)")
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
}
