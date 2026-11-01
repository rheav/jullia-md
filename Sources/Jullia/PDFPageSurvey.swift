import CoreGraphics
import PDFKit

/// What dark paper may touch on a page. A page already dark, or nearly all picture, keeps its pixels; so do the photos
/// on a page of text. A screenshot of a table is light and flat like the paper around it, so it darkens with the page.
struct PDFPageSurvey: Equatable {
    var recolors: Bool
    /// Pictures that keep their pixels, where the page shows them: from its lower left corner, with its rotation.
    var pictures: [CGRect]
    /// The page as shown, with its rotation.
    var size: CGSize

    private static let paperMedian = 200
    private static let pictureArea: CGFloat = 400

    init(page: PDFPage) {
        let transform = page.transform(for: .cropBox)
        let shown = page.bounds(for: .cropBox).applying(transform)
        size = shown.size
        guard let tones = Tones(page: page, size: shown.size) else {
            recolors = false
            pictures = []
            return
        }
        let whole = tones.measure(CGRect(origin: .zero, size: shown.size))
        recolors = whole.median >= Self.paperMedian && whole.midTones < 0.55
        guard recolors else {
            pictures = []
            return
        }
        pictures = PDFImageScan.rects(on: page)
            .map { $0.applying(transform).offsetBy(dx: -shown.minX, dy: -shown.minY) }
            .filter { rect in
                guard rect.width * rect.height >= Self.pictureArea else { return false }
                let picture = tones.measure(rect)
                return picture.median < Self.paperMedian || picture.midTones >= 0.45
            }
    }
}

/// The page's lightness at a small size, read region by region.
private struct Tones {
    private let width: Int, height: Int, scale: CGFloat
    private let pixels: [UInt8]

    init?(page: PDFPage, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return nil }
        width = 240
        scale = CGFloat(width) / size.width
        height = max(1, Int(size.height * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// The median lightness in `rect` and the share of it neither near white nor near black.
    func measure(_ rect: CGRect) -> (median: Int, midTones: Double) {
        let left = max(0, Int(rect.minX * scale)), right = min(width, Int(rect.maxX * scale))
        let top = max(0, height - Int(rect.maxY * scale)), bottom = min(height, height - Int(rect.minY * scale))
        guard right > left, bottom > top else { return (0, 1) }
        var histogram = [Int](repeating: 0, count: 256)
        var midTones = 0
        for y in top..<bottom {
            for x in left..<right {
                let offset = (y * width + x) * 4
                let luma = (54 * Int(pixels[offset]) + 183 * Int(pixels[offset + 1]) + 19 * Int(pixels[offset + 2])) / 256
                histogram[luma] += 1
                if luma > 40, luma < 215 { midTones += 1 }
            }
        }
        let count = (right - left) * (bottom - top)
        var seen = 0
        let median = histogram.firstIndex { value in
            seen += value
            return seen >= count / 2
        } ?? 0
        return (median, Double(midTones) / Double(count))
    }
}

/// Where a page's images are: its content stream's `Do` operators under the running transform, into its forms too.
private final class PDFImageScan {
    private static let maxFormDepth = 8

    private var transform = CGAffineTransform.identity
    private var saved: [CGAffineTransform] = []
    private var streams: [CGPDFContentStreamRef] = []
    private var rects: [CGRect] = []

    static func rects(on page: PDFPage) -> [CGRect] {
        guard let reference = page.pageRef else { return [] }
        let scan = PDFImageScan()
        scan.read(CGPDFContentStreamCreateWithPage(reference))
        return scan.rects
    }

    private func read(_ stream: CGPDFContentStreamRef) {
        streams.append(stream)
        let scanner = CGPDFScannerCreate(stream, Self.operators, Unmanaged.passUnretained(self).toOpaque())
        CGPDFScannerScan(scanner)
        streams.removeLast()
    }

    private static func scan(_ info: UnsafeMutableRawPointer?) -> PDFImageScan {
        Unmanaged<PDFImageScan>.fromOpaque(info!).takeUnretainedValue()
    }

    nonisolated(unsafe) private static let operators: CGPDFOperatorTableRef = {
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let scan = PDFImageScan.scan(info)
            scan.saved.append(scan.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let scan = PDFImageScan.scan(info)
            if let transform = scan.saved.popLast() { scan.transform = transform }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
            }
            let scan = PDFImageScan.scan(info)
            scan.transform = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
                .concatenating(scan.transform)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in PDFImageScan.scan(info).place(from: scanner) }
        return table
    }()

    private func place(from scanner: CGPDFScannerRef) {
        var name: UnsafePointer<CChar>?
        var object: CGPDFStreamRef?
        var subtype: UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner, &name), let name, let content = streams.last,
              let resource = CGPDFContentStreamGetResource(content, "XObject", name),
              CGPDFObjectGetValue(resource, .stream, &object), let object,
              let dictionary = CGPDFStreamGetDictionary(object),
              CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
        if strcmp(subtype, "Image") == 0 {
            rects.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(transform))
        } else if strcmp(subtype, "Form") == 0, streams.count < Self.maxFormDepth {
            enter(form: object, dictionary: dictionary, in: content)
        }
    }

    private func enter(form: CGPDFStreamRef, dictionary: CGPDFDictionaryRef, in content: CGPDFContentStreamRef) {
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return }
        let outer = transform
        defer { transform = outer }
        var matrix: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrix), let matrix, CGPDFArrayGetCount(matrix) == 6 {
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in 0..<6 { _ = CGPDFArrayGetNumber(matrix, index, &values[index]) }
            transform = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
                .concatenating(transform)
        }
        read(CGPDFContentStreamCreateWithStream(form, resources, content))
    }
}
