import XCTest
import PDFKit
import AppKit
import CoreGraphics
@testable import AVOCRLib

final class WorkItemsTests: XCTestCase {
    
    // MARK: - WorkItem Tests
    
    func testWorkItemCreation() {
        let item = WorkItem(id: 1, path: "/test/file.pdf", page: 0)
        
        XCTAssertEqual(item.id, 1)
        XCTAssertEqual(item.path, "/test/file.pdf")
        XCTAssertEqual(item.page, 0)
    }
    
    func testWorkItemWithoutPage() {
        let item = WorkItem(id: 5, path: "/test/image.jpg", page: nil)
        
        XCTAssertEqual(item.id, 5)
        XCTAssertEqual(item.path, "/test/image.jpg")
        XCTAssertNil(item.page)
    }
    
    // MARK: - WorkPlan Tests
    
    func testWorkPlanCreation() {
        let items = [
            WorkItem(id: 0, path: "/test/file1.pdf", page: 0),
            WorkItem(id: 1, path: "/test/file1.pdf", page: 1)
        ]
        
        let plan = WorkPlan(items: items, totalPages: 2)
        
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertEqual(plan.totalPages, 2)
    }
    
    func testEmptyWorkPlan() {
        let plan = WorkPlan(items: [], totalPages: 0)
        
        XCTAssertEqual(plan.items.count, 0)
        XCTAssertEqual(plan.totalPages, 0)
    }
    
    // MARK: - buildWorkPlan Tests
    
    func testBuildWorkPlanWithSingleImage() {
        // Create a temporary image file for testing
        let tempDir = FileManager.default.temporaryDirectory
        let imageFile = tempDir.appendingPathComponent("\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: imageFile.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: imageFile) }
        
        let files = [imageFile]
        let plan = buildWorkPlan(files: files)
        
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.totalPages, 1)
        XCTAssertEqual(plan.items[0].id, 0)
        XCTAssertEqual(plan.items[0].path, imageFile.path)
        XCTAssertNil(plan.items[0].page)
    }
    
    func testBuildWorkPlanWithMultipleImages() {
        let tempDir = FileManager.default.temporaryDirectory
        let image1 = tempDir.appendingPathComponent("\(UUID().uuidString).jpg")
        let image2 = tempDir.appendingPathComponent("\(UUID().uuidString).png")
        
        FileManager.default.createFile(atPath: image1.path, contents: Data())
        FileManager.default.createFile(atPath: image2.path, contents: Data())
        
        defer {
            try? FileManager.default.removeItem(at: image1)
            try? FileManager.default.removeItem(at: image2)
        }
        
        let files = [image1, image2]
        let plan = buildWorkPlan(files: files)
        
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertEqual(plan.totalPages, 2)
        XCTAssertEqual(plan.items[0].id, 0)
        XCTAssertEqual(plan.items[1].id, 1)
        XCTAssertNil(plan.items[0].page)
        XCTAssertNil(plan.items[1].page)
    }
    
    func testBuildWorkPlanIDsAreSequential() {
        let tempDir = FileManager.default.temporaryDirectory
        let files = (0..<5).map { i in
            let file = tempDir.appendingPathComponent("\(UUID().uuidString)_\(i).jpg")
            FileManager.default.createFile(atPath: file.path, contents: Data())
            return file
        }
        
        defer {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        
        let plan = buildWorkPlan(files: files)
        
        XCTAssertEqual(plan.items.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(plan.items[i].id, i)
        }
    }
    
    func testBuildWorkPlanEmptyFilesList() {
        let plan = buildWorkPlan(files: [])
        
        XCTAssertEqual(plan.items.count, 0)
        XCTAssertEqual(plan.totalPages, 0)
    }

    func testBuildWorkPlanBatchByDocumentSortsByPath() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let pdfA = tempDir.appendingPathComponent("a.pdf")
        let pdfB = tempDir.appendingPathComponent("b.pdf")

        let pdfData = createMinimalPDF()
        FileManager.default.createFile(atPath: pdfA.path, contents: pdfData)
        FileManager.default.createFile(atPath: pdfB.path, contents: pdfData)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plan = buildWorkPlan(files: [pdfB, pdfA], batchByDocument: true)
        let firstPath = plan.items.first?.path

        XCTAssertEqual(firstPath, pdfA.path)
        XCTAssertEqual(plan.items.first?.id, 0)
    }
    
