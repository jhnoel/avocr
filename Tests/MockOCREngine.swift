import Foundation
import CoreGraphics
@testable import AVOCRLib

struct MockOCREngine: OCREngineProtocol {
    var performOCRHandler: (CGImage, OCRConfig, String, Int?) throws -> OCRResult
    var loadImageHandler: (URL) throws -> CGImage

    init(
        performOCRHandler: @escaping (CGImage, OCRConfig, String, Int?) throws -> OCRResult,
        loadImageHandler: @escaping (URL) throws -> CGImage
    ) {
        self.performOCRHandler = performOCRHandler
        self.loadImageHandler = loadImageHandler
    }

    func performOCR(
        image: CGImage,
        config: OCRConfig,
        path: String,
        page: Int?
    ) throws -> OCRResult {
        try performOCRHandler(image, config, path, page)
    }

    func loadImage(url: URL) throws -> CGImage {
        try loadImageHandler(url)
    }
}
