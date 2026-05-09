# Test Improvement Plan

This document outlines improvements needed for the avocr test suite based on a comprehensive review.

## Executive Summary

The test suite provides decent coverage of core functionality but has several weaknesses:
- Vacuous assertions that always pass
- Tests that re-implement logic instead of testing production code
- Weak validation of structured output (JSONL)
- Missing error path coverage
- Flaky concurrency tests

## Priority Levels

- **P0**: Critical issues that undermine test confidence
- **P1**: Important gaps that should be addressed soon
- **P2**: Nice-to-have improvements

---

## P0: Critical Fixes

### 1. Fix Vacuous Assertions

**File**: `CLIArgsTests.swift`

```swift
// BEFORE (always passes)
XCTAssertTrue(error is ValidationError || error is any Error)

// AFTER
XCTAssertTrue(error is ValidationError, "Expected ValidationError, got \(type(of: error))")
```

**File**: `IntegrationTests.swift`

```swift
// BEFORE (always true)
XCTAssertGreaterThanOrEqual(result.blocks.count, 0)

// AFTER (if blocks are expected)
XCTAssertGreaterThan(result.blocks.count, 0, "Expected OCR to detect text blocks")
```

### 2. ReadingOrderTests: Actually Test Production Code

**Problem**: Most tests create `TextBlock` arrays and re-implement sorting inline, testing Swift's `sorted()` rather than `ReadingOrder.sortAndFormat`.

**Solution**: Refactor `ReadingOrder` to expose a testable interface:

```swift
// In AVOCRLib/ReadingOrder.swift
extension ReadingOrder {
    static func sortAndFormat(blocks: [TextBlock], columnMode: ColumnMode) -> (String, [TextBlock]) {
        // Core logic extracted here
    }
}
```

Then rewrite tests to call this directly:

```swift
func testSingleColumnSorting() {
    let blocks = [
        TextBlock(text: "Line 3", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05)),
        TextBlock(text: "Line 1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.8, height: 0.05)),
        TextBlock(text: "Line 2", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05))
    ]
    
    let (text, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .auto)
    
    XCTAssertEqual(sortedBlocks[0].text, "Line 1")
    XCTAssertEqual(sortedBlocks[1].text, "Line 2")
    XCTAssertEqual(sortedBlocks[2].text, "Line 3")
    XCTAssertTrue(text.contains("Line 1"))
}
```

### 3. Fix Concurrency Test

**File**: `OutputWriterTests.swift`

```swift
// BEFORE (swallows errors, only checks file exists)
queue.async {
    try? writer.write(result: result)  // Errors hidden!
    group.leave()
}

// AFTER
func testConcurrentWrites() throws {
    let writer = OutputWriter(...)
    let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
    let group = DispatchGroup()
    let errors = OSAllocatedUnfairLock(initialState: [Error]())
    
    for i in 0..<10 {
        group.enter()
        queue.async {
            defer { group.leave() }
            let result = OCRResult(text: "Content \(i)", blocks: [], path: "/test/doc.pdf", page: i)
            do {
                try writer.write(result: result)
            } catch {
                errors.withLock { $0.append(error) }
            }
        }
    }
    
    group.wait()
    writer.close()
    
    // Assert no errors
    let capturedErrors = errors.withLock { $0 }
    XCTAssertTrue(capturedErrors.isEmpty, "Concurrent writes produced errors: \(capturedErrors)")
    
    // Assert all content present
    let outputFile = tempDir.appendingPathComponent("doc.txt")
    let content = try String(contentsOf: outputFile, encoding: .utf8)
    for i in 0..<10 {
        XCTAssertTrue(content.contains("Content \(i)"), "Missing content for page \(i)")
    }
}
```

---

## P1: Important Gaps

### 4. Validate JSONL Structure

**File**: `OutputWriterTests.swift`

```swift
func testWriteJSONLValidatesStructure() throws {
    let writer = OutputWriter(outputDir: tempDir.path, perPage: false, format: .jsonl, noHeaders: false, emitPageMarkers: false)
    
    let blocks = [TextBlock(text: "Test", confidence: 0.95, boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))]
    let result = OCRResult(text: "Test content", blocks: blocks, path: "/test/doc.pdf", page: 0)
    
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
```

