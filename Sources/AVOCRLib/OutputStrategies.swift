import Foundation

protocol OutputStrategy {
    func write(result: OCRResult) throws
    func close()
}

final class StdoutTextStrategy: OutputStrategy {
    private let output: OutputStreamProtocol
    private let noHeaders: Bool

    init(output: OutputStreamProtocol, noHeaders: Bool) {
        self.output = output
        self.noHeaders = noHeaders
    }

    func write(result: OCRResult) throws {
        if !noHeaders {
            let pageValue = result.page ?? 0
            let header = "=== Page \(pageValue) ==="
            output.write("\(header)\n")
        }
        output.write("\(result.text)\n")
        if !noHeaders && !result.text.isEmpty {
            output.write(data: Data([0x0A]))
        }
        output.flush()
    }

    func close() {}
}

final class StdoutJSONLStrategy: OutputStrategy {
    private let output: OutputStreamProtocol

    init(output: OutputStreamProtocol) {
        self.output = output
    }

    func write(result: OCRResult) throws {
        writeJSONL(result: result, to: output)
        output.flush()
    }

    func close() {}
}

final class FileTextStrategy: OutputStrategy {
    private let outputDir: String
    private let perPage: Bool
    private let fileSystem: FileSystemProtocol
    private var fileHandles: [String: FileHandle] = [:]
    private var outputPathsByResultKey: [String: String] = [:]
    private var sourceByOutputPath: [String: String] = [:]
    private var didEnsureOutputDirectory = false

    init(outputDir: String, perPage: Bool, fileSystem: FileSystemProtocol) {
        self.outputDir = outputDir
        self.perPage = perPage
        self.fileSystem = fileSystem
    }

    func write(result: OCRResult) throws {
        try ensureOutputDirectory()

        let outputPath = resolveOutputPath(for: result)
        let hasPage = result.page != nil

        if perPage || !hasPage {
            guard let data = result.text.data(using: .utf8) else {
                throw OCRError.ocrFailed("Unable to encode output for \(outputPath)")
            }
            _ = fileSystem.createFile(atPath: outputPath, contents: nil)
            let outputURL = URL(fileURLWithPath: outputPath)
            let outHandle = try fileSystem.openFileForWriting(at: outputURL)
            defer { try? outHandle.close() }
            try outHandle.truncate(atOffset: 0)
            outHandle.write(data)
            return
        }

        let fileHandle: FileHandle
        if let existing = fileHandles[outputPath] {
            fileHandle = existing
        } else {
            if !fileSystem.fileExists(atPath: outputPath, isDirectory: nil) {
                _ = fileSystem.createFile(atPath: outputPath, contents: nil)
            }
            fileHandle = try fileSystem.openFileForWriting(at: URL(fileURLWithPath: outputPath))
            try fileHandle.truncate(atOffset: 0)
            fileHandles[outputPath] = fileHandle
        }

        let needsLeadingNewline = fileHandle.offsetInFile > 0
        let prefix = needsLeadingNewline ? "\n" : ""
        if let data = "\(prefix)\(result.text)\n".data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    func close() {
        for (_, handle) in fileHandles {
            try? handle.close()
        }
        fileHandles.removeAll()
    }

    private func ensureOutputDirectory() throws {
        guard !didEnsureOutputDirectory else { return }
        try fileSystem.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        didEnsureOutputDirectory = true
    }

    private func resolveOutputPath(for result: OCRResult) -> String {
        let resultKey = "\(result.path)#\(result.page.map(String.init) ?? "image")"
        if let existing = outputPathsByResultKey[resultKey] {
            return existing
        }

        let baseName = URL(fileURLWithPath: result.path)
            .deletingPathExtension()
            .lastPathComponent
        let fileName: String
        if perPage, let page = result.page {
            fileName = "\(baseName)_page\(page).txt"
        } else {
            fileName = "\(baseName).txt"
        }
        let preferredPath = (outputDir as NSString).appendingPathComponent(fileName)
        let outputPath: String
        if let existingSource = sourceByOutputPath[preferredPath], existingSource != result.path {
            outputPath = (outputDir as NSString).appendingPathComponent(disambiguatedFileName(for: result, baseName: baseName))
        } else {
            outputPath = preferredPath
        }

        outputPathsByResultKey[resultKey] = outputPath
        sourceByOutputPath[outputPath] = result.path
        return outputPath
    }

    private func disambiguatedFileName(for result: OCRResult, baseName: String) -> String {
        let source = URL(fileURLWithPath: result.path).deletingPathExtension().path
        let sanitized = source
            .split(separator: "/")
            .suffix(3)
            .joined(separator: "_")
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "_" || character == "-" ? character : "_"
            }
        let stem = sanitized.isEmpty ? "\(baseName)_\(stableSuffix(for: result.path))" : String(sanitized)
        if perPage, let page = result.page {
            return "\(stem)_page\(page).txt"
        }
        return "\(stem).txt"
    }

