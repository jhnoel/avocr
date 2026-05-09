import XCTest
import CoreGraphics
import PDFKit
import Vision
import AppKit
@testable import AVOCRLib

final class OCRProcessorTests: XCTestCase {
    func testProcessImageUsesEngineAndReturnsResult() throws {
        let testImage = makeTestImage()
        var receivedPath: String?
        var receivedPage: Int?

        let engine = MockOCREngine(
            performOCRHandler: { image, config, path, page in
                XCTAssertEqual(image.width, testImage.width)
                XCTAssertEqual(config.languages, ["en-US"])
                receivedPath = path
                receivedPage = page
                return OCRResult(text: "Hello", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: "/tmp/sample.jpg", page: nil)
        let result = try processor.process(
            item: item,
            config: makeConfig(),
            dpi: 300,
            pdfTextExtraction: .forceOCR,
            retryPolicy: .none
        )

        XCTAssertEqual(receivedPath, item.path)
        XCTAssertNil(receivedPage)
        XCTAssertEqual(result.text, "Hello")
        XCTAssertFalse(result.usedExistingText)
        XCTAssertEqual(result.path, item.path)
    }

    func testProcessPDFPageUsesOCRWhenNoExtractedText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("sample.pdf")
        try createTestPDF(at: pdfURL)

        let testImage = makeTestImage()
        var receivedPage: Int?

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                receivedPage = page
                return OCRResult(text: "PDF OCR", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 1, path: pdfURL.path, page: 0)
        let result = try processor.process(
            item: item,
            config: makeConfig(),
            dpi: 72,
            pdfTextExtraction: .auto,
            retryPolicy: .none
        )

        XCTAssertEqual(receivedPage, 0)
        XCTAssertEqual(result.text, "PDF OCR")
        XCTAssertFalse(result.usedExistingText)
        XCTAssertEqual(result.page, 0)
    }

    func testRetryPolicyRetriesOnVisionErrors() throws {
        let testImage = makeTestImage()
        var attempts = 0
        var retryMessages: [String] = []

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                attempts += 1
                if attempts < 3 {
                    throw NSError(domain: VNErrorDomain, code: 1)
                }
                return OCRResult(text: "Recovered", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine, retryHandler: { message in
            retryMessages.append(message)
        })

        let item = WorkItem(id: 2, path: "/tmp/retry.jpg", page: nil)
        let result = try processor.process(
            item: item,
            config: makeConfig(),
            dpi: 300,
            pdfTextExtraction: .forceOCR,
            retryPolicy: RetryPolicy(maxAttempts: 3, backoffMultiplier: 1.0, initialDelay: 0)
        )

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(retryMessages.count, 2)
        XCTAssertEqual(result.text, "Recovered")
    }

    func testRetryPolicyDoesNotRetryOnOCRError() {
        let testImage = makeTestImage()
        var attempts = 0

        let engine = MockOCREngine(
            performOCRHandler: { _, _, _, _ in
                attempts += 1
                throw OCRError.ocrFailed("No retry")
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 3, path: "/tmp/fail.jpg", page: nil)

        XCTAssertThrowsError(
            try processor.process(
                item: item,
                config: makeConfig(),
                dpi: 300,
                pdfTextExtraction: .forceOCR,
                retryPolicy: RetryPolicy(maxAttempts: 3, backoffMultiplier: 1.0, initialDelay: 0)
            )
        ) { error in
            XCTAssertTrue(error is OCRError)
        }

        XCTAssertEqual(attempts, 1)
    }

    // MARK: - Two-phase API (prepare / processOCR)

    func testPrepareImageReturnsImagePreparedItem() throws {
        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: "/tmp/test.jpg", page: nil)

        let prepared = try processor.prepare(
            item: item,
            dpi: 300,
            pdfTextExtraction: .forceOCR
        )

        if case .image(let image, let preparedItem) = prepared {
            XCTAssertEqual(image.width, testImage.width)
            XCTAssertEqual(image.height, testImage.height)
            XCTAssertEqual(preparedItem.path, item.path)
            XCTAssertNil(preparedItem.page)
        } else {
            XCTFail("Expected .image prepared item for image files")
        }
    }

    func testPreparePDFPageReturnsImageWhenForceOCR() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("test.pdf")
        try createTestPDF(at: pdfURL)

        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: pdfURL.path, page: 0)

