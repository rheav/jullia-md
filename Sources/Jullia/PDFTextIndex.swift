import Foundation
import JulliaCore
import PDFKit

/// Stable text coordinates for the shared annotation model, with exact page-local selections for PDFKit.
@MainActor
final class PDFTextIndex {
    struct PageText {
        let text: NSString
        let range: NSRange
    }

    let document: PDFDocument
    let pages: [PageText]
    let text: NSString

    init(document: PDFDocument) {
        self.document = document
        var combined = ""
        var pages: [PageText] = []
        var offset = 0
        for index in 0..<document.pageCount {
            if index > 0 { combined += "\n"; offset += 1 }
            let text = (document.page(at: index)?.string ?? "") as NSString
            pages.append(PageText(text: text, range: NSRange(location: offset, length: text.length)))
            combined += text as String
            offset += text.length
        }
        self.pages = pages
        self.text = combined as NSString
    }

    func anchor(for selection: PDFSelection) -> TextAnchor? {
        var fragments: [PDFAnchorFragment] = []
        for page in selection.pages {
            let pageIndex = document.index(for: page)
            guard pages.indices.contains(pageIndex) else { return nil }
            var ranges = (0..<selection.numberOfTextRanges(on: page)).map { selection.range(at: $0, on: page) }
            ranges.sort { $0.location < $1.location }
            var merged: [NSRange] = []
            for range in ranges where valid(range, in: pages[pageIndex].text) {
                if let last = merged.last, NSMaxRange(last) >= range.location {
                    merged[merged.count - 1] = NSUnionRange(last, range)
                } else {
                    merged.append(range)
                }
            }
            fragments += merged.map { PDFAnchorFragment(pageIndex: pageIndex, text: Anchoring.make(range: $0, in: pages[pageIndex].text)) }
        }
        return anchor(fragments: fragments)
    }

    func anchor(for range: NSRange) -> TextAnchor? {
        guard valid(range, in: text) else { return nil }
        let fragments = pages.enumerated().compactMap { index, page -> PDFAnchorFragment? in
            let intersection = NSIntersectionRange(range, page.range)
            guard intersection.length > 0 else { return nil }
            let local = NSRange(location: intersection.location - page.range.location, length: intersection.length)
            return PDFAnchorFragment(pageIndex: index, text: Anchoring.make(range: local, in: page.text))
        }
        return anchor(fragments: fragments)
    }

    private func anchor(fragments: [PDFAnchorFragment]) -> TextAnchor? {
        let fragments = fragments.sorted {
            $0.pageIndex == $1.pageIndex ? $0.text.start < $1.text.start : $0.pageIndex < $1.pageIndex
        }
        guard let first = fragments.first, let last = fragments.last else { return nil }
        let start = pages[first.pageIndex].range.location + first.text.start
        let end = pages[last.pageIndex].range.location + last.text.end
        var anchor = TextAnchor(start: start, end: end, quote: fragments.map(\.text.quote).joined(separator: "\n"),
                                prefix: first.text.prefix, suffix: last.text.suffix)
        anchor.pdf = fragments
        return anchor
    }

    /// All fragments must survive; partially missing selections must not silently annotate other text.
    func resolve(_ anchor: TextAnchor) -> TextAnchor? {
        guard let fragments = anchor.pdf, !fragments.isEmpty else { return nil }
        var resolved: [PDFAnchorFragment] = []
        for fragment in fragments {
            var best: (page: Int, range: NSRange, score: Int, distance: Int)?
            for (index, page) in pages.enumerated() {
                guard let range = Anchoring.resolve(fragment.text, in: page.text).range else { continue }
                let context = Anchoring.make(range: range, in: page.text)
                let score = zip(context.prefix.utf16.reversed(), fragment.text.prefix.utf16.reversed()).prefix { $0 == $1 }.count
                    + zip(context.suffix.utf16, fragment.text.suffix.utf16).prefix { $0 == $1 }.count
                let distance = abs(index - fragment.pageIndex)
                if best == nil || score > best!.score || (score == best!.score && distance < best!.distance) {
                    best = (index, range, score, distance)
                }
            }
            guard let best else { return nil }
            var local = fragment.text
            local.start = best.range.location
            local.end = NSMaxRange(best.range)
            resolved.append(PDFAnchorFragment(pageIndex: best.page, text: local))
        }
        // Distinct fragments collapsing onto the same text means part of the selection was lost.
        for (offset, fragment) in resolved.enumerated() {
            for other in resolved.prefix(offset) where other.pageIndex == fragment.pageIndex {
                if NSIntersectionRange(other.text.range, fragment.text.range).length > 0 { return nil }
            }
        }
        guard var result = self.anchor(fragments: resolved) else { return nil }
        result.quote = anchor.quote
        result.prefix = anchor.prefix
        result.suffix = anchor.suffix
        return result
    }

    func selection(for anchor: TextAnchor) -> PDFSelection? {
        guard let parts = selections(for: anchor) else { return nil }
        let selection = PDFSelection(document: document)
        for part in parts { selection.add(part) }
        return selection
    }

    /// Keep disjoint fragments separate: PDFKit merges same-line fragments' bounds when combined.
    func lines(for anchor: TextAnchor) -> [PDFSelection] {
        selections(for: anchor)?.flatMap { $0.selectionsByLine() } ?? []
    }

    private func selections(for anchor: TextAnchor) -> [PDFSelection]? {
        guard let fragments = anchor.pdf, !fragments.isEmpty else { return nil }
        var selections: [PDFSelection] = []
        for fragment in fragments {
            guard pages.indices.contains(fragment.pageIndex),
                  fragment.text.start >= 0, fragment.text.end > fragment.text.start,
                  fragment.text.end <= pages[fragment.pageIndex].text.length,
                  let page = document.page(at: fragment.pageIndex),
                  let part = page.selection(for: fragment.text.range) else { return nil }
            selections.append(part)
        }
        return selections
    }

    private func valid(_ range: NSRange, in text: NSString) -> Bool {
        range.location >= 0 && range.location <= text.length && range.length > 0 && range.length <= text.length - range.location
    }
}
