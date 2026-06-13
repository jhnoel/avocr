import Foundation
import ArgumentParser

extension LogFormat: ExpressibleByArgument {}

public enum OutputFormat: String, ExpressibleByArgument {
    case text
    case jsonl
}

public enum PDFTextMode {
    case auto
    case ocr
}

public enum ColumnMode: ExpressibleByArgument {
    case auto
    case fixed(Int)

    public init?(argument: String) {
        if argument == "auto" {
            self = .auto
            return
        }
        if let count = Int(argument), (Constants.minColumnCount...Constants.maxColumnCount).contains(count) {
            self = .fixed(count)
            return
        }
        return nil
    }
}

public struct JobsValue: ExpressibleByArgument {
    public let value: Int?
    public let isMax: Bool

    public init?(argument: String) {
        if argument == "max" {
            value = nil
            isMax = true
            return
        }
        guard let parsed = Int(argument), parsed > 0 else { return nil }
        value = parsed
        isMax = false
    }
}

public struct CLIArgs {
    public init() {}

    public var inputs: [String] = []
    public var columns: ColumnMode = .auto
    public var dpi: Int = 300
    public var fast: Bool = false
    public var useExistingText: Bool = true
    public var embedTextLayer: Bool = false
    public var overwrite: Bool = false
    public var skipTextPDF: Bool = false
    public var format: OutputFormat = .text
    public var jsonl: Bool = false
    public var includeHidden: Bool = false
    public var languageString: String = "en-US"
    public var minTextHeight: Float?
    public var noCorrection: Bool = false
    public var noHeaders: Bool = false
    public var quiet: Bool = false
    public var progress: Bool = true
    public var progressFormat: ProgressFormat = .bar
    public var noProgress: Bool = false
    public var verbose: Bool = false
    public var logFormat: LogFormat = .text
    public var output: String?
    public var perPage: Bool = false
    public var splitPages: Bool = false
    public var roiString: String?
    public var stdout: Bool = false
    public var workers: JobsValue?
    public var workerMode: Bool = false
    public var prefetch: Int = 2
    public var batchByDocument: Bool = false
    public var failFast: Bool = false
    public var maxErrors: Int?
    public var retries: Int = 0
    public var gracefulTimeout: Double = Constants.defaultGracefulTimeoutSeconds

    private var parsedROI: CGRect?

    public var outputDir: String? {
        get { output }
        set { output = newValue }
    }

    public var languages: [String] {
        let trimmed = languageString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ["en-US"]
        }

        let parsed = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parsed.isEmpty ? ["en-US"] : parsed
    }

    public var roi: CGRect? {
        parsedROI
    }

    public var pdfTextMode: PDFTextMode {
        useExistingText ? .auto : .ocr
    }

    public var jobs: Int {
        if workerMode {
            return 1
        }
        let maxJobs = max(1, ProcessInfo.processInfo.activeProcessorCount)
        if let workers = workers {
            let resolved = workers.value ?? maxJobs
            return min(maxJobs, resolved)
        }
        return maxJobs
    }

    public var jobsIsAuto: Bool {
        if workerMode {
            return false
        }
        return workers == nil || workers?.isMax == true
    }

    public var multiprocess: Bool {
        jobs > 1
    }

    public var retryPolicy: RetryPolicy {
        RetryPolicy(maxAttempts: max(1, retries + 1))
    }

    public var progressEnabled: Bool {
        progress && progressFormat != .quiet
    }

    public mutating func validate() throws {
        if jsonl {
            format = .jsonl
        }

        if quiet {
            noHeaders = true
        }

        if splitPages {
            perPage = true
        }

        if noProgress {
            progress = false
            progressFormat = .quiet
        } else if progressFormat == .quiet {
            progress = false
        } else {
            progress = true
        }

        if !workerMode && inputs.isEmpty {
            throw CLIError.invalidArgument("No input files or directories specified")
        }

        if stdout && outputDir != nil {
            throw CLIError.invalidArgument("--stdout cannot be used with --output")
        }

        if let minTextHeight = minTextHeight, minTextHeight <= 0 || minTextHeight > 1 {
            throw CLIError.invalidArgument("--min-text-height must be between 0 and 1")
        }

        if dpi < Constants.minPDFRenderDPI || dpi > Constants.maxPDFRenderDPI {
            throw CLIError.invalidArgument("--dpi must be between \(Constants.minPDFRenderDPI) and \(Constants.maxPDFRenderDPI)")
        }

        if prefetch < 1 {
            throw CLIError.invalidArgument("--prefetch must be >= 1")
        }

        if let roiString = roiString {
            guard let roiValue = CLIArgs.parseROI(roiString) else {
                throw CLIError.invalidArgument("--roi must be x,y,w,h with 0-1 normalized values")
            }
            parsedROI = roiValue
        }

        if overwrite && !embedTextLayer {
            throw CLIError.invalidArgument("--overwrite requires --embed-text-layer")
        }

        if embedTextLayer && stdout {
            throw CLIError.invalidArgument("--embed-text-layer cannot be used with --stdout")
        }

        if embedTextLayer && format == .jsonl {
            throw CLIError.invalidArgument("--embed-text-layer cannot be used with --format jsonl")
        }

        if embedTextLayer && perPage {
            throw CLIError.invalidArgument("--embed-text-layer cannot be used with --per-page")
        }

        if let maxErrors = maxErrors, maxErrors < 1 {
            throw CLIError.invalidArgument("--max-errors must be >= 1")
        }

        if gracefulTimeout < 0 {
            throw CLIError.invalidArgument("--graceful-timeout must be >= 0")
        }

        if retries < 0 {
            throw CLIError.invalidArgument("--retries must be >= 0")
        }

        if !workerMode && !stdout && outputDir == nil {
            outputDir = FileManager.default.currentDirectoryPath
        }
    }

    public mutating func run() throws {
        if workerMode {
            runWorker(args: self)
            return
        }

        let output = StandardOutputStream()
        let errorOutput = StandardErrorStream()
        let logger = LoggerFactory.makeLogger(format: logFormat, isVerbose: verbose, output: errorOutput)
        let dependencies = RuntimeDependencies(
            output: output,
            errorOutput: errorOutput,
            logger: logger
        )
        let result = runOCR(args: self, dependencies: dependencies)
        
        switch result {
        case .success(let processingResult):
            let exitCode = ExitCode.from(processingResult)
            if exitCode != .success {
                Darwin.exit(exitCode.rawValue)
            }
        case .failure(let error):
            dependencies.logger.error("Fatal error: \(error)")
            Darwin.exit(ExitCode.totalFailure.rawValue)
        }
    }

    private static func parseROI(_ value: String) -> CGRect? {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        let x = parts[0]
        let y = parts[1]
        let w = parts[2]
        let h = parts[3]
        guard x >= 0, y >= 0, w > 0, h > 0,
              x <= 1, y <= 1, w <= 1, h <= 1,
              x + w <= 1, y + h <= 1 else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