        let prepared = try processor.prepare(
            item: item,
            dpi: 72,
            pdfTextExtraction: .forceOCR
        )

        if case .image(let image, let preparedItem) = prepared {
            XCTAssertGreaterThan(image.width, 0)
            XCTAssertGreaterThan(image.height, 0)
            XCTAssertEqual(preparedItem.page, 0)
        } else {
            XCTFail("Expected .image prepared item when forceOCR is set")
        }
    }

    func testProcessOCRWithImagePreparedItem() throws {
        let testImage = makeTestImage()
        var ocrCalled = false

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                ocrCalled = true
                return OCRResult(
                    text: "OCR result",
                    blocks: [TextBlock(text: "OCR result", confidence: 0.95, boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1))],
                    path: path,
                    page: page
                )
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 5, path: "/tmp/test.jpg", page: nil)
        let prepared = OCRProcessor.PreparedItem.image(testImage, item)

        let result = try processor.processOCR(
            prepared: prepared,
            config: makeConfig(),
            retryPolicy: .none
        )

        XCTAssertTrue(ocrCalled, "OCR engine should be called for image items")
        XCTAssertEqual(result.text, "OCR result")
        XCTAssertEqual(result.blocks.count, 1)
        XCTAssertFalse(result.usedExistingText)
        XCTAssertEqual(result.path, "/tmp/test.jpg")
        XCTAssertNil(result.page)
    }

    func testProcessOCRWithExtractedTextSkipsEngine() throws {
        let testImage = makeTestImage()
        var ocrCalled = false

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                ocrCalled = true
                return OCRResult(text: "should not reach", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 7, path: "/tmp/doc.pdf", page: 2)
        let prepared = OCRProcessor.PreparedItem.extractedText("Existing PDF text content", item)

        let result = try processor.processOCR(
            prepared: prepared,
            config: makeConfig(),
            retryPolicy: .none
        )

        XCTAssertFalse(ocrCalled, "OCR engine should NOT be called for extracted text")
        XCTAssertEqual(result.text, "Existing PDF text content")
        XCTAssertTrue(result.blocks.isEmpty)
        XCTAssertTrue(result.usedExistingText)
        XCTAssertEqual(result.path, "/tmp/doc.pdf")
        XCTAssertEqual(result.page, 2)
    }

    func testTwoPhaseMatchesSinglePhaseForImages() throws {
        let testImage = makeTestImage()
        let blocks = [TextBlock(text: "Hello", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))]

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "Hello", blocks: blocks, path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: "/tmp/test.jpg", page: nil)
        let config = makeConfig()

        // Single-step
        let singleResult = try processor.process(
            item: item,
            config: config,
            dpi: 300,
            pdfTextExtraction: .forceOCR,
            retryPolicy: .none
        )

        // Two-phase
        let prepared = try processor.prepare(
            item: item,
            dpi: 300,
            pdfTextExtraction: .forceOCR
        )
        let twoPhaseResult = try processor.processOCR(
            prepared: prepared,
            config: config,
            retryPolicy: .none
        )

        XCTAssertEqual(singleResult.text, twoPhaseResult.text)
        XCTAssertEqual(singleResult.path, twoPhaseResult.path)
        XCTAssertEqual(singleResult.page, twoPhaseResult.page)
        XCTAssertEqual(singleResult.usedExistingText, twoPhaseResult.usedExistingText)
        XCTAssertEqual(singleResult.blocks.count, twoPhaseResult.blocks.count)
    }

    func testTwoPhaseMatchesSinglePhaseForPDF() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("test.pdf")
        try createTestPDF(at: pdfURL)

        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "PDF text", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: pdfURL.path, page: 0)
        let config = makeConfig()

        let singleResult = try processor.process(
            item: item,
            config: config,
            dpi: 72,
            pdfTextExtraction: .forceOCR,
            retryPolicy: .none
        )

        let prepared = try processor.prepare(
            item: item,
            dpi: 72,
            pdfTextExtraction: .forceOCR
        )
        let twoPhaseResult = try processor.processOCR(
            prepared: prepared,
            config: config,
            retryPolicy: .none
        )

        XCTAssertEqual(singleResult.text, twoPhaseResult.text)
        XCTAssertEqual(singleResult.path, twoPhaseResult.path)
        XCTAssertEqual(singleResult.page, twoPhaseResult.page)
        XCTAssertEqual(singleResult.usedExistingText, twoPhaseResult.usedExistingText)
    }

    func testProcessOCRRetriesOnVisionError() throws {
        let testImage = makeTestImage()
        var attempts = 0

        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                attempts += 1
                if attempts < 2 {
                    throw NSError(domain: VNErrorDomain, code: 1)
                }
                return OCRResult(text: "Recovered", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: "/tmp/test.jpg", page: nil)
        let prepared = OCRProcessor.PreparedItem.image(testImage, item)

        let result = try processor.processOCR(
            prepared: prepared,
            config: makeConfig(),
            retryPolicy: RetryPolicy(maxAttempts: 3, backoffMultiplier: 1.0, initialDelay: 0)
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(result.text, "Recovered")
    }

    func testPrepareThrowsForInvalidPDFPath() {
        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: "/nonexistent/fake.pdf", page: 0)

        XCTAssertThrowsError(
            try processor.prepare(
                item: item,
                dpi: 300,
                pdfTextExtraction: .forceOCR
            )
        )
    }

    func testPrepareThrowsForInvalidPageIndex() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("test.pdf")
        try createTestPDF(at: pdfURL) // Single-page PDF

        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(engine: engine)
        let item = WorkItem(id: 0, path: pdfURL.path, page: 99) // Page out of range

        XCTAssertThrowsError(
            try processor.prepare(
                item: item,
                dpi: 72,
                pdfTextExtraction: .forceOCR
            )
        )
    }

    func testPreparePDFCacheIsUsedAcrossCalls() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("test.pdf")
        try createTestPDF(at: pdfURL)

        let testImage = makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                OCRResult(text: "", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in testImage }
        )

        let processor = OCRProcessor(enablePDFCache: true, engine: engine)

        // Prepare page 0 — loads PDF into cache
        let prepared0 = try processor.prepare(
            item: WorkItem(id: 0, path: pdfURL.path, page: 0),
            dpi: 72,
            pdfTextExtraction: .forceOCR
        )

        // Delete the PDF file — cached copy should still work for same path
        try FileManager.default.removeItem(at: pdfURL)

        // Prepare same path again — should use cached PDFDocument
        // (If cache wasn't working, this would throw because the file is gone)
        // Note: page 0 exists so this should succeed from cache
        let prepared0Again = try processor.prepare(
            item: WorkItem(id: 1, path: pdfURL.path, page: 0),
            dpi: 72,
            pdfTextExtraction: .forceOCR
        )

        // Both should produce valid image items
        if case .image(_, _) = prepared0 {} else { XCTFail("Expected .image") }
        if case .image(_, _) = prepared0Again {} else { XCTFail("Expected .image from cache") }
    }
}

private func makeConfig() -> OCRConfig {
    OCRConfig(
        fast: false,
        languages: ["en-US"],
        noCorrection: false,
        minTextHeight: nil,
        roi: nil,
        columnMode: .auto
    )
}

private func makeTestImage() -> CGImage {
    let size = CGSize(width: 10, height: 10)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: Int(size.width) * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    )
    context?.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context?.fill(CGRect(origin: .zero, size: size))

    guard let image = context?.makeImage() else {
        XCTFail("Failed to create test image")
        return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo, provider: CGDataProvider(data: Data(count: 4) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    return image
}

private func createTestPDF(at url: URL) throws {
    let image = makeTestImage()
    let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    let page = PDFPage(image: nsImage)
    let document = PDFDocument()
    if let page = page {
        document.insert(page, at: 0)
    }

    guard let data = document.dataRepresentation() else {
        throw OCRError.ocrFailed("Unable to create PDF")
    }
    try data.write(to: url)
}
