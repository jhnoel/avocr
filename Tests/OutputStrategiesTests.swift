import XCTest
@testable import AVOCRLib

final class OutputStrategiesTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStdoutTextStrategyWritesHeader() throws {
        let output = InMemoryOutputStream()
        let strategy = StdoutTextStrategy(output: output, noHeaders: false)
        let result = OCRResult(text: "Hello", blocks: [], path: "/test/doc.pdf", page: 0)

        try strategy.write(result: result)

        XCTAssertTrue(output.text.contains("=== Page 0 ==="))
        XCTAssertTrue(output.text.contains("Hello"))
    }

    func testStdoutJSONLStrategyWritesRecord() throws {
        let output = InMemoryOutputStream()
        let strategy = StdoutJSONLStrategy(output: output)
        let result = OCRResult(text: "JSONL", blocks: [], path: "/test/doc.pdf", page: 2)

        try strategy.write(result: result)

        let lines = output.text.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let data = Data(lines[0].utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["path"] as? String, "/test/doc.pdf")
        XCTAssertEqual(json?["page"] as? Int, 2)
    }

    func testFileTextStrategyWritesFile() throws {
        let strategy = FileTextStrategy(outputDir: tempDir.path, perPage: false, fileSystem: RealFileSystem())
        let result = OCRResult(text: "File text", blocks: [], path: "/test/doc.pdf", page: 0)

        try strategy.write(result: result)
        strategy.close()

        let outputFile = tempDir.appendingPathComponent("doc.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("File text"))
    }

    func testFileTextStrategyCreatesOutputDirectoryOnce() throws {
        let fileSystem = CountingFileSystem(base: RealFileSystem())
        let strategy = FileTextStrategy(outputDir: tempDir.path, perPage: false, fileSystem: fileSystem)

        try strategy.write(result: OCRResult(text: "First", blocks: [], path: "/test/doc.pdf", page: 0))
        try strategy.write(result: OCRResult(text: "Second", blocks: [], path: "/test/doc.pdf", page: 1))
        strategy.close()

        XCTAssertEqual(fileSystem.createDirectoryCallCount, 1)
    }

    func testFileJSONLStrategyWritesFile() throws {
        let strategy = FileJSONLStrategy(outputDir: tempDir.path, fileSystem: RealFileSystem())
        let result = OCRResult(text: "JSONL file", blocks: [], path: "/test/doc.pdf", page: 1)

        try strategy.write(result: result)
        strategy.close()

        let jsonlFile = tempDir.appendingPathComponent("results.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonlFile.path))
        let content = try String(contentsOf: jsonlFile, encoding: .utf8)
        XCTAssertTrue(content.contains("\"path\""))
    }

    func testFileJSONLStrategyCreatesOutputDirectoryOnce() throws {
        let fileSystem = CountingFileSystem(base: RealFileSystem())
        let strategy = FileJSONLStrategy(outputDir: tempDir.path, fileSystem: fileSystem)

        try strategy.write(result: OCRResult(text: "First", blocks: [], path: "/test/doc.pdf", page: 0))
        try strategy.write(result: OCRResult(text: "Second", blocks: [], path: "/test/doc.pdf", page: 1))
        strategy.close()

        XCTAssertEqual(fileSystem.createDirectoryCallCount, 1)
    }

    func testOrderedBufferingStrategyOrdersPages() throws {
        let baseStrategy = CapturingOutputStrategy()
        let strategy = OrderedBufferingStrategy(
            strategy: baseStrategy,
            shouldBuffer: { $0.page != nil }
        )

        try strategy.write(result: OCRResult(text: "Page 2", blocks: [], path: "/test/doc.pdf", page: 1))
        try strategy.write(result: OCRResult(text: "Page 1", blocks: [], path: "/test/doc.pdf", page: 0))
        strategy.close()

        XCTAssertEqual(baseStrategy.results.count, 2)
        XCTAssertEqual(baseStrategy.results.first?.text, "Page 1")
        XCTAssertEqual(baseStrategy.results.last?.text, "Page 2")
    }
}

private final class CapturingOutputStrategy: OutputStrategy {
    private(set) var results: [OCRResult] = []

    func write(result: OCRResult) throws {
        results.append(result)
    }

    func close() {}
}

private final class CountingFileSystem: FileSystemProtocol {
    private let base: FileSystemProtocol
    private(set) var createDirectoryCallCount = 0

    init(base: FileSystemProtocol) {
        self.base = base
    }

    func fileExists(atPath: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        base.fileExists(atPath: atPath, isDirectory: isDirectory)
    }

    func createDirectory(
        atPath: String,
        withIntermediateDirectories: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        createDirectoryCallCount += 1
        try base.createDirectory(
            atPath: atPath,
            withIntermediateDirectories: withIntermediateDirectories,
            attributes: attributes
        )
    }

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        base.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }

    func createFile(atPath: String, contents: Data?) -> Bool {
        base.createFile(atPath: atPath, contents: contents)
    }

    func openFileForWriting(at url: URL) throws -> FileHandle {
        try base.openFileForWriting(at: url)
    }

    func isExecutableFile(atPath: String) -> Bool {
        base.isExecutableFile(atPath: atPath)
    }
}