### 5. Add CLI Negative Parsing Tests

**File**: `CLIArgsTests.swift`

```swift
// MARK: - Invalid Input Tests

func testInvalidDPIThrows() {
    XCTAssertThrowsError(try parseArgs(["--dpi", "0", "test.pdf"]))
    XCTAssertThrowsError(try parseArgs(["--dpi", "-100", "test.pdf"]))
    XCTAssertThrowsError(try parseArgs(["--dpi", "abc", "test.pdf"]))
}

func testInvalidWorkersThrows() {
    XCTAssertThrowsError(try parseArgs(["--workers", "0", "test.pdf"]))
    XCTAssertThrowsError(try parseArgs(["--workers", "-1", "test.pdf"]))
}

func testInvalidFormatThrows() {
    XCTAssertThrowsError(try parseArgs(["--format", "xml", "test.pdf"]))
    XCTAssertThrowsError(try parseArgs(["--format", "", "test.pdf"]))
}

func testEmptyLanguageHandling() throws {
    // Decide expected behavior: error or fallback to default?
    let args = try parseArgs(["--lang", "", "test.pdf"])
    XCTAssertEqual(args.languages, ["en-US"]) // or XCTAssertThrowsError
}
```

### 6. Add FileEnumerator Edge Cases

**File**: `FileEnumeratorTests.swift`

```swift
// MARK: - Symlink Tests

func testSymlinkToFile() throws {
    let realFile = tempDir.appendingPathComponent("real.jpg")
    let symlink = tempDir.appendingPathComponent("link.jpg")
    
    FileManager.default.createFile(atPath: realFile.path, contents: Data())
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)
    
    let result = FileEnumerator.enumerateFiles(paths: [symlink.path], includeHidden: false)
    
    switch result {
    case .success(let files):
        XCTAssertEqual(files.count, 1)
    case .failure(let error):
        XCTFail("Symlink should be followed: \(error)")
    }
}

func testBrokenSymlink() throws {
    let symlink = tempDir.appendingPathComponent("broken.jpg")
    let nonexistent = tempDir.appendingPathComponent("nonexistent.jpg")
    
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: nonexistent)
    
    let result = FileEnumerator.enumerateFiles(paths: [symlink.path], includeHidden: false)
    
    switch result {
    case .success:
        XCTFail("Broken symlink should fail")
    case .failure(let error):
        XCTAssertTrue(error is FileEnumeratorError)
    }
}

func testHiddenDirectory() throws {
    let hiddenDir = tempDir.appendingPathComponent(".hidden")
    try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
    
    let imageInHidden = hiddenDir.appendingPathComponent("image.jpg")
    FileManager.default.createFile(atPath: imageInHidden.path, contents: Data())
    
    // Without includeHidden
    let result1 = FileEnumerator.enumerateFiles(paths: [tempDir.path], includeHidden: false)
    if case .success(let files) = result1 {
        XCTAssertFalse(files.contains { $0.path.contains(".hidden") })
    }
    
    // With includeHidden
    let result2 = FileEnumerator.enumerateFiles(paths: [tempDir.path], includeHidden: true)
    if case .success(let files) = result2 {
        XCTAssertTrue(files.contains { $0.path.contains(".hidden") })
    }
}

func testDuplicateInputPaths() throws {
    let imageFile = tempDir.appendingPathComponent("image.jpg")
    FileManager.default.createFile(atPath: imageFile.path, contents: Data())
    
    let result = FileEnumerator.enumerateFiles(
        paths: [imageFile.path, imageFile.path],
        includeHidden: false
    )
    
    switch result {
    case .success(let files):
        // Decide: dedupe or allow duplicates?
        XCTAssertEqual(files.count, 1) // Assuming dedupe
    case .failure(let error):
        XCTFail("Duplicate paths should be handled: \(error)")
    }
}
```

### 7. Add OutputWriter Edge Cases

**File**: `OutputWriterTests.swift`

