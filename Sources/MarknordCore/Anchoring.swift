import Foundation

/// Where a highlight or comment sits in the rendered text, with enough context to find it again after the file changes.
/// Offsets are UTF-16, the units of `NSString` and `NSRange`.
public struct TextAnchor: Codable, Hashable, Sendable {
    public var start: Int
    public var end: Int
    public var quote: String
    public var prefix: String
    public var suffix: String

    public init(start: Int, end: Int, quote: String, prefix: String, suffix: String) {
        self.start = start
        self.end = end
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
    }

    public var range: NSRange { NSRange(location: start, length: end - start) }
}

public enum AnchorResolution: Equatable, Sendable {
    /// The passage is where it was.
    case exact(NSRange)
    /// The passage was found elsewhere; the anchor should be saved with the new offsets.
    case moved(NSRange)
    /// The passage is no longer in the text.
    case orphan

    public var range: NSRange? {
        switch self {
        case .exact(let range), .moved(let range): range
        case .orphan: nil
        }
    }
}

public enum Anchoring {
    public static let contextLength = 32

    public static func make(range: NSRange, in text: NSString) -> TextAnchor {
        let before = max(0, range.location - contextLength)
        let afterEnd = min(text.length, NSMaxRange(range) + contextLength)
        return TextAnchor(
            start: range.location,
            end: NSMaxRange(range),
            quote: text.substring(with: range),
            prefix: text.substring(with: NSRange(location: before, length: range.location - before)),
            suffix: text.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range)))
        )
    }

    public static func resolve(_ anchor: TextAnchor, in text: NSString) -> AnchorResolution {
        guard !anchor.quote.isEmpty else { return .orphan }
        let length = (anchor.quote as NSString).length
        if anchor.start >= 0, anchor.start + length <= text.length,
           text.substring(with: NSRange(location: anchor.start, length: length)) == anchor.quote {
            return .exact(NSRange(location: anchor.start, length: length))
        }

        var best: (range: NSRange, score: Int, distance: Int)?
        var searchFrom = 0
        while searchFrom < text.length {
            let found = text.range(
                of: anchor.quote, options: [.literal],
                range: NSRange(location: searchFrom, length: text.length - searchFrom)
            )
            if found.location == NSNotFound { break }
            let score = contextScore(of: found, in: text, anchor: anchor)
            let distance = abs(found.location - anchor.start)
            if best == nil || score > best!.score || (score == best!.score && distance < best!.distance) {
                best = (found, score, distance)
            }
            searchFrom = found.location + 1
        }
        return best.map { .moved($0.range) } ?? .orphan
    }

    /// How many characters of the saved prefix and suffix still surround a candidate.
    static func contextScore(of range: NSRange, in text: NSString, anchor: TextAnchor) -> Int {
        let before = max(0, range.location - contextLength)
        let prefix = text.substring(with: NSRange(location: before, length: range.location - before))
        let afterEnd = min(text.length, NSMaxRange(range) + contextLength)
        let suffix = text.substring(with: NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range)))
        return commonSuffixLength(prefix, anchor.prefix) + commonPrefixLength(suffix, anchor.suffix)
    }

    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        zip(a.utf16, b.utf16).prefix { $0 == $1 }.count
    }

    static func commonSuffixLength(_ a: String, _ b: String) -> Int {
        zip(a.utf16.reversed(), b.utf16.reversed()).prefix { $0 == $1 }.count
    }
}
