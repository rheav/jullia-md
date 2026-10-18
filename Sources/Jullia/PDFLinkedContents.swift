import PDFKit

/// The table of contents printed in a PDF as links to its own pages, read as the outline of a PDF that has none. Each
/// link is an item titled by the text it covers. A line without a link just above a run of them heads that run, as
/// "Capítulo 1" over its sections, and links set further right than the others sit a level deeper.
@MainActor
enum PDFLinkedContents {
    /// A link to another page of the document.
    private struct Link {
        let bounds: CGRect
        let target: OutlineItem.Target
        var page: Int { if case .page(let page, _) = target { page } else { 0 } }
    }

    /// A line of text with letters in it, and whether a link runs along it.
    private struct Line {
        let text: String
        let bounds: CGRect
        let linked: Bool
    }

    /// A page of the printed contents: its links and its lines, top to bottom.
    private struct ContentsPage {
        let index: Int
        let links: [Link]
        let lines: [Line]
    }

    /// One item of the contents, from one link or from the pieces of one (its title and its page number).
    private struct Entry {
        var title: String
        var bounds: CGRect
        var indent: CGFloat
        let target: OutlineItem.Target
    }

    private enum Mark {
        case line(Line)
        case entry(Entry)
        var bounds: CGRect {
            switch self {
            case .line(let line): line.bounds
            case .entry(let entry): entry.bounds
            }
        }
    }

    static func outline(of document: PDFDocument) -> [OutlineItem] {
        let pages = contentsPages(of: document)
        // Lines printed on more than one page of the contents are its running header or footer, not headings.
        var printed: [String: Int] = [:]
        for page in pages {
            for text in Set(page.lines.filter { !$0.linked }.map(\.text)) { printed[text, default: 0] += 1 }
        }
        var marks: [(heading: Line?, entry: Entry)] = []
        for page in pages {
            guard let pdfPage = document.page(at: page.index) else { continue }
            let all = page.lines.filter { !$0.linked }.map(Mark.line) + entries(of: page, on: pdfPage).map(Mark.entry)
            var above: Line?
            for mark in all.sorted(by: { readingOrder($0.bounds, $1.bounds) }) {
                switch mark {
                case .line(let line):
                    above = line
                case .entry(let entry):
                    let heading = above.flatMap { line in
                        printed[line.text] == 1 && line.bounds.minY - entry.bounds.maxY <= 2 * entry.bounds.height
                            ? line : nil
                    }
                    marks.append((heading, entry))
                    above = nil
                }
            }
        }
        // A single heading over the whole list is the contents' own title.
        let headed = marks.filter { $0.heading != nil }.count >= 2
        let depth = depths(of: marks.map(\.entry.indent))
        var items: [OutlineItem] = []
        var underHeading = false
        for (heading, entry) in marks {
            if headed, let heading {
                items.append(OutlineItem(id: items.count, title: heading.text, level: 1, target: entry.target))
                underHeading = true
            }
            let level = depth(entry.indent) + (underHeading ? 2 : 1)
            items.append(OutlineItem(id: items.count, title: entry.title, level: level, target: entry.target))
        }
        return items
    }

    /// The run of consecutive pages that reads as a table of contents, the longest if there are several, as a book
    /// with a short contents at the start of each chapter.
    private static func contentsPages(of document: PDFDocument) -> [ContentsPage] {
        var best: [ContentsPage] = []
        var run: [ContentsPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { run = []; continue }
            let links = links(on: page, at: index, in: document)
            if let last = run.last, let next = contentsPage(page, at: index, links: links, after: last) {
                run.append(next)
            } else if let first = contentsPage(page, at: index, links: links, after: nil) {
                run = [first]
            } else {
                run = []
            }
            if run.map(\.links.count).reduce(0, +) > best.map(\.links.count).reduce(0, +) { best = run }
        }
        return best
    }

    /// The page as a page of contents, if its links run like one: to at least three pages in order, or on from the
    /// page before it, along most of its lines of text.
    private static func contentsPage(_ page: PDFPage, at index: Int, links: [Link], after previous: ContentsPage?)
        -> ContentsPage? {
        let targets = links.map(\.page)
        if let previous {
            guard previous.index == index - 1, let first = targets.first, let last = previous.links.last,
                  first >= last.page else { return nil }
        } else {
            guard links.count >= 4, Set(targets).count >= 3 else { return nil }
        }
        let inOrder = zip(targets, targets.dropFirst()).filter { $0 <= $1 }.count
        guard Double(inOrder) >= 0.75 * Double(targets.count - 1) else { return nil }
        let lines = lines(on: page, along: links)
        guard lines.filter(\.linked).count * 2 >= lines.count else { return nil }
        return ContentsPage(index: index, links: links, lines: lines)
    }