```swift
// MARK: - Lifecycle Tests

func testCloseIsIdempotent() throws {
    let writer = OutputWriter(outputDir: tempDir.path, perPage: false, format: .text, noHeaders: false, emitPageMarkers: false)
    
    let result = OCRResult(text: "Test", blocks: [], path: "/test/doc.pdf", page: 0)
    try writer.write(result: result)
    
    writer.close()
    writer.close() // Should not crash or throw
    
    let outputFile = tempDir.appendingPathComponent("doc.txt")
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
}

func testEmitPageMarkers() throws {
    let writer = OutputWriter(
        outputDir: tempDir.path,
        perPage: false,
        format: .text,
        noHeaders: false,
        emitPageMarkers: true  // Test this flag
    )
    
    let result1 = OCRResult(text: "Page 1", blocks: [], path: "/test/doc.pdf", page: 0)
    let result2 = OCRResult(text: "Page 2", blocks: [], path: "/test/doc.pdf", page: 1)
    
    try writer.write(result: result1)
    try writer.write(result: result2)
    writer.close()
    
    let outputFile = tempDir.appendingPathComponent("doc.txt")
    let content = try String(contentsOf: outputFile, encoding: .utf8)
    
    // Assert page markers are present (adjust based on actual format)
    XCTAssertTrue(content.contains("--- Page 1 ---") || content.contains("[Page 1]"))
}
```

---

## P2: Nice-to-Have

### 8. WorkItemsTests: Verify PDF Page Expansion

```swift
func testBuildWorkPlanExpandsPDFPages() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    
    let pdf = tempDir.appendingPathComponent("doc.pdf")
    let pdfData = createMinimalPDF() // Creates 1-page PDF
    try pdfData.write(to: pdf)
    
    let plan = buildWorkPlan(files: [pdf])
    
    XCTAssertEqual(plan.items.count, 1, "1-page PDF should create 1 work item")
    XCTAssertEqual(plan.items[0].page, 0)
    XCTAssertEqual(plan.totalPages, 1)
}
```

### 9. Integration Test Isolation

Mark integration tests to allow selective execution:

```swift
// At top of IntegrationTests.swift
#if canImport(Vision)
import Vision
#endif

final class IntegrationTests: XCTestCase {
    
    override func setUpWithError() throws {
        #if !os(macOS)
        throw XCTSkip("Vision framework tests only run on macOS")
        #endif
    }
    
    // ... tests
}
```

Or use environment variable gating:

```swift
override func setUpWithError() throws {
    if ProcessInfo.processInfo.environment["SKIP_INTEGRATION_TESTS"] != nil {
        throw XCTSkip("Integration tests disabled via environment")
    }
}
```

---

## Implementation Checklist

| Priority | Task | File | Status |
|----------|------|------|--------|
| P0 | Fix vacuous assertion in validation test | CLIArgsTests.swift | ✅ Done |
| P0 | Fix vacuous assertion in blocks test | IntegrationTests.swift | ✅ Done |
| P0 | Refactor ReadingOrder for testability | ReadingOrder.swift + Tests | ✅ Done |
| P0 | Fix concurrency test | OutputWriterTests.swift | ✅ Done |
| P1 | Add JSONL structure validation | OutputWriterTests.swift | ✅ Done |
| P1 | Add CLI negative parsing tests | CLIArgsTests.swift | ✅ Done |
| P1 | Add symlink tests | FileEnumeratorTests.swift | ✅ Done |
| P1 | Add hidden directory test | FileEnumeratorTests.swift | ✅ Done |
| P1 | Add duplicate path test | FileEnumeratorTests.swift | ✅ Done |
| P1 | Add emitPageMarkers test | OutputWriterTests.swift | Skipped (stdout-based) |
| P1 | Add close() idempotency test | OutputWriterTests.swift | ✅ Done |
| P2 | Verify PDF page expansion | WorkItemsTests.swift | Deferred |
| P2 | Add integration test gating | IntegrationTests.swift | Deferred |

---

## Success Criteria

After implementing these improvements:

1. **No vacuous assertions** — all assertions can fail if behavior is wrong
2. **ReadingOrderTests** — directly tests `ReadingOrder` module, not reimplemented logic
3. **Concurrency test** — validates correctness, not just file existence
4. **JSONL tests** — parse and validate JSON structure
5. **Error paths** — specific error types asserted, not just "throws"
6. **Edge cases** — symlinks, hidden directories, invalid CLI inputs covered
