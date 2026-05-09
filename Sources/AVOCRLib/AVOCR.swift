import Foundation
import PDFKit
import CoreGraphics
import Vision

// MARK: - Processing Result

/// Represents the outcome of an OCR processing operation.
///
/// Use this struct to inspect how many pages were processed successfully,
/// how many failed, and how many were skipped.
public struct ProcessingResult: Sendable {
    /// Number of pages successfully processed
    public let completed: Int
    
    /// Number of pages that failed to process
    public let failed: Int
    
    /// Number of pages that were skipped (e.g., already had text)
    public let skipped: Int
    
    /// Total number of pages attempted
    public var total: Int { completed + failed + skipped }
    
    /// Whether all pages were processed successfully
    public var isSuccess: Bool { failed == 0 }
    
    /// Whether some pages failed but some succeeded
    public var isPartialSuccess: Bool { failed > 0 && completed > 0 }
    
    /// Whether all pages failed
    public var isTotalFailure: Bool { completed == 0 && failed > 0 }
    
    public init(completed: Int = 0, failed: Int = 0, skipped: Int = 0) {
        self.completed = completed
        self.failed = failed
        self.skipped = skipped
    }
    
    /// Merge two results together
    public func merging(_ other: ProcessingResult) -> ProcessingResult {
        ProcessingResult(
            completed: completed + other.completed,
            failed: failed + other.failed,
            skipped: skipped + other.skipped
        )
    }
}

// MARK: - Exit Codes

/// Standard exit codes for CLI operations
public enum ExitCode: Int32 {
    /// All pages processed successfully
    case success = 0
    /// Some pages failed, but some succeeded
    case partialFailure = 1
    /// All pages failed or a fatal error occurred
    case totalFailure = 2
    
    /// Determine the appropriate exit code from a processing result
    public static func from(_ result: ProcessingResult) -> ExitCode {
        if result.isTotalFailure {
            return .totalFailure
        } else if result.isPartialSuccess {
            return .partialFailure
        }
        return .success
    }
}

// MARK: - Processing Errors

/// Errors that can occur during OCR processing
public enum ProcessingError: Error, CustomStringConvertible {
    /// Failed to enumerate input files
    case fileEnumerationFailed(String)
    
    /// Maximum error threshold exceeded
    case maxErrorsExceeded(Int)
    
    /// Processing was cancelled
    case cancelled
    
    /// Failed to process a specific file
    case processingFailed(path: String, message: String)
    
    public var description: String {
        switch self {
        case .fileEnumerationFailed(let message):
            return "Failed to enumerate files: \(message)"
        case .maxErrorsExceeded(let count):
            return "Maximum error threshold exceeded (\(count) errors)"
        case .cancelled:
            return "Processing was cancelled"
        case .processingFailed(let path, let message):
            return "Failed to process \(path): \(message)"
        }
    }
}

// MARK: - Configuration

// MARK: - Retry Policy

/// Retry configuration for transient OCR failures.
public struct RetryPolicy: Sendable {
    /// Total attempts including the initial attempt.
    public let maxAttempts: Int
    /// Exponential backoff multiplier applied after each failed attempt.
    public let backoffMultiplier: Double
    /// Initial delay before the first retry.
    public let initialDelay: TimeInterval

    public init(maxAttempts: Int, backoffMultiplier: Double = 2.0, initialDelay: TimeInterval = 0.25) {
        self.maxAttempts = max(1, maxAttempts)
        self.backoffMultiplier = backoffMultiplier
        self.initialDelay = initialDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1)
}

/// Configuration options for OCR processing.
///
/// Create a configuration to customize how OCR is performed:
///
/// ```swift
/// let config = AVOCR.Configuration(
///     languages: ["en-US", "de-DE"],
///     recognitionLevel: .accurate,
///     pdfRenderDPI: 300
/// )
/// ```
public struct Configuration: Sendable {
    /// Recognition level for OCR
    public enum RecognitionLevel: Sendable {
        /// Fast recognition, less accurate
        case fast
        /// Accurate recognition, slower
        case accurate
    }
    
