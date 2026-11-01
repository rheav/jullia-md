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

/// Recolours one page from above, after PDFKit has painted it. PDFKit paints selections and highlights last, in
/// multiply, which vanishes on a page already dark; from above they change colour with the page. The document is left
/// as it is, so printing gives the original pages.
final class PDFPaperOverlay: NSView {
    private let page: PDFPage
    private var survey: PDFPageSurvey?

    init(page: PDFPage) {
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks and drags belong to the page underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ filter: CIFilter?) {
        guard let filter else {
            layer?.backgroundFilters = []
            return
        }
        let survey = survey ?? PDFPageSurvey(page: page)
        self.survey = survey
        layer?.backgroundFilters = survey.recolors ? [filter] : []
        layer?.mask = survey.unrotatedPictures.isEmpty ? nil
            : Self.mask(size: page.bounds(for: .cropBox).size, cutting: survey.unrotatedPictures)
    }

    private static func mask(size: CGSize, cutting pictures: [CGRect]) -> CAShapeLayer {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRects(pictures)
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: size)
        mask.path = path
        mask.fillRule = .evenOdd
        return mask
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
