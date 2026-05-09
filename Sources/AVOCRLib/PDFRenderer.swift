import Foundation
import PDFKit
import CoreGraphics
import ImageIO
import AppKit

struct PDFRenderer {

    // MARK: - Searchable PDF generation

    /// Create a searchable PDF by overlaying invisible OCR text onto the original PDF pages.
    ///
    /// - Parameters:
    ///   - sourceURL: URL of the source PDF
    ///   - pageResults: OCR results per page (0-based page index + text blocks)
    ///   - outputURL: Where to write the searchable PDF
    static func createSearchablePDF(
        from sourceURL: URL,
        pageResults: [(pageIndex: Int, blocks: [TextBlock])],
        to outputURL: URL
    ) throws {
        guard let document = PDFDocument(url: sourceURL) else {
            throw OCRError.ocrFailed("Cannot open PDF: \(sourceURL.path)")
        }
        // Keep a second copy for drawing original page content.
        // Pages removed from `document` lose their document reference,
        // causing "Drawing a PDFPage when its PDFDocument is nil" warnings.
        guard let sourceForDrawing = PDFDocument(url: sourceURL) else {
            throw OCRError.ocrFailed("Cannot open PDF: \(sourceURL.path)")
        }

        let resultsByPage = Dictionary(pageResults.map { ($0.pageIndex, $0.blocks) }, uniquingKeysWith: { _, b in b })

        for pageIndex in 0..<document.pageCount {
            guard let blocks = resultsByPage[pageIndex], !blocks.isEmpty else { continue }
            guard let drawingPage = sourceForDrawing.page(at: pageIndex) else { continue }

            let overlayPage = SearchableTextPage(originalPage: drawingPage, textBlocks: blocks)
            document.removePage(at: pageIndex)
            document.insert(overlayPage, at: pageIndex)
        }

        if !document.write(to: outputURL) {
            throw OCRError.ocrFailed("Failed to write searchable PDF to \(outputURL.path)")
        }
    }

    static func extractTextIfAvailable(page: PDFPage, minLength: Int = 50) -> String? {
        guard let pageText = page.string else { return nil }
        let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > minLength else { return nil }
        return pageText
    }

    static func renderPageToImage(page: PDFPage, dpi: Int) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72.0
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // noneSkipLast: 8 bits per component, no alpha channel (RGBX).
        // bytesPerRow 0: let CoreGraphics pick optimal row alignment.
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Fill with white (PDFs may have transparent backgrounds)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale from points (72 dpi) to the target pixel dimensions
        context.scaleBy(x: scale, y: scale)

        // PDFPage.draw handles rotation, cropping, and coordinate transforms
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    static func loadPDF(url: URL) -> PDFDocument? {
        return PDFDocument(url: url)
    }

    static func extractTextFromPage(page: PDFPage) -> String? {
        return page.string
    }

    /// Lightweight page count using CGPDFDocument (avoids full PDFKit parsing).
    static func pageCount(url: URL) -> Int? {
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        return doc.numberOfPages
    }
}

// MARK: - SearchableTextPage

/// A PDFPage subclass that draws the original page content plus an invisible text overlay.
/// The invisible text makes the PDF searchable and selectable while preserving the original appearance.
final class SearchableTextPage: PDFPage {
    private let originalPage: PDFPage
    private let textBlocks: [TextBlock]

    init(originalPage: PDFPage, textBlocks: [TextBlock]) {
        self.originalPage = originalPage
        self.textBlocks = textBlocks
        super.init()
    }

    override func bounds(for box: PDFDisplayBox) -> CGRect {
        return originalPage.bounds(for: box)
    }

    override var rotation: Int {
        get { return originalPage.rotation }
        set { originalPage.rotation = newValue }
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        // Draw the original page content
        originalPage.draw(with: box, to: context)

        let pageBounds = originalPage.bounds(for: box)

        // Draw invisible text at OCR block positions
        // Vision returns normalized coordinates with origin at bottom-left
        // PDF coordinates also have origin at bottom-left, so we can map directly
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity

        let refSize: CGFloat = 12.0
        let refFont = CTFontCreateWithName("Helvetica" as CFString, refSize, nil)
        let refAttrs: [NSAttributedString.Key: Any] = [.font: refFont]
        var fontCache: [CGFloat: CTFont] = [:]

        for block in textBlocks {
            guard !block.text.isEmpty else { continue }

            let bbox = block.boundingBox
            // Map normalized (0-1) coordinates to page coordinates
            let x = bbox.origin.x * pageBounds.width + pageBounds.origin.x
            let y = bbox.origin.y * pageBounds.height + pageBounds.origin.y
            let targetWidth = bbox.width * pageBounds.width
            let targetHeight = bbox.height * pageBounds.height

            // Calculate font size so rendered text width ≈ bounding box width.
            // Avoids text-matrix horizontal scaling, which causes tools like
            // pdftotext to insert spurious spaces between characters.
            let refStr = NSAttributedString(string: block.text, attributes: refAttrs)
            let refLine = CTLineCreateWithAttributedString(refStr)
            let refWidth = CGFloat(CTLineGetTypographicBounds(refLine, nil, nil, nil))

            let fontSize: CGFloat
            if refWidth > 0 {
                fontSize = max(1, refSize * targetWidth / refWidth)
            } else {
                fontSize = max(1, targetHeight)
            }

            let fontKey = (fontSize * 4).rounded() / 4
            let font: CTFont
            if let cachedFont = fontCache[fontKey] {
                font = cachedFont
            } else {
                let newFont = CTFontCreateWithName("Helvetica" as CFString, fontKey, nil)
                fontCache[fontKey] = newFont
                font = newFont
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: block.text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)

            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }

        context.restoreGState()
    }
}