    /// The page's links to other pages of the document, in reading order.
    private static func links(on page: PDFPage, at index: Int, in document: PDFDocument) -> [Link] {
        page.annotations.compactMap { annotation -> Link? in
            guard annotation.type == "Link" else { return nil }
            let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination
            guard let destination, let target = destination.page else { return nil }
            let targetIndex = document.index(for: target)
            guard targetIndex != NSNotFound, targetIndex != index else { return nil }
            return Link(bounds: annotation.bounds, target: .page(targetIndex, destination.point))
        }
        .sorted { readingOrder($0.bounds, $1.bounds) }
    }

    /// The page's lines with letters in them, in reading order, each marked when a link runs along it.
    private static func lines(on page: PDFPage, along links: [Link]) -> [Line] {
        let selections = page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? []
        return selections.compactMap { selection -> Line? in
            let text = cleaned(selection.string ?? "")
            guard text.contains(where: \.isLetter) else { return nil }
            let bounds = selection.bounds(for: page)
            let linked = links.contains { overlap($0.bounds, bounds) >= bounds.height / 2 }
            return Line(text: text, bounds: bounds, linked: linked)
        }
        .sorted { readingOrder($0.bounds, $1.bounds) }
    }

    /// The page's links as items: the pieces of one on the same line joined, each titled by the text it covers, or,
    /// when it covers only a page number, by its line.
    private static func entries(of contents: ContentsPage, on page: PDFPage) -> [Entry] {
        var pieces: [Entry] = []
        for link in contents.links {
            if let last = pieces.last, last.target == link.target,
               overlap(last.bounds, link.bounds) >= min(last.bounds.height, link.bounds.height) / 2 {
                pieces[pieces.count - 1].bounds = last.bounds.union(link.bounds)
            } else {
                pieces.append(Entry(title: "", bounds: link.bounds, indent: link.bounds.minX, target: link.target))
            }
        }
        var entries: [Entry] = []
        for var entry in pieces {
            entry.title = cleaned(page.selection(for: entry.bounds.insetBy(dx: 0, dy: entry.bounds.height / 4))?.string ?? "")
            if !entry.title.contains(where: \.isLetter) {
                let row = contents.lines.filter { overlap($0.bounds, entry.bounds) >= $0.bounds.height / 2 }
                entry.title = row.map(\.text).joined(separator: " ")
                    .replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
                entry.indent = row.map(\.bounds.minX).min() ?? entry.indent
            }
            guard entry.title.contains(where: \.isLetter) else { continue }
            // A title wrapped onto a second line, each line its own link: the second goes on in lowercase.
            if let last = entries.last, last.target == entry.target, entry.title.first?.isLowercase == true {
                entries[entries.count - 1].title += " " + entry.title
                entries[entries.count - 1].bounds = last.bounds.union(entry.bounds)
                continue
            }
            entries.append(entry)
        }
        return entries
    }

    /// Each indent's depth, indents within 10 points of each other being one, as numbers of different widths shift
    /// a title a little. More than three depths are ragged lines, not a hierarchy.
    private static func depths(of indents: [CGFloat]) -> (CGFloat) -> Int {
        var starts: [CGFloat] = []
        for indent in indents.sorted() where starts.last.map({ indent - $0 > 10 }) ?? true { starts.append(indent) }
        guard starts.count <= 3 else { return { _ in 0 } }
        return { indent in starts.lastIndex { $0 <= indent } ?? 0 }
    }

    /// Top to bottom, then left to right.
    private static func readingOrder(_ a: CGRect, _ b: CGRect) -> Bool {
        (a.midY.rounded(), -a.minX) > (b.midY.rounded(), -b.minX)
    }

    /// How far two rectangles overlap vertically.
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    /// The text on one line, without dot leaders and the page number after them.
    private static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: #"\s*(?:(?:[.·…_]\s*){2,}\d+|(?:[.·_]\s*){4,})$"#, with: "",
                                  options: .regularExpression)
    }
}
