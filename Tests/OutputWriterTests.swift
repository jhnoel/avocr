import XCTest
import os
@testable import AVOCRLib

final class OutputWriterTests: XCTestCase {
    var tempDir: URL!
    
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
    
    // MARK: - Text Format Tests

    func testWriteStdoutTextWithInMemoryOutput() throws {
        let output = InMemoryOutputStream()
        let writer = OutputWriter(
            outputDir: nil,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false,
            output: output
        )

        let result = OCRResult(
            text: "Hello stdout",
            blocks: [],
            path: "/test/document.pdf",
            page: 0
        )

        try writer.write(result: result)
        writer.close()

        let content = output.text
        XCTAssertTrue(content.contains("=== Page 0 ==="))
        XCTAssertTrue(content.contains("Hello stdout"))
    }
    
    func testWriteTextToFile() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result = OCRResult(
            text: "Hello World",
            blocks: [],
            path: "/test/document.pdf",
            page: 0
        )
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("document.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("Hello World"))
    }
    
    func testWriteTextWithNoHeaders() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: true,
            emitPageMarkers: false
        )
        
        let result = OCRResult(
            text: "Test content",
            blocks: [],
            path: "/test/document.pdf",
            page: 0
        )
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("document.txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertEqual(content.trimmingCharacters(in: .whitespacesAndNewlines), "Test content")
    }
    
    func testWriteMultiplePages() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result1 = OCRResult(text: "Page 1", blocks: [], path: "/test/doc.pdf", page: 0)
        let result2 = OCRResult(text: "Page 2", blocks: [], path: "/test/doc.pdf", page: 1)
        
        try writer.write(result: result1)
        try writer.write(result: result2)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        
        XCTAssertTrue(content.contains("Page 1"))
        XCTAssertTrue(content.contains("Page 2"))
    }
    
    // MARK: - Per-Page Mode Tests
    
    func testWritePerPage() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: true,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result1 = OCRResult(text: "Page 1 content", blocks: [], path: "/test/doc.pdf", page: 0)
        let result2 = OCRResult(text: "Page 2 content", blocks: [], path: "/test/doc.pdf", page: 1)
        
        try writer.write(result: result1)
        try writer.write(result: result2)
        writer.close()
        
        let file1 = tempDir.appendingPathComponent("doc_page0.txt")
        let file2 = tempDir.appendingPathComponent("doc_page1.txt")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
        
        let content1 = try String(contentsOf: file1, encoding: .utf8)
        let content2 = try String(contentsOf: file2, encoding: .utf8)
        
        XCTAssertTrue(content1.contains("Page 1 content"))
        XCTAssertTrue(content2.contains("Page 2 content"))
    }
    
    // MARK: - JSONL Format Tests

    func testWriteStdoutJSONLWithInMemoryOutput() throws {
        let output = InMemoryOutputStream()
        let writer = OutputWriter(
            outputDir: nil,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false,
            output: output
        )

        let result = OCRResult(
            text: "JSONL stdout",
            blocks: [],
            path: "/test/doc.pdf",
            page: 1
        )

        try writer.write(result: result)
        writer.close()

        let lines = output.text.split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let data = Data(lines[0].utf8)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["path"] as? String, "/test/doc.pdf")
        XCTAssertEqual(json?["text"] as? String, "JSONL stdout")
        XCTAssertEqual(json?["page"] as? Int, 1)
    }
    
    func testWriteJSONL() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let blocks = [
            TextBlock(
                text: "Test",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
            )
        ]
        
        let result = OCRResult(
            text: "Test content",
            blocks: blocks,
            path: "/test/doc.pdf",
            page: 0
        )
        
        try writer.write(result: result)
        writer.close()
        
        let jsonlFile = tempDir.appendingPathComponent("results.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonlFile.path))
        
        let content = try String(contentsOf: jsonlFile, encoding: .utf8)
        XCTAssertTrue(content.contains("\"path\""))
        XCTAssertTrue(content.contains("\"text\""))
        XCTAssertTrue(content.contains("\"blocks\""))
        XCTAssertTrue(content.contains("\"confidence\""))
        XCTAssertTrue(content.contains("\"bbox\""))
    }
    
    func testWriteMultipleResultsToJSONL() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result1 = OCRResult(text: "Page 1", blocks: [], path: "/test/doc.pdf", page: 0)
        let result2 = OCRResult(text: "Page 2", blocks: [], path: "/test/doc.pdf", page: 1)
        
        try writer.write(result: result1)
        try writer.write(result: result2)
        writer.close()
        
        let jsonlFile = tempDir.appendingPathComponent("results.jsonl")
        let content = try String(contentsOf: jsonlFile, encoding: .utf8)
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
    }
    
    func testWriteJSONLValidatesStructure() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let blocks = [
            TextBlock(
                text: "Test",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
            )
        ]
        let result = OCRResult(
            text: "Test content",
            blocks: blocks,
            path: "/test/doc.pdf",
            page: 0
        )
        
        try writer.write(result: result)
        writer.close()
        
        let jsonlFile = tempDir.appendingPathComponent("results.jsonl")
        let content = try String(contentsOf: jsonlFile, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        for line in lines {
            let data = line.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            XCTAssertNotNil(json["path"] as? String)
            XCTAssertNotNil(json["text"] as? String)
            XCTAssertNotNil(json["blocks"] as? [[String: Any]])
            
            if let blocks = json["blocks"] as? [[String: Any]], let block = blocks.first {
                XCTAssertNotNil(block["text"] as? String)
                XCTAssertNotNil(block["confidence"] as? Double)
                XCTAssertNotNil(block["bbox"] as? [String: Double])
            }
        }
    }
    
    // MARK: - Directory Creation Tests
    
    func testCreateOutputDirectory() throws {
        let nestedDir = tempDir.appendingPathComponent("nested/output")
        
        let writer = OutputWriter(
            outputDir: nestedDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result = OCRResult(text: "Test", blocks: [], path: "/test/doc.pdf", page: 0)
        
        try writer.write(result: result)
        writer.close()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDir.path))
    }
    
    // MARK: - Image (No Page) Tests
    
    func testWriteImageResult() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result = OCRResult(
            text: "Image content",
            blocks: [],
            path: "/test/image.jpg",
            page: nil
        )
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("image.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertTrue(content.contains("Image content"))
    }

    func testFilesWithSameBasenameUseDistinctOutputPaths() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )

        try writer.write(result: OCRResult(text: "First directory", blocks: [], path: "/input/a/page.pdf", page: 0))
        try writer.write(result: OCRResult(text: "Second directory", blocks: [], path: "/input/b/page.pdf", page: 0))
        writer.close()

        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        let textFiles = (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "txt" }

        XCTAssertEqual(textFiles.count, 2)
    }

    func testExistingTextOutputIsTruncatedOnNewRun() throws {
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        try "old content that should disappear".write(to: outputFile, atomically: true, encoding: .utf8)

        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )

        try writer.write(result: OCRResult(text: "new", blocks: [], path: "/input/doc.pdf", page: 0))
        writer.close()

        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertFalse(content.contains("old content"))
        XCTAssertEqual(content, "new\n")
    }

    func testExistingJSONLOutputIsTruncatedOnNewRun() throws {
        let outputFile = tempDir.appendingPathComponent("results.jsonl")
        try "{\"text\":\"old\"}\n".write(to: outputFile, atomically: true, encoding: .utf8)

        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false
        )

        try writer.write(result: OCRResult(text: "new", blocks: [], path: "/input/doc.pdf", page: 0))
        writer.close()

        let content = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertFalse(content.contains("\"old\""))
        XCTAssertEqual(content.split(separator: "\n").count, 1)
    }
    
    // MARK: - Concurrent Write Tests
    
    func testConcurrentWrites() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let expectation = self.expectation(description: "All writes complete")
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let errors = OSAllocatedUnfairLock(initialState: [Error]())
        
        for i in 0..<10 {
            group.enter()
            queue.async {
                defer { group.leave() }
                let result = OCRResult(
                    text: "Content \(i)",
                    blocks: [],
                    path: "/test/doc.pdf",
                    page: i
                )
                do {
                    try writer.write(result: result)
                } catch {
                    errors.withLock { $0.append(error) }
                }
            }
        }
        
        group.notify(queue: .main) {
            writer.close()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Assert no errors occurred
        let capturedErrors = errors.withLock { $0 }
        XCTAssertTrue(capturedErrors.isEmpty, "Concurrent writes produced errors: \(capturedErrors)")
        
        // Assert all content is present
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        for i in 0..<10 {
            XCTAssertTrue(content.contains("Content \(i)"), "Missing content for page \(i)")
        }
    }
    
    // MARK: - Special Characters Tests
    
    func testWriteSpecialCharacters() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let specialText = "Special chars: é, ñ, 中文, 🎉"
        let result = OCRResult(text: specialText, blocks: [], path: "/test/doc.pdf", page: 0)
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        
        XCTAssertTrue(content.contains("é"))
        XCTAssertTrue(content.contains("中文"))
    }
    
    // MARK: - Empty Content Tests
    
    func testWriteEmptyContent() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result = OCRResult(text: "", blocks: [], path: "/test/empty.pdf", page: 0)
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("empty.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
    }
    
    // MARK: - Ordered Writes Tests
    
    func testOrderedWritesBuffer() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false,
            orderedWrites: true
        )
        
        // Write pages out of order
        let result2 = OCRResult(text: "Page 2", blocks: [], path: "/test/doc.pdf", page: 1)
        let result1 = OCRResult(text: "Page 1", blocks: [], path: "/test/doc.pdf", page: 0)
        let result3 = OCRResult(text: "Page 3", blocks: [], path: "/test/doc.pdf", page: 2)
        
        try writer.write(result: result2)
        try writer.write(result: result1)
        try writer.write(result: result3)
        writer.close()
        
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        let content = try String(contentsOf: outputFile, encoding: .utf8)
        
        // Check that pages appear in order
        let page1Index = content.range(of: "Page 1")?.lowerBound
        let page2Index = content.range(of: "Page 2")?.lowerBound
        let page3Index = content.range(of: "Page 3")?.lowerBound
        
        XCTAssertNotNil(page1Index)
        XCTAssertNotNil(page2Index)
        XCTAssertNotNil(page3Index)
        
        if let p1 = page1Index, let p2 = page2Index, let p3 = page3Index {
            XCTAssertTrue(p1 < p2)
            XCTAssertTrue(p2 < p3)
        }
    }
    
    // MARK: - Lifecycle Tests

    func testCloseIsIdempotent() throws {
        let writer = OutputWriter(
            outputDir: tempDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        let result = OCRResult(text: "Test", blocks: [], path: "/test/doc.pdf", page: 0)
        try writer.write(result: result)
        
        writer.close()
        writer.close() // Should not crash or throw
        
        let outputFile = tempDir.appendingPathComponent("doc.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
    }
}