    /// Column detection mode
    public enum ColumnDetection: Sendable {
        /// Automatically detect columns
        case auto
        /// Fixed number of columns (1-3)
        case fixed(Int)
        
        var toColumnMode: ColumnMode {
            switch self {
            case .auto:
                return .auto
            case .fixed(let count):
                return .fixed(count)
            }
        }
    }
    
    /// How to handle PDFs that already contain text
    public enum PDFTextExtraction: Sendable {
        /// Use existing text if available, fall back to OCR
        case auto
        /// Always perform OCR, ignore existing text
        case forceOCR
    }
    
    /// Languages to use for recognition (e.g., "en-US", "de-DE")
    public var languages: [String]
    
    /// Recognition level (fast or accurate)
    public var recognitionLevel: RecognitionLevel
    
    /// Column detection mode
    public var columnDetection: ColumnDetection
    
    /// DPI for rendering PDF pages (72-600)
    public var pdfRenderDPI: Int
    
    /// How to handle PDFs with existing text
    public var pdfTextExtraction: PDFTextExtraction
    
    /// Disable language correction
    public var disableLanguageCorrection: Bool
    
    /// Minimum text height (normalized 0-1)
    public var minimumTextHeight: Float?
    
    /// Region of interest (normalized 0-1 coordinates)
    public var regionOfInterest: CGRect?
    
    /// Stop processing on first error
    public var failFast: Bool
    
    /// Maximum number of errors before stopping (nil = unlimited)
    public var maxErrors: Int?

    /// Retry policy for transient OCR failures
    public var retryPolicy: RetryPolicy
    
    /// Create a new configuration with default values
    public init(
        languages: [String] = ["en-US"],
        recognitionLevel: RecognitionLevel = .accurate,
        columnDetection: ColumnDetection = .auto,
        pdfRenderDPI: Int = 300,
        pdfTextExtraction: PDFTextExtraction = .forceOCR,
        disableLanguageCorrection: Bool = false,
        minimumTextHeight: Float? = nil,
        regionOfInterest: CGRect? = nil,
        failFast: Bool = false,
        maxErrors: Int? = nil,
        retryPolicy: RetryPolicy = .none
    ) {
        self.languages = languages
        self.recognitionLevel = recognitionLevel
        self.columnDetection = columnDetection
        self.pdfRenderDPI = pdfRenderDPI
        self.pdfTextExtraction = pdfTextExtraction
        self.disableLanguageCorrection = disableLanguageCorrection
        self.minimumTextHeight = minimumTextHeight
        self.regionOfInterest = regionOfInterest
        self.failFast = failFast
        self.maxErrors = maxErrors
        self.retryPolicy = retryPolicy
    }
    
    /// Convert to internal OCRConfig
    func toOCRConfig() -> OCRConfig {
        OCRConfig(
            fast: recognitionLevel == .fast,
            languages: languages,
            noCorrection: disableLanguageCorrection,
            minTextHeight: minimumTextHeight,
            roi: regionOfInterest,
            columnMode: columnDetection.toColumnMode
        )
    }
}

// MARK: - Page Result

/// Result of processing a single page
public struct PageResult: Sendable {
    /// The extracted text
    public let text: String
    
    /// Individual text blocks with positions and confidence
    public let blocks: [TextBlock]
    
    /// Path to the source file
    public let path: String
    
    /// Page index (0-based) for multi-page documents, nil for images
    public let page: Int?
    
    /// Whether this result used existing PDF text (not OCR)
    public let usedExistingText: Bool
    
    public init(text: String, blocks: [TextBlock], path: String, page: Int?, usedExistingText: Bool = false) {
        self.text = text
        self.blocks = blocks
        self.path = path
        self.page = page
        self.usedExistingText = usedExistingText
    }
}

