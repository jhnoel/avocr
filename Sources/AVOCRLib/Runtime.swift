import Foundation
import Darwin
import Vision
import PDFKit
import CoreGraphics
import AppKit

/// Run OCR processing and return the result.
///
/// - Parameter args: CLI arguments
/// - Returns: Result containing ProcessingResult on success or ProcessingError on failure
public func runOCR(
    args: CLIArgs,
    dependencies: RuntimeDependencies = RuntimeDependencies()
) -> Result<ProcessingResult, ProcessingError> {
    let filesResult = FileEnumerator.enumerateFiles(
        paths: args.inputs,
        includeHidden: args.includeHidden,
        fileSystem: dependencies.fileSystem,
        logger: dependencies.logger
    )

    let files: [URL]
    switch filesResult {
    case .success(let foundFiles):
        files = foundFiles
    case .failure(let error):
        dependencies.logger.error("\(error)")
        return .failure(.fileEnumerationFailed(String(describing: error)))
    }

    if args.multiprocess {
        do {
            let result = try MultiprocessCoordinator.runMultiprocess(
                files: files,
                args: args,
                dependencies: dependencies
            )
            return .success(result)
        } catch let error as ProcessingError {
            dependencies.logger.error("\(error)")
            return .failure(error)
        } catch {
            dependencies.logger.error("\(error)")
            return .failure(.processingFailed(path: "", message: String(describing: error)))
        }
    } else {
        return runSingleProcess(files: files, args: args, dependencies: dependencies)
    }
}