    // MARK: - File Type Detection Tests
    
    func testWorkItemForImageTypes() {
        let imageExtensions = ["jpg", "jpeg", "png", "tif", "tiff", "bmp", "gif", "heic"]
        
        for ext in imageExtensions {
            let url = URL(fileURLWithPath: "/test/image.\(ext)")
            XCTAssertTrue(FileEnumerator.isImage(url), "\(ext) should be detected as image")
            XCTAssertFalse(FileEnumerator.isPDF(url), "\(ext) should not be detected as PDF")
        }
    }
    
    func testWorkItemForPDFType() {
        let url = URL(fileURLWithPath: "/test/document.pdf")
        XCTAssertTrue(FileEnumerator.isPDF(url))
        XCTAssertFalse(FileEnumerator.isImage(url))
    }
    
    // MARK: - Integration with FileEnumerator
    
    func testWorkPlanWithMixedFileTypes() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let image = tempDir.appendingPathComponent("image.jpg")
        let pdf = tempDir.appendingPathComponent("doc.pdf")
        
        FileManager.default.createFile(atPath: image.path, contents: Data())
        
        // Create a minimal valid PDF
        let pdfData = createMinimalPDF()
        FileManager.default.createFile(atPath: pdf.path, contents: pdfData)
        
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let files = [image, pdf]
        let plan = buildWorkPlan(files: files)
        
        // Image creates 1 item, PDF creates items based on page count
        XCTAssertGreaterThanOrEqual(plan.items.count, 1)
        
