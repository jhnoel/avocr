import XCTest
import CoreGraphics
import PDFKit
import AppKit
@testable import AVOCRLib

final class PDFRendererTests: XCTestCase {

    // MARK: - renderPageToImage (CGContext rendering)

    func testRenderPageToImageReturnsValidCGImage() throws {
        let pdfURL = try createSinglePagePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))

        let image = PDFRenderer.renderPageToImage(page: page, dpi: 150)
        XCTAssertNotNil(image, "Should produce a valid CGImage")
    }

    func testRenderPageToImageDimensionsScaleWithDPI() throws {
        let pdfURL = try createSinglePagePDF(width: 612, height: 792) // US Letter
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))

        let bounds = page.bounds(for: .mediaBox)

        // At 72 DPI (1:1 with PDF points), pixel dimensions should match points
        let image72 = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 72))
        let scale72 = CGFloat(72) / 72.0
        XCTAssertEqual(image72.width, Int(ceil(bounds.width * scale72)))
        XCTAssertEqual(image72.height, Int(ceil(bounds.height * scale72)))

        // At 144 DPI, dimensions should double (within rounding)
        let image144 = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 144))
        let scale144 = CGFloat(144) / 72.0
        XCTAssertEqual(image144.width, Int(ceil(bounds.width * scale144)))
        XCTAssertEqual(image144.height, Int(ceil(bounds.height * scale144)))

        // At 300 DPI (default)
        let image300 = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 300))
        let scale300 = CGFloat(300) / 72.0
        XCTAssertEqual(image300.width, Int(ceil(bounds.width * scale300)))
        XCTAssertEqual(image300.height, Int(ceil(bounds.height * scale300)))
    }

    func testRenderPageToImageUsesNoneSkipLastAlpha() throws {
        let pdfURL = try createSinglePagePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 72))

        // noneSkipLast means no alpha channel — 4 bytes per pixel but alpha ignored
        XCTAssertEqual(image.alphaInfo, .noneSkipLast)
        XCTAssertEqual(image.bitsPerComponent, 8)
    }

    func testRenderPageToImageWhiteBackground() throws {
        // Create a PDF with no content — the rendered image should be white
        let pdfURL = try createSinglePagePDF(width: 10, height: 10)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 72))

        // Sample the top-left pixel to verify white background
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              CFDataGetLength(data) >= 4 else {
            XCTFail("Cannot access pixel data")
            return
        }
        let ptr = CFDataGetBytePtr(data)!
        // RGBX format: R=255, G=255, B=255
        XCTAssertEqual(ptr[0], 255, "Red channel should be 255 (white)")
        XCTAssertEqual(ptr[1], 255, "Green channel should be 255 (white)")
        XCTAssertEqual(ptr[2], 255, "Blue channel should be 255 (white)")
    }

    func testRenderPageToImageWithLandscapePage() throws {
        let pdfURL = try createSinglePagePDF(width: 792, height: 612) // Landscape
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = try XCTUnwrap(PDFRenderer.renderPageToImage(page: page, dpi: 72))

        XCTAssertEqual(image.width, 792)
        XCTAssertEqual(image.height, 612)
    }

    func testRenderPageToImageWithSmallPage() throws {
        let pdfURL = try createSinglePagePDF(width: 1, height: 1)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let image = PDFRenderer.renderPageToImage(page: page, dpi: 72)

        // 1pt at 72 DPI = 1px — should still render
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.width, 1)
        XCTAssertEqual(image?.height, 1)
    }

    // MARK: - pageCount (CGPDFDocument)

    func testPageCountReturnsSinglePage() throws {
        let pdfURL = try createSinglePagePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        XCTAssertEqual(PDFRenderer.pageCount(url: pdfURL), 1)
    }

    func testPageCountReturnsMultiplePages() throws {
        let pdfURL = try createMultiPagePDF(pageCount: 3)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        XCTAssertEqual(PDFRenderer.pageCount(url: pdfURL), 3)
    }

    func testPageCountReturnsNilForInvalidURL() {
        let invalid = URL(fileURLWithPath: "/nonexistent/fake.pdf")
        XCTAssertNil(PDFRenderer.pageCount(url: invalid))
    }

    func testPageCountReturnsNilForNonPDFFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let textFile = tempDir.appendingPathComponent("\(UUID().uuidString).txt")
        try "not a pdf".write(to: textFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFile) }

        XCTAssertNil(PDFRenderer.pageCount(url: textFile))
    }

    func testPageCountMatchesPDFDocumentPageCount() throws {
        let pdfURL = try createMultiPagePDF(pageCount: 5)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdfKitCount = PDFDocument(url: pdfURL)?.pageCount
        let cgPDFCount = PDFRenderer.pageCount(url: pdfURL)

        XCTAssertNotNil(pdfKitCount)
        XCTAssertNotNil(cgPDFCount)
        XCTAssertEqual(pdfKitCount, cgPDFCount,
                       "CGPDFDocument pageCount should match PDFDocument pageCount")
    }

    // MARK: - extractTextIfAvailable

    func testExtractTextIfAvailableReturnsNilForShortText() throws {
        let pdfURL = try createSinglePagePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(pdf.page(at: 0))

        // Minimal PDF has very short text ("Test") — below the 50 char threshold
        let text = PDFRenderer.extractTextIfAvailable(page: page)
        XCTAssertNil(text, "Short text should not be extracted (below minLength)")
    }

    // MARK: - Helpers

    private func createSinglePagePDF(width: CGFloat = 612, height: CGFloat = 792) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("\(UUID().uuidString).pdf")

        let image = makeTestImage(width: Int(width), height: Int(height))
        let nsImage = NSImage(cgImage: image, size: NSSize(width: width, height: height))
        let document = PDFDocument()
        if let page = PDFPage(image: nsImage) {
            document.insert(page, at: 0)
        }
        guard let data = document.dataRepresentation() else {
            throw OCRError.ocrFailed("Unable to create PDF")
        }
        try data.write(to: pdfURL)
        return pdfURL
    }

    private func createMultiPagePDF(pageCount: Int) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("\(UUID().uuidString).pdf")

        let image = makeTestImage(width: 100, height: 100)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: 100, height: 100))
        let document = PDFDocument()
        for i in 0..<pageCount {
            if let page = PDFPage(image: nsImage) {
                document.insert(page, at: i)
            }
        }
        guard let data = document.dataRepresentation() else {
            throw OCRError.ocrFailed("Unable to create PDF")
        }
        try data.write(to: pdfURL)
        return pdfURL
    }

    private func makeTestImage(width: Int = 10, height: Int = 10) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
