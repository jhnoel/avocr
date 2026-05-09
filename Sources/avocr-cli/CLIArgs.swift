import Foundation
import ArgumentParser
import AVOCRLib

// The CLI is just an entry point that delegates to AVOCRLib.CLIArgs
// This provides a clean separation between the library and the CLI

@main
struct OCRCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ocr",
        abstract: "Fast macOS OCR using Apple Vision",
        discussion: """
            Supported formats: PDF, PNG, JPEG, TIFF, GIF, BMP, HEIC, WebP

            EXAMPLES:
              ocr document.pdf
              ocr --stdout image.png | pbcopy
              ocr -f jsonl -o ./results/ *.pdf
              ocr -i ./scans -i ./photos -o ./text
            """,
        version: "1.0.0"
    )

    // MARK: - Input Options

    @Argument(help: "Input files or directories")
    var inputs: [String] = []

    @Option(name: [.short, .customLong("input")], parsing: .upToNextOption, help: "Input files or directories (can be repeated)")
    var inputOptions: [String] = []

    @Flag(name: .customLong("include-hidden"), help: "Include hidden files when scanning directories")
    var includeHidden: Bool = false

    // MARK: - Output Options

    @Option(name: [.short, .customLong("output")], help: "Output directory (default: current directory)")
    var output: String?

    @Flag(name: .customLong("stdout"), help: "Write output to stdout instead of files")
    var stdout: Bool = false

    @Option(name: [.customShort("f"), .customLong("format")], help: "Output format: text or jsonl")
    var format: AVOCRLib.OutputFormat = .text

    @Flag(name: .customLong("per-page"), help: "Write one .txt file per page")
    var perPage: Bool = false

    @Flag(name: .customLong("no-headers"), help: "Suppress page headers in text output")
    var noHeaders: Bool = false

    @Flag(name: .customLong("no-progress"), help: "Disable progress output")
    var noProgress: Bool = false

    @Flag(name: [.short, .customLong("verbose")], help: "Enable verbose logging")
    var verbose: Bool = false

    @Option(name: .customLong("log-format"), help: "Log format: text or json")
    var logFormat: AVOCRLib.LogFormat = .text

    // MARK: - OCR Options

    @Flag(name: .customLong("fast"), help: "Fast recognition (~2x speed, lower accuracy)")
    var fast: Bool = false

    @Option(name: [.customShort("c"), .customLong("columns")], help: "Column layout: auto, 1, 2, or 3")
    var columns: AVOCRLib.ColumnMode = .auto

    @Option(name: [.customShort("l"), .customLong("lang")], help: "Languages, comma-separated (e.g., en-US,de-DE)")
    var languageString: String = "en-US"

    @Flag(name: .customLong("no-correction"), help: "Disable language correction")
    var noCorrection: Bool = false

    @Option(name: .customLong("min-text-height"), help: "Minimum text height, normalized 0-1")
    var minTextHeight: Float?

    @Option(name: .customLong("roi"), help: "Region of interest: x,y,w,h (normalized 0-1)")
    var roiString: String?

    // MARK: - PDF Options

    @Option(name: .customLong("dpi"), help: "PDF render DPI (72-600)")
    var dpi: Int = 300

    @Flag(name: .customLong("use-existing-text"), help: "Use existing PDF text instead of OCR (default)")
    var useExistingText: Bool = true

    @Flag(name: .customLong("embed-text-layer"), help: "Output a searchable PDF with OCR text layer embedded")
    var embedTextLayer: Bool = false

    @Flag(name: .customLong("overwrite"), help: "Overwrite original files (requires --embed-text-layer)")
    var overwrite: Bool = false

    @Flag(name: .customLong("force-ocr"), help: "Force OCR even when PDFs have embedded text")
    var forceOCR: Bool = false

    // MARK: - Performance Options
    
    @Option(name: [.customShort("j"), .customLong("workers")], help: "Worker processes (default: CPU count, or 'max')")
    var workers: AVOCRLib.JobsValue?

    @Option(name: .customLong("prefetch"), help: "In-flight tasks per worker (default: 2)")
    var prefetch: Int = 2

    // MARK: - Error Handling Options

    @Flag(name: .customLong("fail-fast"), help: "Stop processing on first error")
    var failFast: Bool = false

    @Option(name: .customLong("max-errors"), help: "Maximum errors before stopping (default: unlimited)")
    var maxErrors: Int?

    @Option(name: .customLong("retries"), help: "Retries for transient OCR errors (default: 0)")
    var retries: Int = 0

    @Option(name: .customLong("graceful-timeout"), help: "Seconds to allow cleanup after cancellation (default: 2.0)")
    var gracefulTimeout: Double = 2.0

    // MARK: - Hidden/Deprecated Options

    @Flag(name: .customLong("jsonl"), help: .hidden)
    var jsonl: Bool = false

    @Flag(name: .customLong("quiet"), help: .hidden)
    var quiet: Bool = false

    @Flag(name: .customLong("split-pages"), help: .hidden)
    var splitPages: Bool = false

    @Flag(name: .customLong("worker"), help: .hidden)
    var workerMode: Bool = false

    // MARK: - Validation & Run

    mutating func validate() throws {
        if !workerMode && (inputs + inputOptions).isEmpty {
            throw CleanExit.helpRequest()
        }

        if stdout && output != nil {
            throw ValidationError("--stdout cannot be used with --output")
        }

        if let minTextHeight = minTextHeight, minTextHeight <= 0 {
            throw ValidationError("--min-text-height must be a positive number")
        }

        if dpi < 72 || dpi > 600 {
            throw ValidationError("--dpi must be between 72 and 600")
        }

        if overwrite && !embedTextLayer {
            throw ValidationError("--overwrite requires --embed-text-layer")
        }

        if embedTextLayer && stdout {
            throw ValidationError("--embed-text-layer cannot be used with --stdout")
        }

        if embedTextLayer && format == .jsonl {
            throw ValidationError("--embed-text-layer cannot be used with --format jsonl")
        }

        if let roiString = roiString {
            let parts = roiString.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4,
                  parts.allSatisfy({ $0 >= 0 && $0 <= 1 }),
                  parts[0] + parts[2] <= 1,
                  parts[1] + parts[3] <= 1 else {
                throw ValidationError("--roi must be x,y,w,h with 0-1 normalized values")
            }
        }
    }

    mutating func run() throws {
        // Build library CLIArgs from our CLI options
        var libArgs = AVOCRLib.CLIArgs()
        
        // Map all options to the library struct
        libArgs.inputs = inputs + inputOptions
        libArgs.includeHidden = includeHidden
        libArgs.output = stdout ? nil : (output ?? FileManager.default.currentDirectoryPath)
        libArgs.format = jsonl ? .jsonl : format
        libArgs.perPage = splitPages || perPage
        libArgs.noHeaders = quiet || noHeaders
        libArgs.noProgress = noProgress
        libArgs.verbose = verbose
        libArgs.logFormat = logFormat
        libArgs.fast = fast
        libArgs.columns = columns
        libArgs.languageString = languageString
        libArgs.noCorrection = noCorrection
        libArgs.minTextHeight = minTextHeight
        libArgs.roiString = roiString
        libArgs.dpi = dpi
        libArgs.useExistingText = forceOCR ? false : useExistingText
        libArgs.embedTextLayer = embedTextLayer
        libArgs.overwrite = overwrite
        libArgs.workers = workers
        libArgs.prefetch = prefetch
        libArgs.failFast = failFast
        libArgs.maxErrors = maxErrors
        libArgs.retries = retries
        libArgs.gracefulTimeout = gracefulTimeout
        libArgs.workerMode = workerMode
        
        // Run validation on libArgs to parse ROI, etc.
        try libArgs.validate()
        
        // Delegate to library
        try libArgs.run()
    }

}