// MARK: - AVOCR

/// Main entry point for the AVOCR library.
///
/// Use this class to perform OCR on images and PDFs programmatically:
///
/// ```swift
/// let ocr = AVOCR()
/// let config = AVOCR.Configuration(languages: ["en-US"])
///
/// // Process files and get results
/// let (results, summary) = try ocr.process(
///     files: [url1, url2],
///     configuration: config
/// )
///
/// for result in results {
///     print(result.text)
/// }
/// ```
public final class AVOCR {
    /// Typealias for Configuration for namespacing
    public typealias Configuration = AVOCRLib.Configuration
    
    /// Callback for progress updates
    public typealias ProgressHandler = (Int, Int) -> Void
    
    /// Callback for individual page results
    public typealias ResultHandler = (PageResult) -> Void
    
    /// Callback for errors during processing
    public typealias ErrorHandler = (Error, String, Int?) -> Void
    
    private let processor: OCRProcessor
    private let dependencies: AVOCRDependencies
    
    /// Create a new AVOCR instance
    public init(
        engine: OCREngineProtocol = AVOCREngine(),
        dependencies: AVOCRDependencies = AVOCRDependencies()
    ) {
        self.processor = OCRProcessor(enablePDFCache: true, engine: engine)
        self.dependencies = dependencies
    }

    private func processInternal(
        files: [URL],
        configuration: Configuration,
        progressHandler: ProgressHandler?,
        errorHandler: ErrorHandler?
    ) throws -> (results: [PageResult], summary: ProcessingResult) {
        let plan = buildWorkPlan(files: files, logger: dependencies.logger)

        if plan.items.isEmpty {
            return ([], ProcessingResult())
        }

        let config = configuration.toOCRConfig()
        var results: [PageResult] = []
        var completed = 0
        var failed = 0
        var skipped = 0

        for item in plan.items {
            // Check max errors threshold
            if let maxErrors = configuration.maxErrors, failed >= maxErrors {
                throw ProcessingError.maxErrorsExceeded(failed)
            }

            // Wrap each iteration in autoreleasepool to release intermediate
            // CoreGraphics/Vision objects (CGImage, VNImageRequestHandler, etc.)
            // immediately instead of letting them accumulate across all items.
            try autoreleasepool {
                do {
                    let result = try processor.process(
                        item: item,
                        config: config,
                        dpi: configuration.pdfRenderDPI,
                        pdfTextExtraction: configuration.pdfTextExtraction,
                        retryPolicy: configuration.retryPolicy
                    )

                    let pageResult = PageResult(
                        text: result.text,
                        blocks: result.blocks,
                        path: result.path,
                        page: result.page,
                        usedExistingText: result.usedExistingText
                    )

                    results.append(pageResult)

                    if result.usedExistingText {
                        skipped += 1
                    } else {
                        completed += 1
                    }

                    progressHandler?(completed + failed + skipped, plan.totalPages)
                } catch {
                    failed += 1
                    errorHandler?(error, item.path, item.page)

                    if configuration.failFast {
                        throw ProcessingError.processingFailed(
                            path: item.path,
                            message: String(describing: error)
                        )
                    }

                    progressHandler?(completed + failed + skipped, plan.totalPages)
                }
            }
        }

        let summary = ProcessingResult(completed: completed, failed: failed, skipped: skipped)
        return (results, summary)
    }
    
    /// Process files synchronously and return all results.
    ///
    /// - Parameters:
    ///   - files: URLs to image or PDF files
    ///   - configuration: Processing configuration
    ///   - progressHandler: Optional callback for progress updates (completed, total)
    ///   - errorHandler: Optional callback for processing errors
    /// - Returns: Tuple of page results and processing summary
    /// - Throws: `ProcessingError` if file enumeration fails or max errors exceeded
    public func process(
        files: [URL],
        configuration: Configuration = Configuration(),
        progressHandler: ProgressHandler? = nil,
        errorHandler: ErrorHandler? = nil
    ) throws -> (results: [PageResult], summary: ProcessingResult) {
        try processInternal(
            files: files,
            configuration: configuration,
            progressHandler: progressHandler,
            errorHandler: errorHandler
        )
    }
    
