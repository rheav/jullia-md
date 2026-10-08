import Foundation
import Testing
@testable import JulliaCore

@Suite struct AnchoringTests {
    let text = "O gato subiu no telhado. O gato desceu do telhado. Fim." as NSString

    @Test func makeCapturesQuoteAndContext() {
        let range = text.range(of: "desceu")
        let anchor = Anchoring.make(range: range, in: text)
        #expect(anchor.quote == "desceu")
        #expect(anchor.start == range.location)
        #expect(anchor.end == NSMaxRange(range))
        #expect(anchor.prefix.hasSuffix("O gato "))
        #expect(anchor.suffix.hasPrefix(" do telhado"))
    }

    @Test func unchangedTextResolvesExactly() {
        let range = text.range(of: "subiu")
        let anchor = Anchoring.make(range: range, in: text)
        #expect(Anchoring.resolve(anchor, in: text) == .exact(range))
    }

    @Test func insertedTextBeforeMovesTheAnchor() {
        let range = text.range(of: "desceu")
        let anchor = Anchoring.make(range: range, in: text)
        let edited = ("Prólogo novo. " + (text as String)) as NSString
        #expect(Anchoring.resolve(anchor, in: edited) == .moved(edited.range(of: "desceu")))
    }

    @Test func repeatedQuotePicksTheOccurrenceWithMatchingContext() {
        // "O gato" appears twice; the second one is anchored.
        let second = text.range(of: "O gato", options: .backwards)
        let anchor = Anchoring.make(range: second, in: text)
        let edited = ("Intro. " + (text as String)) as NSString
        let expected = edited.range(of: "O gato", options: .backwards)
        #expect(Anchoring.resolve(anchor, in: edited) == .moved(expected))
    }

    @Test func missingQuoteIsAnOrphan() {
        let anchor = Anchoring.make(range: text.range(of: "telhado. O"), in: text)
        #expect(Anchoring.resolve(anchor, in: "Outro texto inteiro." as NSString) == .orphan)
    }

    @Test func outOfBoundsAnchorStillSearches() {
        let anchor = TextAnchor(start: 500, end: 504, quote: "gato", prefix: "O ", suffix: " subiu")
        #expect(Anchoring.resolve(anchor, in: text) == .moved(text.range(of: "gato")))
    }

    @Test func utf16OffsetsHandleEmoji() {
        let emoji = "🎉 festa e 🎉 bolo" as NSString
        let range = emoji.range(of: "bolo")
        let anchor = Anchoring.make(range: range, in: emoji)
        #expect(Anchoring.resolve(anchor, in: emoji) == .exact(range))
    }
}