func runSingleProcess(
    files: [URL],
    args: CLIArgs,
    dependencies: RuntimeDependencies
) -> Result<ProcessingResult, ProcessingError> {
    let plan = buildWorkPlan(files: files, logger: dependencies.logger)
    let writer = OutputWriter(
        outputDir: args.outputDir,
        perPage: args.perPage,
        format: args.format,
        noHeaders: args.noHeaders,
        emitPageMarkers: false,
        orderedWrites: false,
        output: dependencies.output,
        fileSystem: dependencies.fileSystem
    )

    let cancellationToken = CancellationToken()
    let signalQueue = DispatchQueue(label: "avocr.singleprocess.signal")
    var signalSources: [DispatchSourceSignal] = []
    var forceExitWorkItem: DispatchWorkItem?

    func scheduleForceExit() {
        guard args.gracefulTimeout > 0 else { return }
        let workItem = DispatchWorkItem {
            dependencies.logger.warn("Graceful timeout exceeded, exiting now.")
            Darwin.exit(ExitCode.totalFailure.rawValue)
        }
        forceExitWorkItem = workItem
        signalQueue.asyncAfter(deadline: .now() + args.gracefulTimeout, execute: workItem)
    }

    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
        source.setEventHandler {
            if cancellationToken.isCancelled {
                return
            }
            cancellationToken.cancel()
            dependencies.logger.warn("Received termination signal, stopping after current page...")
            scheduleForceExit()
        }
        source.resume()
        signalSources.append(source)
    }

    defer {
        for source in signalSources {
            source.cancel()
        }
        forceExitWorkItem?.cancel()
    }

    if !args.noHeaders && args.format != .jsonl && args.progressFormat != .json {
        dependencies.logger.info("Processing \(plan.totalPages) page(s)")
    }

    let progressReporter = ProgressReporterFactory.makeReporter(
        format: args.progressFormat,
        enabled: args.progressEnabled,
        output: dependencies.errorOutput
    )
    progressReporter.start(totalPages: plan.totalPages)

    let config = OCRConfig(
        fast: args.fast,
        languages: args.languages,
        noCorrection: args.noCorrection,
        minTextHeight: args.minTextHeight,
        roi: args.roi,
        columnMode: args.columns
    )

    let retryHandler: ((String) -> Void)? = args.retries > 0 ? { message in
        dependencies.logger.debug(message)
    } : nil
    let processor = OCRProcessor(enablePDFCache: true, retryHandler: retryHandler)
    let pdfTextExtraction: Configuration.PDFTextExtraction = args.useExistingText ? .auto : .forceOCR
    let retryPolicy = args.retryPolicy
    
    let startTime = Date()
    var completed = 0
    var failed = 0
    var skipped = 0
    let totalPages = plan.items.count

    // When embedding text layers, collect OCR blocks grouped by source PDF
    var pdfPageResults: [String: [(pageIndex: Int, blocks: [TextBlock])]] = [:]

    enum PreparedSingleProcessWork {
        case ready(WorkItem, OCRProcessor.PreparedItem)
        case failed(WorkItem, Error)
    }

    final class PreparedSlot {
        private let lock = NSLock()
        private var work: PreparedSingleProcessWork?

        func set(_ work: PreparedSingleProcessWork) {
            lock.lock()
            self.work = work
            lock.unlock()
        }

        func get() -> PreparedSingleProcessWork? {
            lock.lock()
            defer { lock.unlock() }
            return work
        }
    }

    let prepareQueue = DispatchQueue(label: "avocr.singleprocess.prepare")
    var nextItemIndex = 0

    func scheduleNextPreparedWork() -> (slot: PreparedSlot, group: DispatchGroup)? {
        guard nextItemIndex < plan.items.count else { return nil }
        let item = plan.items[nextItemIndex]
        nextItemIndex += 1

        let slot = PreparedSlot()
        let group = DispatchGroup()
        group.enter()
        prepareQueue.async {
            let work: PreparedSingleProcessWork = autoreleasepool {
                do {
                    let prepared = try processor.prepare(
                        item: item,
                        dpi: args.dpi,
                        pdfTextExtraction: pdfTextExtraction
                    )
                    return .ready(item, prepared)
                } catch {
                    return .failed(item, error)
                }
            }
            slot.set(work)
            group.leave()
        }
        return (slot, group)
    }

    var scheduledWork = scheduleNextPreparedWork()

    while let currentWork = scheduledWork {
        if cancellationToken.isCancelled {
            currentWork.group.wait()
            break
        }
        // Check fail-fast condition
        if args.failFast && failed > 0 {
            currentWork.group.wait()
            break
        }

        // Check max errors threshold
        if let maxErrors = args.maxErrors, failed >= maxErrors {
            currentWork.group.wait()
            writer.close()
            return .failure(.maxErrorsExceeded(failed))
        }

        currentWork.group.wait()
        guard let work = currentWork.slot.get() else {
            dependencies.logger.error("Internal error: prepared work was unavailable")
            failed += 1
            progressReporter.update(
                completedPages: completed + failed + skipped,
                totalPages: totalPages
            )
            scheduledWork = scheduleNextPreparedWork()
            continue
        }

        scheduledWork = scheduleNextPreparedWork()

        autoreleasepool {
            switch work {
            case .ready(_, let prepared):
                do {
                    let internalResult = try processor.processOCR(
                        prepared: prepared,
                        config: config,
                        retryPolicy: retryPolicy
                    )

                    if args.embedTextLayer, let pageIndex = internalResult.page {
                        var entries = pdfPageResults[internalResult.path] ?? []
                        entries.append((pageIndex: pageIndex, blocks: internalResult.blocks))
                        pdfPageResults[internalResult.path] = entries
                    } else if !args.embedTextLayer {
                        let result = OCRResult(
                            text: internalResult.text,
                            blocks: internalResult.blocks,
                            path: internalResult.path,
                            page: internalResult.page
                        )
                        try writer.write(result: result)
                    }

                    if internalResult.usedExistingText {
                        skipped += 1
                    } else {
                        completed += 1
                    }
                } catch {
                    failed += 1
                    dependencies.logger.error("\(error)")
                }
            case .failed(_, let error):
                failed += 1
                dependencies.logger.error("\(error)")
            }

            progressReporter.update(
                completedPages: completed + failed + skipped,
                totalPages: totalPages
            )
        }
    }

    // Write searchable PDFs if embed-text-layer mode
    if args.embedTextLayer {
        for (pdfPath, pageResults) in pdfPageResults {
            do {
                let sourceURL = URL(fileURLWithPath: pdfPath)
                let outputURL: URL
                if args.overwrite {
                    outputURL = sourceURL
                } else if let outputDir = args.outputDir {
                    let fileName = sourceURL.lastPathComponent
                    try dependencies.fileSystem.createDirectory(
                        atPath: outputDir,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                    outputURL = URL(fileURLWithPath: outputDir).appendingPathComponent(fileName)
                } else {
                    outputURL = sourceURL
                }
                try PDFRenderer.createSearchablePDF(from: sourceURL, pageResults: pageResults, to: outputURL)
                dependencies.logger.info("Wrote searchable PDF: \(outputURL.path)")
            } catch {
                failed += 1
                dependencies.logger.error("Failed to create searchable PDF for \(pdfPath): \(error)")
            }
        }
    }

    if !args.embedTextLayer {
        writer.close()
    }

    let processingResult = ProcessingResult(completed: completed, failed: failed, skipped: skipped)
    
    if args.progressEnabled {
        let duration = Date().timeIntervalSince(startTime)
        let rate = duration > 0 ? Double(completed + skipped) / duration : 0
        let summary = ProgressSummary(
            completed: completed,
            failed: failed,
            skipped: skipped,
            duration: duration,
            throughput: rate
        )
        progressReporter.finish(summary: summary)
    }
    
    if cancellationToken.isCancelled {
        return .failure(.cancelled)
    }

    return .success(processingResult)
}

