import XCTest
import Vision
import CoreGraphics
import AppKit
import Foundation
@testable import AVOCRLib

final class IntegrationTests: XCTestCase {
    private let engine = AVOCREngine()
    
    // MARK: - AVOCREngine Integration Tests
    
    func testOCRWithSimpleImage() throws {
        guard let testImage = createTestImage(text: "Hello World", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertFalse(result.text.isEmpty)
        XCTAssertEqual(result.path, "/test/image.jpg")
        XCTAssertNil(result.page)
    }
    
    func testOCRWithFastMode() throws {
        guard let testImage = createTestImage(text: "Fast OCR Test", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let config = OCRConfig(
            fast: true,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertFalse(result.text.isEmpty)
    }
    
    func testOCRWithMinTextHeight() throws {
        guard let testImage = createTestImage(text: "Test", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: 0.05,
            roi: nil,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertNotNil(result)
    }
    
    func testOCRWithROI() throws {
        guard let testImage = createTestImage(text: "ROI Test", size: CGSize(width: 800, height: 400)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let roi = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: roi,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertNotNil(result)
    }
    
    func testOCRResultIncludesBlocks() throws {
        guard let testImage = createTestImage(text: "Block Test", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertGreaterThan(result.blocks.count, 0, "Expected OCR to detect text blocks")
        
        for block in result.blocks {
            XCTAssertFalse(block.text.isEmpty)
            XCTAssertGreaterThanOrEqual(block.confidence, 0.0)
            XCTAssertLessThanOrEqual(block.confidence, 1.0)
            XCTAssertGreaterThan(block.boundingBox.width, 0)
            XCTAssertGreaterThan(block.boundingBox.height, 0)
        }
    }
    
    // MARK: - End-to-End Workflow Tests
    
    func testCompleteWorkflowImageToText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        guard let testImage = createTestImage(text: "Integration Test", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let imageFile = tempDir.appendingPathComponent("test.jpg")
        if let data = createJPEGData(from: testImage) {
            try data.write(to: imageFile)
        }
        
        let filesResult = FileEnumerator.enumerateFiles(paths: [imageFile.path], includeHidden: false)
        guard case .success(let files) = filesResult else {
            XCTFail("Failed to enumerate files")
            return
        }
        
        XCTAssertEqual(files.count, 1)
        
        let plan = buildWorkPlan(files: files)
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.totalPages, 1)
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let image = try engine.loadImage(url: files[0])
        let result = try engine.performOCR(
            image: image,
            config: config,
            path: files[0].path
        )
        
        XCTAssertFalse(result.text.isEmpty)
        
        let outputDir = tempDir.appendingPathComponent("output")
        let writer = OutputWriter(
            outputDir: outputDir.path,
            perPage: false,
            format: .text,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        try writer.write(result: result)
        writer.close()
        
        let outputFile = outputDir.appendingPathComponent("test.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputFile.path))
        
        let outputContent = try String(contentsOf: outputFile, encoding: .utf8)
        XCTAssertFalse(outputContent.isEmpty)
    }
    
    func testCompleteWorkflowWithJSONL() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        guard let testImage = createTestImage(text: "JSONL Test", size: CGSize(width: 800, height: 200)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let imageFile = tempDir.appendingPathComponent("test.jpg")
        if let data = createJPEGData(from: testImage) {
            try data.write(to: imageFile)
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let image = try engine.loadImage(url: imageFile)
        let result = try engine.performOCR(
            image: image,
            config: config,
            path: imageFile.path
        )
        
        let outputDir = tempDir.appendingPathComponent("output")
        let writer = OutputWriter(
            outputDir: outputDir.path,
            perPage: false,
            format: .jsonl,
            noHeaders: false,
            emitPageMarkers: false
        )
        
        try writer.write(result: result)
        writer.close()
        
        let jsonlFile = outputDir.appendingPathComponent("results.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonlFile.path))
        
        let jsonlContent = try String(contentsOf: jsonlFile, encoding: .utf8)
        XCTAssertTrue(jsonlContent.contains("\"text\""))
        XCTAssertTrue(jsonlContent.contains("\"path\""))
    }
    
    // MARK: - Error Handling Tests
    
    func testOCRWithInvalidImageFile() {
        let invalidFile = URL(fileURLWithPath: "/nonexistent/image.jpg")
        
        XCTAssertThrowsError(try engine.loadImage(url: invalidFile)) { error in
            XCTAssertTrue(error is OCRError)
            if case OCRError.imageLoadFailed(let path) = error {
                XCTAssertTrue(path.contains("nonexistent"))
            }
        }
    }
    
    func testOCRWithEmptyImage() throws {
        guard let blankImage = createBlankImage(size: CGSize(width: 100, height: 100)) else {
            XCTFail("Failed to create blank image")
            return
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .auto
        )
        
        let result = try engine.performOCR(
            image: blankImage,
            config: config,
            path: "/test/blank.jpg"
        )
        
        XCTAssertTrue(result.text.isEmpty || result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
        XCTAssertEqual(result.blocks.count, 0)
    }
    
    // MARK: - Column Detection Integration
    
    func testOCRWithSingleColumnMode() throws {
        guard let testImage = createTestImage(text: "Single Column", size: CGSize(width: 800, height: 400)) else {
            XCTFail("Failed to create test image")
            return
        }
        
        let config = OCRConfig(
            fast: false,
            languages: ["en-US"],
            noCorrection: false,
            minTextHeight: nil,
            roi: nil,
            columnMode: .fixed(1)
        )
        
        let result = try engine.performOCR(
            image: testImage,
            config: config,
            path: "/test/image.jpg"
        )
        
        XCTAssertNotNil(result)
    }
    
    // MARK: - Helper Methods
    
    func createTestImage(text: String, size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
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
        
        context.textPosition = CGPoint(x: 50, y: height / 2)
        CTLineDraw(line, context)
        
        return context.makeImage()
    }
    
    func createBlankImage(size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
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
        
        return context.makeImage()
    }
    
    func createJPEGData(from image: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .jpeg, properties: [:])
    }
}