    private func stableSuffix(for value: String) -> String {
        let hash = value.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return String(hash, radix: 16)
    }
}

final class FileJSONLStrategy: OutputStrategy {
    private let outputDir: String
    private let fileSystem: FileSystemProtocol
    private var fileHandle: FileHandle?
    private var didEnsureOutputDirectory = false

    init(outputDir: String, fileSystem: FileSystemProtocol) {
        self.outputDir = outputDir
        self.fileSystem = fileSystem
    }

    func write(result: OCRResult) throws {
        try ensureOutputDirectory()
        let handle = try openJSONLHandleIfNeeded()
        writeJSONL(result: result, to: handle)
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func ensureOutputDirectory() throws {
        guard !didEnsureOutputDirectory else { return }
        try fileSystem.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        didEnsureOutputDirectory = true
    }

    private func openJSONLHandleIfNeeded() throws -> FileHandle {
        if let handle = fileHandle {
            return handle
        }

        let jsonlPath = (outputDir as NSString).appendingPathComponent("results.jsonl")
        if !fileSystem.fileExists(atPath: jsonlPath, isDirectory: nil) {
            _ = fileSystem.createFile(atPath: jsonlPath, contents: nil)
        }
        let handle = try fileSystem.openFileForWriting(at: URL(fileURLWithPath: jsonlPath))
        try handle.truncate(atOffset: 0)
        fileHandle = handle
        return handle
    }
}

final class OrderedBufferingStrategy: OutputStrategy {
    private let strategy: OutputStrategy
    private let shouldBuffer: (OCRResult) -> Bool
    private let keyForResult: (OCRResult) -> String
    private var bufferedResults: [String: [Int: OCRResult]] = [:]

    init(
        strategy: OutputStrategy,
        shouldBuffer: @escaping (OCRResult) -> Bool,
        keyForResult: @escaping (OCRResult) -> String = { $0.path }
    ) {
        self.strategy = strategy
        self.shouldBuffer = shouldBuffer
        self.keyForResult = keyForResult
    }

    func write(result: OCRResult) throws {
        guard shouldBuffer(result), let page = result.page else {
            try strategy.write(result: result)
            return
        }

        let key = keyForResult(result)
        var pageMap = bufferedResults[key] ?? [:]
        pageMap[page] = result
        bufferedResults[key] = pageMap
    }

    func close() {
        for key in bufferedResults.keys.sorted() {
            let pageMap = bufferedResults[key] ?? [:]
            for page in pageMap.keys.sorted() {
                if let result = pageMap[page] {
                    try? strategy.write(result: result)
                }
            }
        }
        bufferedResults.removeAll()
        strategy.close()
    }
}

func writeJSONL(result: OCRResult, to outputStream: OutputStreamProtocol) {
    guard let jsonData = jsonDataForResult(result) else {
        return
    }
    outputStream.write(data: jsonData)
    outputStream.write(data: Data([0x0A]))
}

func writeJSONL(result: OCRResult, to fileHandle: FileHandle) {
    guard let jsonData = jsonDataForResult(result) else {
        return
    }
    fileHandle.write(jsonData)
    fileHandle.write(Data([0x0A]))
}

private func jsonDataForResult(_ result: OCRResult) -> Data? {
    var json: [String: Any] = [
        "path": result.path,
        "text": result.text
    ]

    if let page = result.page {
        json["page"] = page
    }

    let blockData = result.blocks.map { block in
        [
            "text": block.text,
            "confidence": block.confidence,
            "bbox": [
                "x": block.boundingBox.origin.x,
                "y": block.boundingBox.origin.y,
                "width": block.boundingBox.width,
                "height": block.boundingBox.height
            ]
        ] as [String: Any]
    }
    json["blocks"] = blockData

    return try? JSONSerialization.data(withJSONObject: json)
}
