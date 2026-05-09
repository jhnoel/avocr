import Foundation

class OutputWriter {
    let outputDir: String?
    let perPage: Bool
    let format: OutputFormat
    let noHeaders: Bool
    let emitPageMarkers: Bool
    let orderedWrites: Bool
    let writeStdout: Bool
    private let output: OutputStreamProtocol
    private let strategy: OutputStrategy
    private let lock = NSLock()

    init(
        outputDir: String?,
        perPage: Bool,
        format: OutputFormat,
        noHeaders: Bool,
        emitPageMarkers: Bool,
        orderedWrites: Bool = false,
        output: OutputStreamProtocol = StandardOutputStream(),
        fileSystem: FileSystemProtocol = RealFileSystem()
    ) {
        self.outputDir = outputDir
        self.writeStdout = outputDir == nil
        self.perPage = perPage
        self.format = format
        self.noHeaders = noHeaders
        self.emitPageMarkers = emitPageMarkers
        self.orderedWrites = orderedWrites
        self.output = output
        let baseStrategy: OutputStrategy
        if let outputDir = outputDir {
            if format == .jsonl {
                baseStrategy = FileJSONLStrategy(outputDir: outputDir, fileSystem: fileSystem)
            } else {
                baseStrategy = FileTextStrategy(outputDir: outputDir, perPage: perPage, fileSystem: fileSystem)
            }
        } else {
            if format == .jsonl {
                baseStrategy = StdoutJSONLStrategy(output: output)
            } else {
                baseStrategy = StdoutTextStrategy(output: output, noHeaders: noHeaders)
            }
        }

        if orderedWrites {
            let shouldBuffer = { (result: OCRResult) in
                outputDir != nil && format == .text && !perPage && result.page != nil
            }
            self.strategy = OrderedBufferingStrategy(strategy: baseStrategy, shouldBuffer: shouldBuffer)
        } else {
            self.strategy = baseStrategy
        }
    }

    func write(result: OCRResult) throws {
        lock.lock()
        defer { lock.unlock() }
        if writeStdout || outputDir != nil {
            try strategy.write(result: result)
        }

        if emitPageMarkers, outputDir != nil {
            writeProgressMarker(result: result)
        }
    }

    private func writeProgressMarker(result: OCRResult) {
        if format == .jsonl {
            var json: [String: Any] = [
                "path": result.path
            ]
            if let page = result.page {
                json["page"] = page
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: json) {
                output.write(data: jsonData)
                output.write(data: Data([0x0A]))
            }
            return
        }

        let pageValue = result.page ?? 0
        let header = "=== Page \(pageValue) ==="
        output.write("\(header)\n")
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        strategy.close()
    }
}
