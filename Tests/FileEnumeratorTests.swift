import XCTest
@testable import AVOCRLib

final class FileEnumeratorTests: XCTestCase {
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
    
    // MARK: - Single File Tests
    
    func testEnumerateSingleImageFile() throws {
        let imageFile = tempDir.appendingPathComponent("test.jpg")
        FileManager.default.createFile(atPath: imageFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [imageFile.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(files[0].lastPathComponent, "test.jpg")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    func testEnumerateSinglePDFFile() throws {
        let pdfFile = tempDir.appendingPathComponent("test.pdf")
        FileManager.default.createFile(atPath: pdfFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [pdfFile.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(files[0].lastPathComponent, "test.pdf")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    func testEnumerateUnsupportedFileType() {
        let txtFile = tempDir.appendingPathComponent("test.txt")
        FileManager.default.createFile(atPath: txtFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [txtFile.path], includeHidden: false)
        
        switch result {
        case .success:
            XCTFail("Expected failure for unsupported file type")
        case .failure(let error):
            if case .other(let message) = error {
                XCTAssertTrue(message.contains("Unsupported file type"))
            } else {
                XCTFail("Expected 'other' error type")
            }
        }
    }
    
    func testEnumerateNonExistentFile() {
        let nonExistent = tempDir.appendingPathComponent("nonexistent.jpg").path
        
        let result = FileEnumerator.enumerateFiles(paths: [nonExistent], includeHidden: false)
        
        switch result {
        case .success:
            XCTFail("Expected failure for non-existent file")
        case .failure(let error):
            if case .fileNotFound(let path) = error {
                XCTAssertTrue(path.contains("nonexistent.jpg"))
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }
    
    // MARK: - Directory Tests
    
    func testEnumerateDirectoryWithMultipleFiles() throws {
        let subDir = tempDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let file1 = subDir.appendingPathComponent("image1.png")
        let file2 = subDir.appendingPathComponent("image2.jpg")
        let file3 = subDir.appendingPathComponent("doc.pdf")
        
        FileManager.default.createFile(atPath: file1.path, contents: Data())
        FileManager.default.createFile(atPath: file2.path, contents: Data())
        FileManager.default.createFile(atPath: file3.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [subDir.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 3)
            // Files should be sorted
            XCTAssertTrue(files[0].lastPathComponent == "doc.pdf")
            XCTAssertTrue(files[1].lastPathComponent == "image1.png")
            XCTAssertTrue(files[2].lastPathComponent == "image2.jpg")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    func testEnumerateEmptyDirectory() throws {
        let emptyDir = tempDir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        
        let result = FileEnumerator.enumerateFiles(paths: [emptyDir.path], includeHidden: false)
        
        switch result {
        case .success:
            XCTFail("Expected failure for empty directory")
        case .failure(let error):
            if case .noSupportedFiles = error {
                // Success
            } else {
                XCTFail("Expected noSupportedFiles error")
            }
        }
    }
    
    func testEnumerateDirectoryWithUnsupportedFiles() throws {
        let subDir = tempDir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let txtFile = subDir.appendingPathComponent("readme.txt")
        let mdFile = subDir.appendingPathComponent("notes.md")
        
        FileManager.default.createFile(atPath: txtFile.path, contents: Data())
        FileManager.default.createFile(atPath: mdFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [subDir.path], includeHidden: false)
        
        switch result {
        case .success:
            XCTFail("Expected failure when no supported files found")
        case .failure(let error):
            if case .noSupportedFiles = error {
                // Success
            } else {
                XCTFail("Expected noSupportedFiles error")
            }
        }
    }
    
    // MARK: - Hidden Files Tests
    
    func testExcludeHiddenFiles() throws {
        let visibleFile = tempDir.appendingPathComponent("visible.jpg")
        let hiddenFile = tempDir.appendingPathComponent(".hidden.jpg")
        
        FileManager.default.createFile(atPath: visibleFile.path, contents: Data())
        FileManager.default.createFile(atPath: hiddenFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [tempDir.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(files[0].lastPathComponent, "visible.jpg")
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    func testIncludeHiddenFiles() throws {
        let visibleFile = tempDir.appendingPathComponent("visible.jpg")
        let hiddenFile = tempDir.appendingPathComponent(".hidden.jpg")
        
        FileManager.default.createFile(atPath: visibleFile.path, contents: Data())
        FileManager.default.createFile(atPath: hiddenFile.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [tempDir.path], includeHidden: true)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 2)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    // MARK: - Recursive Directory Tests
    
    func testEnumerateNestedDirectories() throws {
        let dir1 = tempDir.appendingPathComponent("dir1")
        let dir2 = dir1.appendingPathComponent("dir2")
        
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let file1 = dir1.appendingPathComponent("image1.png")
        let file2 = dir2.appendingPathComponent("image2.jpg")
        
        FileManager.default.createFile(atPath: file1.path, contents: Data())
        FileManager.default.createFile(atPath: file2.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [dir1.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 2)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    // MARK: - Multiple Input Paths
    
    func testEnumerateMultiplePaths() throws {
        let dir1 = tempDir.appendingPathComponent("dir1")
        let dir2 = tempDir.appendingPathComponent("dir2")
        
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        
        let file1 = dir1.appendingPathComponent("image1.png")
        let file2 = dir2.appendingPathComponent("image2.jpg")
        
        FileManager.default.createFile(atPath: file1.path, contents: Data())
        FileManager.default.createFile(atPath: file2.path, contents: Data())
        
        let result = FileEnumerator.enumerateFiles(paths: [dir1.path, dir2.path], includeHidden: false)
        
        switch result {
        case .success(let files):
            XCTAssertEqual(files.count, 2)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
    // MARK: - File Type Detection Tests
    
    func testIsSupportedFile() {
        let supportedExtensions = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "heic", "pdf"]
        
        for ext in supportedExtensions {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            XCTAssertTrue(FileEnumerator.isSupportedFile(url), "\(ext) should be supported")
        }
        
        let unsupportedExtensions = ["txt", "doc", "md", "swift"]
        for ext in unsupportedExtensions {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            XCTAssertFalse(FileEnumerator.isSupportedFile(url), "\(ext) should not be supported")
        }
    }
    
    func testIsImage() {
        let imageExtensions = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "gif", "heic"]
        
        for ext in imageExtensions {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            XCTAssertTrue(FileEnumerator.isImage(url), "\(ext) should be an image")
        }
        
        let url = URL(fileURLWithPath: "/test/file.pdf")
        XCTAssertFalse(FileEnumerator.isImage(url), "PDF should not be an image")
    }
    
    func testIsPDF() {
        let pdfURL = URL(fileURLWithPath: "/test/file.pdf")
        XCTAssertTrue(FileEnumerator.isPDF(pdfURL))
        
        let imageURL = URL(fileURLWithPath: "/test/file.jpg")
        XCTAssertFalse(FileEnumerator.isPDF(imageURL))
    }
    
    func testCaseInsensitiveExtensions() {
        let variations = ["PDF", "Pdf", "pDf", "pdf"]
        for ext in variations {
            let url = URL(fileURLWithPath: "/test/file.\(ext)")
            XCTAssertTrue(FileEnumerator.isSupportedFile(url), "\(ext) should be supported (case insensitive)")
        }
    }
    
    // MARK: - Sorting Tests
    
    func testFilesSortedAlphabetically() throws {
        let files = ["zebra.jpg", "apple.png", "banana.pdf"]
        
        for filename in files {
            let file = tempDir.appendingPathComponent(filename)
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        
        let result = FileEnumerator.enumerateFiles(paths: [tempDir.path], includeHidden: false)
        
        switch result {
        case .success(let foundFiles):
            XCTAssertEqual(foundFiles.count, 3)
            XCTAssertTrue(foundFiles[0].path < foundFiles[1].path)
            XCTAssertTrue(foundFiles[1].path < foundFiles[2].path)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }
    
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
        case .failure:
            // Expected - broken symlinks should produce an error
            break
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
            // Duplicates may or may not be deduped - just verify it doesn't crash
            XCTAssertGreaterThanOrEqual(files.count, 1)
        case .failure(let error):
            XCTFail("Duplicate paths should be handled: \(error)")
        }
    }
}
