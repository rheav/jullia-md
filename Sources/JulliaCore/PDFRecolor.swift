import Foundation

/// One dark look for a PDF's pages: white paper becomes `paper`, black ink becomes `ink`.
public struct PDFPaper: Hashable, Sendable, Identifiable {
    public var name: String
    public var paper: RGBA
    public var ink: RGBA

    public var id: String { name }

    public init(name: String, paper: RGBA, ink: RGBA) {
        self.name = name
        self.paper = paper
        self.ink = ink
    }
}

/// Turns the colours of a white page into a dark one, in OKLab so a colour keeps its hue. Plain inversion gives pure
/// black at 21:1 and swaps the colours; a lightness ramp sinks mid-tones like red into the paper.
public enum PDFRecolor {
    /// Points per axis of the colour cube. 33 cost a third of the frame rate while scrolling, for the same colours.
    public static let cubeDimension = 17

    private static let maxChroma = 0.14
    /// Saturated colours would sink into the page; they get this much more lightness.
    private static let saturatedLift = 0.07

    public static func map(_ color: RGBA, on target: PDFPaper) -> RGBA {
        let lab = oklab(color), paper = oklab(target.paper), ink = oklab(target.ink)
        let lightness = min(max(lab.L, 0), 1)
        // Past linear, so mid-tones reach further from the paper than their share of black.
        let inked = 1 - lightness * lightness
        let chroma = hypot(lab.a, lab.b)
        let L = min(ink.L, paper.L + (ink.L - paper.L) * inked + saturatedLift * min(1, chroma / 0.2))
        let tintA = paper.a + (ink.a - paper.a) * inked, tintB = paper.b + (ink.b - paper.b) * inked
        guard chroma > 1e-5 else { return srgb(L, tintA, tintB) }
        let directionA = lab.a / chroma, directionB = lab.b / chroma
        // Barely tinted greys follow the paper's own tint.
        let neutral = max(0, 1 - chroma / 0.04)
        var limited = maxChroma * (1 - exp(-chroma / maxChroma))
        var linear = (0.0, 0.0, 0.0)
        for _ in 0..<24 {
            linear = linearRGB(L, directionA * limited + tintA * neutral, directionB * limited + tintB * neutral)
            if [linear.0, linear.1, linear.2].allSatisfy({ (-0.0005)...1.0005 ~= $0 }) { break }
            limited *= 0.93
        }
        return RGBA(red: encoded(linear.0), green: encoded(linear.1), blue: encoded(linear.2))
    }

    /// The colour table `CIColorCubeWithColorSpace` reads: RGBA floats, red the fastest axis, in sRGB.
    public static func cube(for paper: PDFPaper) -> Data {
        let size = cubeDimension, last = Double(size - 1)
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 4)
        for blue in 0..<size {
            for green in 0..<size {
                for red in 0..<size {
                    let color = map(RGBA(red: Double(red) / last, green: Double(green) / last, blue: Double(blue) / last), on: paper)
                    values += [Float(color.red), Float(color.green), Float(color.blue), 1]
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decoded(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    private static func oklab(_ color: RGBA) -> (L: Double, a: Double, b: Double) {
        let red = decoded(color.red), green = decoded(color.green), blue = decoded(color.blue)
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func linearRGB(_ L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let l = L + 0.3963377774 * a + 0.2158037573 * b
        let m = L - 0.1055613458 * a - 0.0638541728 * b
        let s = L - 0.0894841775 * a - 1.2914855480 * b
        let (l3, m3, s3) = (l * l * l, m * m * m, s * s * s)
        return (4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
    }

    private static func srgb(_ L: Double, _ a: Double, _ b: Double) -> RGBA {
        let linear = linearRGB(L, a, b)
        return RGBA(red: encoded(linear.0), green: encoded(linear.1), blue: encoded(linear.2))
    }
}