    /// Process files asynchronously.
    ///
    /// - Parameters:
    ///   - files: URLs to image or PDF files
    ///   - configuration: Processing configuration
    ///   - progressHandler: Optional callback for progress updates (completed, total)
    ///   - errorHandler: Optional callback for processing errors
    /// - Returns: Tuple of page results and processing summary
    /// - Throws: `ProcessingError` if file enumeration fails or max errors exceeded
    public func process(
        files: [URL],
        configuration: Configuration = Configuration(),
        progressHandler: ProgressHandler? = nil,
        errorHandler: ErrorHandler? = nil
    ) async throws -> (results: [PageResult], summary: ProcessingResult) {
        try processInternal(
            files: files,
            configuration: configuration,
            progressHandler: progressHandler,
            errorHandler: errorHandler
        )
    }
    
    /// Process files with streaming results.
    ///
    /// This method calls the result handler for each page as it completes,
    /// allowing for incremental processing of results.
    ///
    /// - Parameters:
    ///   - files: URLs to image or PDF files
    ///   - configuration: Processing configuration
    ///   - resultHandler: Callback for each completed page
    ///   - errorHandler: Optional callback for processing errors
    /// - Returns: Processing summary
    /// - Throws: `ProcessingError` if file enumeration fails or max errors exceeded
    public func processStreaming(
        files: [URL],
        configuration: Configuration = Configuration(),
        resultHandler: ResultHandler,
        errorHandler: ErrorHandler? = nil
    ) throws -> ProcessingResult {
        let plan = buildWorkPlan(files: files, logger: dependencies.logger)
        
        if plan.items.isEmpty {
            return ProcessingResult()
        }
        
        let config = configuration.toOCRConfig()
        var completed = 0
        var failed = 0
        var skipped = 0
        
        for item in plan.items {
            // Check max errors threshold
            if let maxErrors = configuration.maxErrors, failed >= maxErrors {
                throw ProcessingError.maxErrorsExceeded(failed)
            }
            
            autoreleasepool {
                do {
                    let result = try processor.process(
                        item: item,
                        config: config,
                        dpi: configuration.pdfRenderDPI,
                        pdfTextExtraction: configuration.pdfTextExtraction,
                        retryPolicy: configuration.retryPolicy
                    )
                    
                    let pageResult = PageResult(
                        text: result.text,
                        blocks: result.blocks,
                        path: result.path,
                        page: result.page,
                        usedExistingText: result.usedExistingText
                    )
                    
                    resultHandler(pageResult)
                    
                    if result.usedExistingText {
                        skipped += 1
                    } else {
                        completed += 1
                    }
                } catch {
                    failed += 1
                    errorHandler?(error, item.path, item.page)
                }
            }
            
            if configuration.failFast && failed > 0 {
                break
            }
        }
        
        return ProcessingResult(completed: completed, failed: failed, skipped: skipped)
    }
}

// MARK: - OCRProcessor

/// Processor that handles the actual OCR work.
/// This unifies the logic previously duplicated between single-process and worker modes.
///
/// Supports two processing modes:
/// 1. Single-step: `process(item:...)` - loads image and runs OCR in one call
/// 2. Pipelined: `prepare(item:...)` then `processOCR(prepared:...)` - separates I/O
///    from compute so image loading can overlap with OCR on the previous item.
public final class OCRProcessor {
    /// Result that tracks whether existing text was used
    public struct InternalResult {
        public let text: String
        public let blocks: [TextBlock]
        public let path: String
        public let page: Int?
        public let usedExistingText: Bool

