import AppKit
import Testing
@testable import JulliaCore

/// Lays rendered text out in a real TextKit 1 view, where block styling problems show up.
@MainActor @Suite struct LayoutTests {
    @Test func codeAndQuoteBlocksLayOutAsBlocks() {
        let rendered = MarkdownRenderer.render(
            "Intro\n\n```\nlinha um\nlinha dois\n```\n\n> quote um\n",
            options: RenderOptions(theme: .polar, fontSize: 15)
        )
        let view = NSTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        view.textStorage?.setAttributedString(rendered)
        let layout = view.layoutManager!
        layout.ensureLayout(for: view.textContainer!)
        let text = rendered.string as NSString

        func rect(_ word: String) -> NSRect {
            let glyphs = layout.glyphRange(forCharacterRange: text.range(of: word), actualCharacterRange: nil)
            return layout.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        }

        let intro = rect("Intro"), one = rect("linha um"), two = rect("linha dois"), quote = rect("quote um")
        #expect(one.width > 40, "a block without a width lays its text out one letter per line")
        #expect(one.minX == two.minX, "every line of a code block starts at the same x")
        #expect(one.minX > intro.minX, "code is inset by the block's padding")
        #expect(quote.minX > intro.minX, "a quote is inset past its bar")
        #expect(two.height < 30)
    }
}
