import Foundation
import Vision
import CoreGraphics
import ImageIO

public struct OCRConfig {
    public let fast: Bool
    public let languages: [String]
    public let noCorrection: Bool
    public let minTextHeight: Float?
    public let roi: CGRect?
    public let columnMode: ColumnMode
    
    public init(
        fast: Bool,
        languages: [String],
        noCorrection: Bool,
        minTextHeight: Float?,
        roi: CGRect?,
        columnMode: ColumnMode
    ) {
        self.fast = fast
        self.languages = languages
        self.noCorrection = noCorrection
        self.minTextHeight = minTextHeight
        self.roi = roi
        self.columnMode = columnMode
    }
}

public struct OCRResult {
    public let text: String
    public let blocks: [TextBlock]
    public let path: String
    public let page: Int?
    
    public init(text: String, blocks: [TextBlock], path: String, page: Int?) {
        self.text = text
        self.blocks = blocks
        self.path = path
        self.page = page
    }
}

public protocol OCREngineProtocol {
    func performOCR(
        image: CGImage,
        config: OCRConfig,
        path: String,
        page: Int?
    ) throws -> OCRResult
    
    func loadImage(url: URL) throws -> CGImage
}

public struct AVOCREngine: OCREngineProtocol {
    public init() {}
    
    public func performOCR(
        image: CGImage,
        config: OCRConfig,
        path: String,
        page: Int? = nil
    ) throws -> OCRResult {
        // Create request
        let request = VNRecognizeTextRequest()

        // Configure request
        request.recognitionLevel = config.fast ? .fast : .accurate
        request.recognitionLanguages = config.languages
        request.usesLanguageCorrection = !config.noCorrection

        if let minHeight = config.minTextHeight {
            request.minimumTextHeight = minHeight
        }

        if let roi = config.roi {
            request.regionOfInterest = roi
        }

        // Create handler and perform request
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        // Extract results
        guard let observations = request.results else {
            return OCRResult(text: "", blocks: [], path: path, page: page)
        }

        // Sort and format text
        let (text, blocks) = ReadingOrder.sortAndFormat(
            observations: observations,
            columnMode: config.columnMode
        )

        return OCRResult(
            text: text,
            blocks: blocks,
            path: path,
            page: page
        )
    }

    public func loadImage(url: URL) throws -> CGImage {
        // Avoid caching raw compressed data since we only need the decoded pixels
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            throw OCRError.imageLoadFailed(url.path)
        }
        // Decode immediately rather than deferring to first access, which avoids
        // a latency spike when the Vision framework reads the pixel data.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions as CFDictionary) else {
            throw OCRError.imageLoadFailed(url.path)
        }
        return image
    }
}

enum OCRError: Error, CustomStringConvertible {
    case imageLoadFailed(String)
    case ocrFailed(String)

    var description: String {
        switch self {
        case .imageLoadFailed(let path):
            return "Failed to load image: \(path)"
        case .ocrFailed(let message):
            return "OCR failed: \(message)"
        }
    }
}