        public init(text: String, blocks: [TextBlock], path: String, page: Int?, usedExistingText: Bool) {
            self.text = text
            self.blocks = blocks
            self.path = path
            self.page = page
            self.usedExistingText = usedExistingText
        }
    }

    /// A work item with its image already loaded, ready for OCR.
    /// Produced by `prepare(item:...)`, consumed by `processOCR(prepared:...)`.
    public enum PreparedItem {
        /// Image loaded and ready for OCR
        case image(CGImage, WorkItem)
        /// PDF text was extracted directly (no OCR needed)
        case extractedText(String, WorkItem)
    }

    /// PDF cache for worker mode (LRU-1)
    private var lastPDFPath: String?
    private var lastPDF: PDFDocument?
    private let enablePDFCache: Bool
    private let engine: OCREngineProtocol
    private let retryHandler: ((String) -> Void)?

    public init(
        enablePDFCache: Bool = false,
        engine: OCREngineProtocol = AVOCREngine(),
        retryHandler: ((String) -> Void)? = nil
    ) {
        self.enablePDFCache = enablePDFCache
        self.engine = engine
        self.retryHandler = retryHandler
    }

    // MARK: - Single-step processing (for callers that don't need pipelining)

    /// Process a single work item (loads image + runs OCR in one call).
    public func process(
        item: WorkItem,
        config: OCRConfig,
        dpi: Int,
        pdfTextExtraction: Configuration.PDFTextExtraction,
        retryPolicy: RetryPolicy
    ) throws -> InternalResult {
        if let pageIndex = item.page {
            return try processPDFPage(
                path: item.path,
                pageIndex: pageIndex,
                config: config,
                dpi: dpi,
                pdfTextExtraction: pdfTextExtraction,
                retryPolicy: retryPolicy
            )
        } else {
            return try processImage(path: item.path, config: config, retryPolicy: retryPolicy)
        }
    }

    // MARK: - Two-phase pipelined processing

    /// Phase 1 (I/O): Load image from disk or render PDF page.
    /// This can run on a background thread to overlap with OCR on another item.
    /// NOTE: This method accesses the PDF cache and is NOT thread-safe.
    /// Call from a single serial queue or synchronize externally.
    public func prepare(
        item: WorkItem,
        dpi: Int,
        pdfTextExtraction: Configuration.PDFTextExtraction
    ) throws -> PreparedItem {
        if let pageIndex = item.page {
            guard let pdf = loadPDF(path: item.path) else {
                throw OCRError.ocrFailed("Cannot load PDF: \(item.path)")
            }
            guard let page = pdf.page(at: pageIndex) else {
                throw OCRError.ocrFailed("Cannot get page \(pageIndex) from \(item.path)")
            }
            if pdfTextExtraction == .auto,
               let text = PDFRenderer.extractTextIfAvailable(page: page) {
                return .extractedText(text, item)
            }
            guard let image = PDFRenderer.renderPageToImage(page: page, dpi: dpi) else {
                throw OCRError.ocrFailed("Cannot render page \(pageIndex) from \(item.path)")
            }
            return .image(image, item)
        } else {
            let fileURL = URL(fileURLWithPath: item.path)
            let image = try engine.loadImage(url: fileURL)
            return .image(image, item)
        }
    }

    /// Phase 2 (Compute): Run OCR on a previously prepared item.
    /// Vision framework OCR is single-threaded per process, so this should run
    /// on the main processing thread while the next item is being prepared.
    public func processOCR(
        prepared: PreparedItem,
        config: OCRConfig,
        retryPolicy: RetryPolicy
    ) throws -> InternalResult {
        switch prepared {
        case .extractedText(let text, let item):
            return InternalResult(
                text: text,
                blocks: [],
                path: item.path,
                page: item.page,
                usedExistingText: true
            )
        case .image(let image, let item):
            let result = try performOCRWithRetry(
                image: image,
                config: config,
                path: item.path,
                page: item.page,
                retryPolicy: retryPolicy
            )
            return InternalResult(
                text: result.text,
                blocks: result.blocks,
                path: result.path,
                page: result.page,
                usedExistingText: false
            )
        }
    }