/// Process a single work item (legacy function, delegates to OCRProcessor)
func processWorkItem(_ item: WorkItem, config: OCRConfig, args: CLIArgs) throws -> OCRResult {
    let processor = OCRProcessor()
    let pdfTextExtraction: Configuration.PDFTextExtraction = args.useExistingText ? .auto : .forceOCR
    let retryPolicy = args.retryPolicy
    
    let internalResult = try processor.process(
        item: item,
        config: config,
        dpi: args.dpi,
        pdfTextExtraction: pdfTextExtraction,
        retryPolicy: retryPolicy
    )
    
    return OCRResult(
        text: internalResult.text,
        blocks: internalResult.blocks,
        path: internalResult.path,
        page: internalResult.page
    )
}

/// Worker entry point with I/O-OCR pipeline.
///
/// Uses a producer-consumer pattern to overlap image loading/rendering with OCR:
/// - Producer thread: reads tasks from stdin, loads images (I/O bound)
/// - Consumer (main): runs OCR on pre-loaded images (compute bound, single-threaded)
///
/// Since Vision's OCR is single-threaded per process, the pipeline hides I/O latency
/// by loading the next image while the current one is being recognized.
public func runWorker(args: CLIArgs) {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    var signalSources: [DispatchSourceSignal] = []
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }

    let config = OCRConfig(
        fast: args.fast,
        languages: args.languages,
        noCorrection: args.noCorrection,
        minTextHeight: args.minTextHeight,
        roi: args.roi,
        columnMode: args.columns
    )

    let processor = OCRProcessor(enablePDFCache: true)
    let pdfTextExtraction: Configuration.PDFTextExtraction = args.useExistingText ? .auto : .forceOCR
    let retryPolicy = args.retryPolicy
    let includeBlocks = args.format == .jsonl || args.embedTextLayer

    // Prepared work item: either a successfully loaded image or an error
    enum PreparedWork {
        case ready(WorkerTask, OCRProcessor.PreparedItem)
        case failed(WorkerTask, Error)
    }

    // Bounded buffer: at most 2 pre-loaded items waiting for OCR.
    // This caps memory usage (each loaded image can be 10-50 MB).
    let bufferLock = NSLock()
    var buffer: [PreparedWork] = []
    var bufferHead = 0
    let itemReady = DispatchSemaphore(value: 0)
    let bufferSpace = DispatchSemaphore(value: 2)
    var producerDone = false

    // Producer thread: read tasks from stdin and pre-load images
    let producerQueue = DispatchQueue(label: "avocr.worker.producer")
    producerQueue.async {
        while let line = readLine() {
            if getppid() == 1 { exit(0) }
            guard let taskData = line.data(using: .utf8),
                  let task = try? decoder.decode(WorkerTask.self, from: taskData) else {
                continue
            }

            bufferSpace.wait()

            let item = WorkItem(id: task.id, path: task.path, page: task.page)
            let work: PreparedWork = autoreleasepool {
                do {
                    let prepared = try processor.prepare(
                        item: item,
                        dpi: args.dpi,
                        pdfTextExtraction: pdfTextExtraction
                    )
                    return .ready(task, prepared)
                } catch {
                    return .failed(task, error)
                }
            }

            bufferLock.lock()
            buffer.append(work)
            bufferLock.unlock()
            itemReady.signal()
        }

        bufferLock.lock()
        producerDone = true
        bufferLock.unlock()
        itemReady.signal()
    }

    // Consumer: run OCR on pre-loaded images and write results
    func writeResult(_ task: WorkerTask, _ internalResult: OCRProcessor.InternalResult) {
        let blocks: [WorkerTextBlock]
        if includeBlocks {
            blocks = internalResult.blocks.map { block in
                WorkerTextBlock(
                    text: block.text,
                    confidence: block.confidence,
                    bbox: WorkerBBox(
                        x: Double(block.boundingBox.origin.x),
                        y: Double(block.boundingBox.origin.y),
                        width: Double(block.boundingBox.size.width),
                        height: Double(block.boundingBox.size.height)
                    )
                )
            }
        } else {
            blocks = []
        }

        let payload = WorkerResultPayload(
            id: task.id,
            path: internalResult.path,
            page: internalResult.page,
            text: internalResult.text,
            blocks: blocks
        )
        if let data = try? encoder.encode(WorkerMessage.result(payload)) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }

    func writeError(_ task: WorkerTask, _ error: Error) {
        let payload = WorkerErrorPayload(
            id: task.id,
            path: task.path,
            page: task.page,
            message: String(describing: error)
        )
        if let data = try? encoder.encode(WorkerMessage.error(payload)) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }

    while true {
        itemReady.wait()

        bufferLock.lock()
        let work: PreparedWork?
        if bufferHead < buffer.count {
            work = buffer[bufferHead]
            bufferHead += 1
            if bufferHead > 16 && bufferHead * 2 >= buffer.count {
                buffer.removeFirst(bufferHead)
                bufferHead = 0
            }
        } else {
            work = nil
        }
        let done = producerDone && bufferHead >= buffer.count
        bufferLock.unlock()

        guard let work = work else {
            if done { break }
            continue
        }

        bufferSpace.signal()

        autoreleasepool {
            switch work {
            case .ready(let task, let prepared):
                do {
                    let result = try processor.processOCR(
                        prepared: prepared,
                        config: config,
                        retryPolicy: retryPolicy
                    )
                    writeResult(task, result)
                } catch {
                    writeError(task, error)
                }
            case .failed(let task, let error):
                writeError(task, error)
            }
        }
    }
}

