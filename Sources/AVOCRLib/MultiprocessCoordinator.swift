import Foundation
import Darwin
import PDFKit

struct WorkerLineBuffer {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        buffer.append(data)
        var lines: [Data] = []
        var searchStart = buffer.startIndex
        var consumedThrough: Data.Index?

        while let newlineIndex = buffer[searchStart...].firstIndex(of: 0x0A) {
            if newlineIndex > searchStart {
                lines.append(buffer.subdata(in: searchStart..<newlineIndex))
            }
            consumedThrough = newlineIndex
            searchStart = buffer.index(after: newlineIndex)
        }

        if let consumedThrough {
            buffer.removeSubrange(buffer.startIndex...consumedThrough)
        }

        return lines
    }
}

struct MultiprocessCoordinator {
    private final class WorkerState {
        let id: Int
        let process: ProcessProtocol
        let stdinHandle: FileHandle
        let stdoutHandle: FileHandle
        var lineBuffer = WorkerLineBuffer()
        var inflight = 0
        var inflightTasks: [WorkerTask] = []
        var isClosed: Bool = false

        init(id: Int, process: ProcessProtocol, stdinHandle: FileHandle, stdoutHandle: FileHandle) {
            self.id = id
            self.process = process
            self.stdinHandle = stdinHandle
            self.stdoutHandle = stdoutHandle
        }
    }

