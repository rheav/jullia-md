import AppKit

/// A code block: rounded fill.
final class CodeTextBlock: NSTextBlock {
    var fill: NSColor = .clear
    var radius: CGFloat = 8

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let rect = contentFrame(frameRect)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    func contentFrame(_ frame: NSRect) -> NSRect {
        let left = width(for: .margin, edge: .minX), right = width(for: .margin, edge: .maxX)
        let top = width(for: .margin, edge: .minY), bottom = width(for: .margin, edge: .maxY)
        return NSRect(x: frame.minX + left, y: frame.minY + top, width: frame.width - left - right, height: frame.height - top - bottom)
    }
}

/// A block quote: a rounded bar on the left.
final class QuoteTextBlock: NSTextBlock {
    var bar: NSColor = .clear

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let left = width(for: .margin, edge: .minX)
        let top = width(for: .margin, edge: .minY), bottom = width(for: .margin, edge: .maxY)
        let rect = NSRect(x: frameRect.minX + left, y: frameRect.minY + top, width: 3, height: frameRect.height - top - bottom)
        bar.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

/// A thematic break: a hairline across the middle.
final class RuleTextBlock: NSTextBlock {
    var line: NSColor = .clear

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        line.setFill()
        NSRect(x: frameRect.minX, y: frameRect.midY.rounded(), width: frameRect.width, height: 1).fill()
    }
}
