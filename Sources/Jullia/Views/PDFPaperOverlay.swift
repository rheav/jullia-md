import AppKit
import CoreImage
import JulliaCore
import PDFKit

extension PDFPaper {
    /// Turns a white page into this paper. The colour space has to be named: without it the paper comes out grey.
    var filter: CIFilter? {
        CIFilter(name: "CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": PDFRecolor.cubeDimension,
            "inputCubeData": PDFRecolor.cube(for: self),
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }
}

/// Recolours the pages on screen from above, after PDFKit has painted them. PDFKit paints selections and highlights
/// last, in multiply, which vanishes on a page already dark; from above they change colour with the page. The document
/// is left as it is, so printing gives the original pages. The overlay stays outside PDFKit's clip view: under the clip
/// view's zoom a background filter reads the page at its unzoomed size and the text blurs.
final class PDFPaperOverlay: NSView {
    private let mask = CAShapeLayer()
    private var surveys: [PDFPage: PDFPageSurvey] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        mask.fillRule = .evenOdd
        layer?.mask = mask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks and drags belong to the pages underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ filter: CIFilter?) {
        layer?.backgroundFilters = filter.map { [$0] } ?? []
    }

    /// Lets the filter through on `pages`, where `view` shows them, around the pictures that keep their pixels.
    func cover(_ pages: [PDFPage], in view: PDFView) {
        let path = CGMutablePath()
        for page in pages {
            let survey = surveys[page] ?? PDFPageSurvey(page: page)
            surveys[page] = survey
            guard survey.recolors else { continue }
            let rects = [page.bounds(for: .cropBox)] + survey.picturesOnPage
            path.addRects(rects.map { convert(view.convert($0, from: page), from: view) })
        }
        // The pages move in this same frame; an animated mask would trail them.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = bounds
        mask.path = path
        CATransaction.commit()
    }

    func forgetPages() {
        surveys.removeAll()
    }
}

@MainActor private let thumbnailContext = CIContext()

extension PDFPage {
    /// A thumbnail in the colours the reader sees on `paper`.
    @MainActor func thumbnail(of size: NSSize, on paper: PDFPaper?) -> NSImage {
        let image = thumbnail(of: size, for: .cropBox)
        guard let filter = paper?.filter else { return image }
        let survey = PDFPageSurvey(page: self)
        guard survey.recolors, let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        filter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let output = filter.outputImage,
              let dark = thumbnailContext.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: sRGB) else { return image }
        guard !survey.pictures.isEmpty, let context = CGContext(
            data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return NSImage(cgImage: dark, size: size) }
        let canvas = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.draw(dark, in: canvas)
        let scale = CGFloat(source.width) / survey.size.width
        context.clip(to: survey.pictures.map { $0.applying(CGAffineTransform(scaleX: scale, y: scale)) })
        context.draw(source, in: canvas)
        return context.makeImage().map { NSImage(cgImage: $0, size: size) } ?? image
    }
}
