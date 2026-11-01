import Foundation
import Testing
@testable import JulliaCore

@Suite struct PDFRecolorTests {
    private static let papers = Theme.polar.pdfPapers + Theme.ink.pdfPapers

    private func close(_ a: RGBA, _ b: RGBA, within tolerance: Double = 1.5 / 255) -> Bool {
        abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance && abs(a.blue - b.blue) <= tolerance
    }

    private func luminance(_ c: RGBA) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    private func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func whiteBecomesThePaperAndBlackTheInk() {
        for paper in Self.papers {
            #expect(close(PDFRecolor.map(RGBA(0xFFFFFF), on: paper), paper.paper), "\(paper.name)")
            #expect(close(PDFRecolor.map(RGBA(0x000000), on: paper), paper.ink), "\(paper.name)")
        }
    }

    @Test func redTextStaysReadableOnEveryPaper() {
        for paper in Self.papers {
            let red = PDFRecolor.map(RGBA(0xFF0000), on: paper)
            #expect(contrast(red, paper.paper) >= 4.5, "\(paper.name)")
        }
    }

    @Test func colourKeepsItsHue() {
        for paper in Self.papers {
            let red = PDFRecolor.map(RGBA(0xFF0000), on: paper)
            #expect(red.red > red.green + 0.2 && red.red > red.blue + 0.2, "\(paper.name)")
            let yellow = PDFRecolor.map(RGBA(0xFFFF00), on: paper)
            #expect(yellow.red > yellow.blue + 0.1 && yellow.green > yellow.blue + 0.1, "\(paper.name)")
            let green = PDFRecolor.map(RGBA(0xD9EAD3), on: paper)
            #expect(green.green > green.red && green.green > green.blue, "\(paper.name)")
        }
    }

    @Test func highlightFillsStayApartFromEachOtherAndFromThePaper() {
        for paper in Self.papers {
            let yellow = PDFRecolor.map(RGBA(0xFFFF00), on: paper)
            let cream = PDFRecolor.map(RGBA(0xFFF2CC), on: paper)
            #expect(!close(yellow, cream, within: 0.03), "\(paper.name)")
            #expect(contrast(yellow, paper.paper) > 1.2, "\(paper.name)")
            #expect(contrast(cream, paper.paper) > 1.15, "\(paper.name)")
            // The document's black text stays readable on its own highlights.
            #expect(contrast(paper.ink, yellow) >= 4.5, "\(paper.name)")
            #expect(contrast(paper.ink, cream) >= 4.5, "\(paper.name)")
        }
    }

    @Test func greysGetLighterAsTheyGetDarker() throws {
        let paper = try #require(Theme.polar.pdfPapers.first)
        var previous = -1.0
        for step in stride(from: 255, through: 0, by: -15) {
            let grey = UInt32(step) << 16 | UInt32(step) << 8 | UInt32(step)
            let value = luminance(PDFRecolor.map(RGBA(grey), on: paper))
            #expect(value > previous)
            previous = value
        }
    }

    @Test func cubeIsWhatCoreImageReads() throws {
        let paper = try #require(Theme.polar.pdfPapers.first)
        let data = PDFRecolor.cube(for: paper)
        let size = PDFRecolor.cubeDimension
        #expect(size == 17)
        #expect(data.count == size * size * size * 4 * MemoryLayout<Float>.size)
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        func entry(_ red: Int, _ green: Int, _ blue: Int) -> RGBA {
            let i = (blue * size * size + green * size + red) * 4
            return RGBA(red: Double(floats[i]), green: Double(floats[i + 1]), blue: Double(floats[i + 2]))
        }
        #expect(close(entry(0, 0, 0), paper.ink))
        #expect(close(entry(16, 16, 16), paper.paper))
        // Red is the fastest axis: full red alone is the second-to-last colour of its row, not of the column.
        #expect(close(entry(16, 0, 0), PDFRecolor.map(RGBA(0xFF0000), on: paper)))
        #expect(floats[3] == 1)
    }

    @Test func darkThemesHaveFourPapersAndLightThemesNone() {
        #expect(Theme.polar.pdfPapers.map(\.name) == ["Contínuo", "Nord", "Painel", "Suave"])
        #expect(Theme.ink.pdfPapers.map(\.name) == ["Contínuo", "Grafite", "Painel", "Suave"])
        #expect(Theme.polar.pdfPapers[1].paper == RGBA(0x2E3440))
        #expect(Theme.polar.pdfPapers[2].paper == Theme.polar.surface)
        #expect(Theme.ink.pdfPapers[2].paper == Theme.ink.surface)
        #expect(Theme.snow.pdfPapers.isEmpty)
        #expect(Theme.paper.pdfPapers.isEmpty)
    }

    @Test func aToneOutOfRangeFallsOnAPaper() {
        #expect(Theme.polar.pdfPaper(2)?.name == "Painel")
        #expect(Theme.polar.pdfPaper(-3)?.name == "Contínuo")
        #expect(Theme.polar.pdfPaper(99)?.name == "Suave")
        #expect(Theme.snow.pdfPaper(2) == nil)
    }
}