        // First item should be the image (no page)
        let imageItem = plan.items.first { $0.path == image.path }
        XCTAssertNotNil(imageItem)
        XCTAssertNil(imageItem?.page)
    }
    
    // MARK: - Edge Cases
    
    func testWorkItemWithLongPath() {
        let longPath = String(repeating: "a", count: 1000) + ".jpg"
        let item = WorkItem(id: 0, path: longPath, page: nil)
        
        XCTAssertEqual(item.path, longPath)
    }
    
    func testWorkItemWithSpecialCharactersInPath() {
        let specialPath = "/test/файл-文档-🎉.jpg"
        let item = WorkItem(id: 0, path: specialPath, page: nil)
        
        XCTAssertEqual(item.path, specialPath)
    }
    
    func testWorkPlanWithLargeNumberOfItems() {
        var items: [WorkItem] = []
        for i in 0..<1000 {
            items.append(WorkItem(id: i, path: "/test/file\(i).jpg", page: nil))
        }
        
        let plan = WorkPlan(items: items, totalPages: 1000)
        
        XCTAssertEqual(plan.items.count, 1000)
        XCTAssertEqual(plan.totalPages, 1000)
        XCTAssertEqual(plan.items.first?.id, 0)
        XCTAssertEqual(plan.items.last?.id, 999)
    }
    
    // MARK: - CGPDFDocument Page Counting Parity

    func testPageCountMatchesPDFDocumentForSinglePage() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("single.pdf")
        let pdfData = createMinimalPDF()
        FileManager.default.createFile(atPath: pdfURL.path, contents: pdfData)

        let pdfKitCount = PDFDocument(url: pdfURL)?.pageCount
        let cgPDFCount = PDFRenderer.pageCount(url: pdfURL)

        XCTAssertNotNil(pdfKitCount)
        XCTAssertNotNil(cgPDFCount)
        XCTAssertEqual(pdfKitCount, cgPDFCount,
                       "CGPDFDocument page count should match PDFDocument for single-page PDF")
    }

    func testPageCountMatchesPDFDocumentForMultiPage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("multi.pdf")
        try createMultiPagePDFFile(at: pdfURL, pageCount: 4)

        let pdfKitCount = PDFDocument(url: pdfURL)?.pageCount
        let cgPDFCount = PDFRenderer.pageCount(url: pdfURL)

        XCTAssertEqual(pdfKitCount, 4)
        XCTAssertEqual(cgPDFCount, 4)
        XCTAssertEqual(pdfKitCount, cgPDFCount)
    }

    func testBuildWorkPlanUsesCorrectPageCountForPDF() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pdfURL = tempDir.appendingPathComponent("three-pages.pdf")
        try createMultiPagePDFFile(at: pdfURL, pageCount: 3)

        let plan = buildWorkPlan(files: [pdfURL])

        XCTAssertEqual(plan.items.count, 3, "3-page PDF should produce 3 work items")
        XCTAssertEqual(plan.totalPages, 3)

        // Each item should reference the same path with sequential page indices
        for i in 0..<3 {
            XCTAssertEqual(plan.items[i].path, pdfURL.path)
            XCTAssertEqual(plan.items[i].page, i)
            XCTAssertEqual(plan.items[i].id, i)
        }
    }

    func testBuildWorkPlanHandlesInvalidPDFGracefully() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badPDF = tempDir.appendingPathComponent("corrupt.pdf")
        FileManager.default.createFile(atPath: badPDF.path, contents: "not a pdf".data(using: .utf8))

        let plan = buildWorkPlan(files: [badPDF])

        // Invalid PDF should be skipped, not crash
        XCTAssertEqual(plan.items.count, 0)
        XCTAssertEqual(plan.totalPages, 0)
    }

    func testBuildWorkPlanMixedPDFAndImagesWithCGPDF() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let image1 = tempDir.appendingPathComponent("photo.jpg")
        let image2 = tempDir.appendingPathComponent("scan.png")
        let pdf = tempDir.appendingPathComponent("document.pdf")

        FileManager.default.createFile(atPath: image1.path, contents: Data())
        FileManager.default.createFile(atPath: image2.path, contents: Data())
        try createMultiPagePDFFile(at: pdf, pageCount: 2)

        let plan = buildWorkPlan(files: [image1, pdf, image2])

        // 2 images + 2 PDF pages = 4 items
        XCTAssertEqual(plan.items.count, 4)
        XCTAssertEqual(plan.totalPages, 4)

        // Images have no page index
        let imageItems = plan.items.filter { $0.page == nil }
        XCTAssertEqual(imageItems.count, 2)

        // PDF pages have page indices
        let pdfItems = plan.items.filter { $0.page != nil }
        XCTAssertEqual(pdfItems.count, 2)
        XCTAssertEqual(pdfItems[0].page, 0)
        XCTAssertEqual(pdfItems[1].page, 1)
    }

    // MARK: - Helper Methods

    private func createMultiPagePDFFile(at url: URL, pageCount: Int) throws {
        let image = makeSmallTestImage()
        let nsImage = NSImage(cgImage: image, size: NSSize(width: 100, height: 100))
        let document = PDFDocument()
        for i in 0..<pageCount {
            if let page = PDFPage(image: nsImage) {
                document.insert(page, at: i)
            }
        }
        guard let data = document.dataRepresentation() else {
            throw OCRError.ocrFailed("Unable to create multi-page PDF")
        }
        try data.write(to: url)
    }

    private func makeSmallTestImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 40,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return context.makeImage()!
    }

    func createMinimalPDF() -> Data {
        // Create a minimal valid PDF file
        let pdfString = """
        %PDF-1.4
        1 0 obj
        <<
        /Type /Catalog
        /Pages 2 0 R
        >>
        endobj
        2 0 obj
        <<
        /Type /Pages
        /Kids [3 0 R]
        /Count 1
        >>
        endobj
        3 0 obj
        <<
        /Type /Page
        /Parent 2 0 R
        /MediaBox [0 0 612 792]
        /Contents 4 0 R
        /Resources <<
        /Font <<
        /F1 <<
        /Type /Font
        /Subtype /Type1
        /BaseFont /Helvetica
        >>
        >>
        >>
        >>
        endobj
        4 0 obj
        <<
        /Length 44
        >>
        stream
        BT
        /F1 12 Tf
        100 700 Td
        (Test) Tj
        ET
        endstream
        endobj
        xref
        0 5
        0000000000 65535 f
        0000000009 00000 n
        0000000058 00000 n
        0000000115 00000 n
        0000000317 00000 n
        trailer
        <<
        /Size 5
        /Root 1 0 R
        >>
        startxref
        410
        %%EOF
        """
        return pdfString.data(using: .utf8) ?? Data()
    }
}