    static func runMultiprocess(
        files: [URL],
        args: CLIArgs,
        dependencies: RuntimeDependencies
    ) throws -> ProcessingResult {
        let plan = buildWorkPlan(
            files: files,
            logger: dependencies.logger,
            batchByDocument: args.batchByDocument
        )
        let items = plan.items
        if items.isEmpty {
            dependencies.logger.info("No supported files to process")
            return ProcessingResult()
        }

        let workerCount = max(1, min(args.jobs, items.count))
        let maxInflight = max(1, args.prefetch)

        if !args.noHeaders && args.format != .jsonl && args.progressFormat != .json {
            let workerLabel = args.jobsIsAuto ? "Running with \(workerCount) workers (Auto)" : "Running with \(workerCount) workers"
            dependencies.logger.info(workerLabel)
            dependencies.logger.info("Processing \(items.count) page(s)")
        }

        let progressReporter = ProgressReporterFactory.makeReporter(
            format: args.progressFormat,
            enabled: args.progressEnabled,
            output: dependencies.errorOutput
        )
        progressReporter.start(totalPages: items.count)

        let writer = OutputWriter(
            outputDir: args.outputDir,
            perPage: args.perPage,
            format: args.format,
            noHeaders: args.noHeaders,
            emitPageMarkers: false,
            orderedWrites: true,
            output: dependencies.output,
            fileSystem: dependencies.fileSystem
        )

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let stateQueue = DispatchQueue(label: "avocr.multiprocess.state")
        let outputQueue = DispatchQueue(label: "avocr.multiprocess.output")

        var nextTaskIndex = 0
        var completedPages = 0
        var errors = 0
        let startTime = Date()

        // Accumulate OCR blocks per PDF when embedding text layers
        var pdfPageResults: [String: [(pageIndex: Int, blocks: [TextBlock])]] = [:]

        var remainingPagesByPath: [String: Int] = [:]
        for item in items {
            remainingPagesByPath[item.path, default: 0] += 1
        }
        let total = items.count

        let completionGroup = DispatchGroup()
        for _ in items {
            completionGroup.enter()
        }

        var workers: [WorkerState] = []
        var isCancelling = false
        var shouldStopScheduling = false
        let signalQueue = DispatchQueue(label: "avocr.multiprocess.signal")
        var signalSources: [DispatchSourceSignal] = []
        var pendingCompletions = items.count

        func terminateWorkers(force: Bool) {
            if force {
                for worker in workers {
                    let pid = worker.process.processIdentifier
                    if pid > 0 {
                        kill(pid, SIGKILL)
                    }
                }
            } else {
                for worker in workers {
                    worker.process.terminate()
                }
            }

            // Release all pending completions so wait() can return
            stateQueue.async {
                while pendingCompletions > 0 {
                    pendingCompletions -= 1
                    completionGroup.leave()
                }
            }
        }

        func closeWorkerInput(_ worker: WorkerState) {
            if worker.isClosed {
                return
            }
            worker.isClosed = true
            try? worker.stdinHandle.close()
        }

        func closeAllWorkerInputs() {
            for worker in workers {
                closeWorkerInput(worker)
            }
        }

        func cancelUnassignedCompletions() {
            let unassigned = max(0, items.count - nextTaskIndex)
            guard unassigned > 0 else { return }
            nextTaskIndex = items.count
            for _ in 0..<unassigned where pendingCompletions > 0 {
                pendingCompletions -= 1
                completionGroup.leave()
            }
        }

        func stopSchedulingNewWork() {
            guard !shouldStopScheduling else { return }
            shouldStopScheduling = true
            cancelUnassignedCompletions()
            closeAllWorkerInputs()
        }

        func shouldStopAfterError() -> Bool {
            if args.failFast {
                return true
            }
            if let maxErrors = args.maxErrors, errors >= maxErrors {
                return true
            }
            return false
        }

        @discardableResult
        func sendNextTask(to worker: WorkerState) -> Bool {
            guard !worker.isClosed, !shouldStopScheduling, nextTaskIndex < items.count else {
                closeWorkerInput(worker)
                return false
            }

            let item = items[nextTaskIndex]
            nextTaskIndex += 1
            let task = WorkerTask(id: item.id, path: item.path, page: item.page)
            guard let data = try? encoder.encode(task) else {
                dependencies.logger.error("Failed to encode worker task")
                closeWorkerInput(worker)
                return false
            }
            worker.stdinHandle.write(data)
            worker.stdinHandle.write(Data([0x0A]))
            worker.inflight += 1
            worker.inflightTasks.append(task)
            return true
        }

        func fillWorkerQueue(_ worker: WorkerState) {
            while worker.inflight < maxInflight {
                if !sendNextTask(to: worker) {
                    break
                }
            }
        }

        func noteCompletion(path: String?) {
            completedPages += 1
            guard let path = path, let remaining = remainingPagesByPath[path] else {
                return
            }
            let nextRemaining = remaining - 1
            if nextRemaining <= 0 {
                remainingPagesByPath.removeValue(forKey: path)
                progressReporter.update(completedPages: completedPages, totalPages: total)
            } else {
                remainingPagesByPath[path] = nextRemaining
            }
        }

        func handleMessage(_ message: WorkerMessage, from worker: WorkerState) {
            if worker.inflight > 0 {
                worker.inflight -= 1
            }

            switch message {
            case .result(let resultMessage):
                worker.inflightTasks.removeAll { $0.id == resultMessage.id }
                let blocks: [TextBlock]
                if args.format == .jsonl || args.embedTextLayer {
                    blocks = resultMessage.blocks.map { block in
                        TextBlock(
                            text: block.text,
                            confidence: block.confidence,
                            boundingBox: CGRect(
                                x: block.bbox.x,
                                y: block.bbox.y,
                                width: block.bbox.width,
                                height: block.bbox.height
                            )
                        )
                    }
                } else {
                    blocks = []
                }

                if args.embedTextLayer, let pageIndex = resultMessage.page {
                    var entries = pdfPageResults[resultMessage.path] ?? []
                    entries.append((pageIndex: pageIndex, blocks: blocks))
                    pdfPageResults[resultMessage.path] = entries
                } else if !args.embedTextLayer {
                    let result = OCRResult(
                        text: resultMessage.text,
                        blocks: blocks,
                        path: resultMessage.path,
                        page: resultMessage.page
                    )

                    outputQueue.async {
                        do {
                            try writer.write(result: result)
                        } catch {
                            dependencies.logger.error("\(error)")
                        }
                    }
                }

                noteCompletion(path: resultMessage.path)

            case .error(let errorMessage):
                worker.inflightTasks.removeAll { $0.id == errorMessage.id }
                errors += 1
                dependencies.logger.error(errorMessage.message)
                noteCompletion(path: errorMessage.path)
            }

            if pendingCompletions > 0 {
                pendingCompletions -= 1
                completionGroup.leave()
            }
            if case .error = message, shouldStopAfterError() {
                stopSchedulingNewWork()
            } else {
                fillWorkerQueue(worker)
            }
        }

        func handleDecodeFailure(from worker: WorkerState) {
            errors += 1
            dependencies.logger.error("Failed to decode worker output")
            noteCompletion(path: nil)
            if pendingCompletions > 0 {
                pendingCompletions -= 1
                completionGroup.leave()
            }
            fillWorkerQueue(worker)
        }

        func handleWorkerData(_ data: Data, from worker: WorkerState) {
            guard !data.isEmpty else {
                worker.stdoutHandle.readabilityHandler = nil
                closeWorkerInput(worker)
                if worker.inflight > 0 || !worker.inflightTasks.isEmpty {
                    let failedTasks = worker.inflightTasks
                    worker.inflight = 0
                    worker.inflightTasks.removeAll()
                    errors += failedTasks.count
                    for task in failedTasks {
                        dependencies.logger.error("Worker \(worker.id) exited before completing task \(task.id)")
                        noteCompletion(path: task.path)
                        if pendingCompletions > 0 {
                            pendingCompletions -= 1
                            completionGroup.leave()
                        }
                    }
                    if shouldStopAfterError() {
                        stopSchedulingNewWork()
                    }
                }
                if workers.allSatisfy(\.isClosed) {
                    stopSchedulingNewWork()
                }
                return
            }

            for lineData in worker.lineBuffer.append(data) {
                if let message = try? decoder.decode(WorkerMessage.self, from: lineData) {
                    handleMessage(message, from: worker)
                } else {
                    handleDecodeFailure(from: worker)
                }
            }
        }

        guard let executableURL = resolveExecutableURL(fileSystem: dependencies.fileSystem) else {
            throw OCRError.ocrFailed("Cannot locate avocr executable")
        }

        for workerID in 0..<workerCount {
            var workerArgs: [String] = []
            workerArgs.append("--worker")

            if args.fast { workerArgs.append("--fast") }
            if args.noCorrection { workerArgs.append("--no-correction") }

            if args.format == .jsonl {
                workerArgs.append("--format")
                workerArgs.append("jsonl")
            }

            if args.useExistingText {
                workerArgs.append("--use-existing-text")
            }

            if args.embedTextLayer {
                workerArgs.append("--embed-text-layer")
            }

            if args.retries > 0 {
                workerArgs.append("--retries")
                workerArgs.append(String(args.retries))
            }

            if args.includeHidden { workerArgs.append("--include-hidden") }

            workerArgs.append("--lang")
            workerArgs.append(args.languages.joined(separator: ","))

            workerArgs.append("--dpi")
            workerArgs.append(String(args.dpi))

            workerArgs.append("--columns")
            switch args.columns {
            case .auto:
                workerArgs.append("auto")
            case .fixed(let count):
                workerArgs.append(String(count))
            }

            if let minHeight = args.minTextHeight {
                workerArgs.append("--min-text-height")
                workerArgs.append(String(minHeight))
            }

            if let roi = args.roi {
                workerArgs.append("--roi")
                workerArgs.append("\(roi.origin.x),\(roi.origin.y),\(roi.width),\(roi.height)")
            }

            let spawned = try dependencies.processSpawner.spawnProcess(
                executableURL: executableURL,
                arguments: workerArgs
            )

            let worker = WorkerState(
                id: workerID,
                process: spawned.process,
                stdinHandle: spawned.stdinHandle,
                stdoutHandle: spawned.stdoutHandle
            )

            worker.stdoutHandle.readabilityHandler = { (handle: FileHandle) in
                let data = handle.availableData
                stateQueue.async {
                    handleWorkerData(data, from: worker)
                }
            }

            workers.append(worker)
        }

        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
            source.setEventHandler {
                if isCancelling {
                    return
                }
                isCancelling = true
                dependencies.logger.warn("Received termination signal, stopping workers...")
                stateQueue.async {
                    stopSchedulingNewWork()
                }
                terminateWorkers(force: false)

                if args.gracefulTimeout > 0 {
                    signalQueue.asyncAfter(deadline: .now() + args.gracefulTimeout) {
                        terminateWorkers(force: true)
                    }
                }
            }
            source.resume()
            signalSources.append(source)
        }