    // MARK: - Private

    private func loadPDF(path: String) -> PDFDocument? {
        if enablePDFCache {
            if let cached = lastPDF, lastPDFPath == path {
                return cached
            }
            let pdf = PDFRenderer.loadPDF(url: URL(fileURLWithPath: path))
            lastPDF = pdf
            lastPDFPath = path
            return pdf
        } else {
            return PDFRenderer.loadPDF(url: URL(fileURLWithPath: path))
        }
    }

    private func processPDFPage(
        path: String,
        pageIndex: Int,
        config: OCRConfig,
        dpi: Int,
        pdfTextExtraction: Configuration.PDFTextExtraction,
        retryPolicy: RetryPolicy
    ) throws -> InternalResult {
        guard let pdf = loadPDF(path: path) else {
            throw OCRError.ocrFailed("Cannot load PDF: \(path)")
        }

        guard let page = pdf.page(at: pageIndex) else {
            throw OCRError.ocrFailed("Cannot get page \(pageIndex) from \(path)")
        }

        // Check for existing text if auto mode
        if pdfTextExtraction == .auto,
           let text = PDFRenderer.extractTextIfAvailable(page: page) {
            return InternalResult(
                text: text,
                blocks: [],
                path: path,
                page: pageIndex,
                usedExistingText: true
            )
        }

        // Render and OCR the page
        guard let image = PDFRenderer.renderPageToImage(page: page, dpi: dpi) else {
            throw OCRError.ocrFailed("Cannot render page \(pageIndex) from \(path)")
        }

        let result = try performOCRWithRetry(
            image: image,
            config: config,
            path: path,
            page: pageIndex,
            retryPolicy: retryPolicy
        )

        return InternalResult(
            text: result.text,
            blocks: result.blocks,
            path: result.path,
            page: result.page,
            usedExistingText: false
        )
    }

    private func processImage(path: String, config: OCRConfig, retryPolicy: RetryPolicy) throws -> InternalResult {
        let fileURL = URL(fileURLWithPath: path)
        let image = try engine.loadImage(url: fileURL)

        let result = try performOCRWithRetry(
            image: image,
            config: config,
            path: path,
            page: nil,
            retryPolicy: retryPolicy
        )

        return InternalResult(
            text: result.text,
            blocks: result.blocks,
            path: result.path,
            page: result.page,
            usedExistingText: false
        )
    }

    private func performOCRWithRetry(
        image: CGImage,
        config: OCRConfig,
        path: String,
        page: Int?,
        retryPolicy: RetryPolicy
    ) throws -> OCRResult {
        let maxAttempts = max(1, retryPolicy.maxAttempts)
        var attempt = 1
        var delay = retryPolicy.initialDelay

        while true {
            do {
                return try engine.performOCR(
                    image: image,
                    config: config,
                    path: path,
                    page: page
                )
            } catch {
                if attempt >= maxAttempts || !shouldRetry(error: error) {
                    throw error
                }

                let nextAttempt = attempt + 1
                let pageLabel = page.map { " page \($0)" } ?? ""
                retryHandler?("Retrying OCR for \(path)\(pageLabel) (attempt \(nextAttempt)/\(maxAttempts)) after error: \(error)")
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                    delay *= retryPolicy.backoffMultiplier
                }
                attempt = nextAttempt
            }
        }
    }

    private func shouldRetry(error: Error) -> Bool {
        if error is OCRError {
            return false
        }
        let nsError = error as NSError
        return nsError.domain == VNErrorDomain || nsError.domain == "com.apple.Vision"
    }
}
