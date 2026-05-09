import XCTest
import Vision
import CoreGraphics
@testable import AVOCRLib

final class RetryPolicyTests: XCTestCase {
    func testRetriesTransientErrorsThenSucceeds() throws {
        var attempts = 0
        let image = Self.makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, path, page in
                attempts += 1
                if attempts < 3 {
                    throw NSError(domain: VNErrorDomain, code: 1, userInfo: nil)
                }
                return OCRResult(text: "ok", blocks: [], path: path, page: page)
            },
            loadImageHandler: { _ in image }
        )
        var retryMessages: [String] = []
        let processor = OCRProcessor(engine: engine, retryHandler: { retryMessages.append($0) })

        let result = try processor.process(
            item: WorkItem(id: 1, path: "/tmp/test.png", page: nil),
            config: Self.makeConfig(),
            dpi: 300,
            pdfTextExtraction: .forceOCR,
            retryPolicy: RetryPolicy(maxAttempts: 3, backoffMultiplier: 1, initialDelay: 0)
        )

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(retryMessages.count, 2)
        XCTAssertEqual(result.text, "ok")
    }

    func testDoesNotRetryNonTransientErrors() {
        var attempts = 0
        let image = Self.makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, _, _ in
                attempts += 1
                throw OCRError.ocrFailed("boom")
            },
            loadImageHandler: { _ in image }
        )
        let processor = OCRProcessor(engine: engine)

        XCTAssertThrowsError(
            try processor.process(
                item: WorkItem(id: 2, path: "/tmp/fail.png", page: nil),
                config: Self.makeConfig(),
                dpi: 300,
                pdfTextExtraction: .forceOCR,
                retryPolicy: RetryPolicy(maxAttempts: 3, backoffMultiplier: 1, initialDelay: 0)
            )
        ) { error in
            XCTAssertTrue(error is OCRError)
        }
        XCTAssertEqual(attempts, 1)
    }

    func testStopsAfterMaxAttempts() {
        var attempts = 0
        let image = Self.makeTestImage()
        let engine = MockOCREngine(
            performOCRHandler: { _, _, _, _ in
                attempts += 1
                throw NSError(domain: VNErrorDomain, code: 2, userInfo: nil)
            },
            loadImageHandler: { _ in image }
        )
        let processor = OCRProcessor(engine: engine)

        XCTAssertThrowsError(
            try processor.process(
                item: WorkItem(id: 3, path: "/tmp/retry.png", page: nil),
                config: Self.makeConfig(),
                dpi: 300,
                pdfTextExtraction: .forceOCR,
                retryPolicy: RetryPolicy(maxAttempts: 2, backoffMultiplier: 1, initialDelay: 0)
            )
        )
        XCTAssertEqual(attempts, 2)
    }

    private static func makeConfig() -> OCRConfig {
        OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
    }

    private static func makeTestImage() -> CGImage {
        let width = 10
        let height = 10
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
        )
        context?.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage() ?? CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: CGDataProvider(data: Data(count: width * height * 4) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