        stateQueue.async {
            for worker in workers {
                fillWorkerQueue(worker)
            }
        }

        completionGroup.wait()

        outputQueue.sync {
            // Wait for pending output writes to finish.
        }

        if !args.embedTextLayer {
            writer.close()
        }

        var finalCompletedPages = 0
        var finalErrors = 0
        stateQueue.sync {
            finalCompletedPages = completedPages
            finalErrors = errors
        }

        // Assemble searchable PDFs from accumulated OCR blocks
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
                    finalErrors += 1
                    dependencies.logger.error("Failed to create searchable PDF for \(pdfPath): \(error)")
                }
            }
        }

        for worker in workers {
            worker.stdoutHandle.readabilityHandler = nil
            worker.process.waitUntilExit()
        }

        for source in signalSources {
            source.cancel()
        }

        // Note: In multiprocess mode, we don't track skipped pages separately
        // as workers report results/errors without distinguishing existing text extraction
        let processingResult = ProcessingResult(
            completed: finalCompletedPages - finalErrors,
            failed: finalErrors,
            skipped: 0
        )
        
        if args.progressEnabled {
            let duration = Date().timeIntervalSince(startTime)
            let successfulPages = max(0, finalCompletedPages - finalErrors)
            let rate = duration > 0 ? Double(successfulPages) / duration : 0
            let summary = ProgressSummary(
                completed: successfulPages,
                failed: finalErrors,
                skipped: 0,
                duration: duration,
                throughput: rate
            )
            progressReporter.finish(summary: summary)
        }

        return processingResult
    }

    private static func resolveExecutableURL(fileSystem: FileSystemProtocol) -> URL? {
        let arg0 = CommandLine.arguments.first ?? ""
        if arg0.contains("/") {
            let url = URL(fileURLWithPath: arg0)
            return fileSystem.isExecutableFile(atPath: url.path) ? url : nil
        }

        guard let pathValue = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }

        for path in pathValue.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(path)).appendingPathComponent(arg0)
            if fileSystem.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