func processImageToResult(file: URL, config: OCRConfig) throws -> OCRResult {
    let engine = AVOCREngine()
    let image = try engine.loadImage(url: file)
    return try engine.performOCR(
        image: image,
        config: config,
        path: file.path,
        page: nil
    )
}

func processPDFPageToResult(
    page: PDFPage,
    pageIndex: Int,
    file: URL,
    config: OCRConfig,
    dpi: Int
) throws -> OCRResult {
    let engine = AVOCREngine()
    guard let image = PDFRenderer.renderPageToImage(page: page, dpi: dpi) else {
        throw OCRError.ocrFailed("Cannot render page \(pageIndex) from \(file.path)")
    }

    return try engine.performOCR(
        image: image,
        config: config,
        path: file.path,
        page: pageIndex
    )
}

func runSelfTest(args: CLIArgs, output: OutputStreamProtocol = StandardErrorStream()) {
    output.write("Running self-test...\n")

    let testText = "Hello AVOCR"

    guard let image = createTestImage(text: testText) else {
        output.write("Failed to create test image\n")
        exit(1)
    }

    let config = OCRConfig(
        fast: args.fast,
        languages: ["en-US"],
        noCorrection: false,
        minTextHeight: nil,
        roi: nil,
        columnMode: .auto
    )

    do {
        let result = try AVOCREngine().performOCR(
            image: image,
            config: config,
            path: "test",
            page: nil
        )

        let detectedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if detectedText.lowercased().contains("hello") {
            output.write("✓ Self-test passed: OCR detected text\n")
            output.write("  Input: \(testText)\n")
            output.write("  Output: \(detectedText)\n")
        } else {
            output.write("✗ Self-test failed: OCR did not detect expected text\n")
            output.write("  Expected: \(testText)\n")
            output.write("  Got: \(detectedText)\n")
            exit(1)
        }
    } catch {
        output.write("✗ Self-test failed: \(error)\n")
        exit(1)
    }
}

func createTestImage(text: String) -> CGImage? {
    let width = 800
    let height = 200

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    ) else {
        return nil
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48),
        .foregroundColor: NSColor.black
    ]

    let attributedString = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributedString)

    context.textPosition = CGPoint(x: 50, y: 80)
    CTLineDraw(line, context)

    return context.makeImage()
}
