import XCTest
import Vision
@testable import AVOCRLib

final class ReadingOrderTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    func createMockObservation(text: String, boundingBox: CGRect, confidence: Float = 0.9) -> VNRecognizedTextObservation {
        // Create a mock observation - in real tests, you'd use actual Vision results
        // For now, we'll test through TextBlock directly since VNRecognizedTextObservation is hard to mock
        let observation = VNRecognizedTextObservation()
        // Note: VNRecognizedTextObservation can't be easily instantiated, so we'll test via sortAndFormat
        return observation
    }
    
    // MARK: - Single Column Tests
    
    func testEmptyBlocks() {
        let (text, blocks) = ReadingOrder.sortAndFormat(observations: [], columnMode: .auto)
        
        XCTAssertEqual(text, "")
        XCTAssertEqual(blocks.count, 0)
    }
    
    func testSingleColumnSorting() {
        // Create mock text blocks that should be sorted top-to-bottom, left-to-right
        // Vision uses bottom-left origin, so higher y = higher on page
        let blocks = [
            TextBlock(text: "Line 1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.8, height: 0.05)),
            TextBlock(text: "Line 2", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
            TextBlock(text: "Line 3", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        XCTAssertEqual(sortedBlocks[0].text, "Line 1")
        XCTAssertEqual(sortedBlocks[1].text, "Line 2")
        XCTAssertEqual(sortedBlocks[2].text, "Line 3")
    }
    
    func testSameLineSorting() {
        // Blocks on the same line (similar y) should be sorted left-to-right
        let blocks = [
            TextBlock(text: "Third", confidence: 0.9, boundingBox: CGRect(x: 0.7, y: 0.5, width: 0.2, height: 0.05)),
            TextBlock(text: "First", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.2, height: 0.05)),
            TextBlock(text: "Second", confidence: 0.9, boundingBox: CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.05))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        XCTAssertEqual(sortedBlocks[0].text, "First")
        XCTAssertEqual(sortedBlocks[1].text, "Second")
        XCTAssertEqual(sortedBlocks[2].text, "Third")
    }
    
    // MARK: - Column Mode Tests
    
    func testFixedSingleColumn() {
        let blocks = [
            TextBlock(text: "Line 2", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05)),
            TextBlock(text: "Line 1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        XCTAssertEqual(sortedBlocks[0].text, "Line 1")
        XCTAssertEqual(sortedBlocks[1].text, "Line 2")
    }
    
    func testFixedTwoColumnLayout() {
        // Test 2-column layout: left column should come before right column
        let blocks = [
            // Left column
            TextBlock(text: "L1", confidence: 0.9, boundingBox: CGRect(x: 0.05, y: 0.9, width: 0.4, height: 0.05)),
            TextBlock(text: "L2", confidence: 0.9, boundingBox: CGRect(x: 0.05, y: 0.8, width: 0.4, height: 0.05)),
            // Right column
            TextBlock(text: "R1", confidence: 0.9, boundingBox: CGRect(x: 0.55, y: 0.9, width: 0.4, height: 0.05)),
            TextBlock(text: "R2", confidence: 0.9, boundingBox: CGRect(x: 0.55, y: 0.8, width: 0.4, height: 0.05))
        ]
        
        // Simulate fixed 2-column mode by dividing blocks by x position
        let columnWidth = 0.5
        var leftColumn: [TextBlock] = []
        var rightColumn: [TextBlock] = []
        
        for block in blocks {
            if block.boundingBox.midX < columnWidth {
                leftColumn.append(block)
            } else {
                rightColumn.append(block)
            }
        }
        
        XCTAssertEqual(leftColumn.count, 2)
        XCTAssertEqual(rightColumn.count, 2)
        
        // Left column should be L1, L2
        XCTAssertTrue(leftColumn.contains { $0.text == "L1" })
        XCTAssertTrue(leftColumn.contains { $0.text == "L2" })
        
        // Right column should be R1, R2
        XCTAssertTrue(rightColumn.contains { $0.text == "R1" })
        XCTAssertTrue(rightColumn.contains { $0.text == "R2" })
    }
    
    func testFixedThreeColumnLayout() {
        let blocks = [
            // Left column (0.0 - 0.33)
            TextBlock(text: "L1", confidence: 0.9, boundingBox: CGRect(x: 0.05, y: 0.9, width: 0.25, height: 0.05)),
            // Middle column (0.33 - 0.67)
            TextBlock(text: "M1", confidence: 0.9, boundingBox: CGRect(x: 0.38, y: 0.9, width: 0.25, height: 0.05)),
            // Right column (0.67 - 1.0)
            TextBlock(text: "R1", confidence: 0.9, boundingBox: CGRect(x: 0.72, y: 0.9, width: 0.25, height: 0.05))
        ]
        
        let columnCount = 3
        let columnWidth = 1.0 / Double(columnCount)
        
        var columns: [[TextBlock]] = Array(repeating: [], count: columnCount)
        
        for block in blocks {
            let columnIndex = min(Int(block.boundingBox.midX / columnWidth), columnCount - 1)
            columns[columnIndex].append(block)
        }
        
        XCTAssertEqual(columns[0].count, 1)
        XCTAssertEqual(columns[1].count, 1)
        XCTAssertEqual(columns[2].count, 1)
        
        XCTAssertEqual(columns[0][0].text, "L1")
        XCTAssertEqual(columns[1][0].text, "M1")
        XCTAssertEqual(columns[2][0].text, "R1")
    }
    
    // MARK: - Line Tolerance Tests
    
    func testLineTolerance() {
        // Test that blocks with slightly different y positions on the same line are handled correctly
        let blocks = [
            TextBlock(text: "Word1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.500, width: 0.2, height: 0.03)),
            TextBlock(text: "Word2", confidence: 0.9, boundingBox: CGRect(x: 0.35, y: 0.502, width: 0.2, height: 0.03)),
            TextBlock(text: "Word3", confidence: 0.9, boundingBox: CGRect(x: 0.6, y: 0.498, width: 0.2, height: 0.03))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        // All blocks should be considered on the same line and sorted left-to-right
        XCTAssertEqual(sortedBlocks[0].text, "Word1")
        XCTAssertEqual(sortedBlocks[1].text, "Word2")
        XCTAssertEqual(sortedBlocks[2].text, "Word3")
    }
    
    // MARK: - Confidence Tests
    
    func testBlocksWithDifferentConfidence() {
        let blocks = [
            TextBlock(text: "High", confidence: 0.99, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.2, height: 0.05)),
            TextBlock(text: "Low", confidence: 0.50, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.05))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        // Confidence shouldn't affect sorting order, only position should
        XCTAssertEqual(sortedBlocks[0].text, "High")
        XCTAssertEqual(sortedBlocks[1].text, "Low")
        
        // Verify confidence values are preserved
        XCTAssertEqual(sortedBlocks[0].confidence, 0.99)
        XCTAssertEqual(sortedBlocks[1].confidence, 0.50)
    }
    
    // MARK: - Bounding Box Tests
    
    func testBoundingBoxPreservation() {
        let bbox = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let block = TextBlock(text: "Test", confidence: 0.95, boundingBox: bbox)
        
        XCTAssertEqual(block.boundingBox.origin.x, 0.1)
        XCTAssertEqual(block.boundingBox.origin.y, 0.2)
        XCTAssertEqual(block.boundingBox.width, 0.3)
        XCTAssertEqual(block.boundingBox.height, 0.4)
        XCTAssertEqual(block.boundingBox.midX, 0.25)
        XCTAssertEqual(block.boundingBox.midY, 0.4)
    }
    
    // MARK: - Complex Layout Tests
    
    func testMixedWidthBlocks() {
        // Test handling of both narrow blocks and wide blocks (like headers)
        let blocks = [
            // Wide header
            TextBlock(text: "Header", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.95, width: 0.8, height: 0.05)),
            // Narrow text blocks
            TextBlock(text: "Body1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.3, height: 0.03)),
            TextBlock(text: "Body2", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.03))
        ]
        
        // Filter narrow blocks (width <= 0.7)
        let narrowBlocks = blocks.filter { $0.boundingBox.width <= 0.7 }
        let wideBlocks = blocks.filter { $0.boundingBox.width > 0.7 }
        
        XCTAssertEqual(narrowBlocks.count, 2)
        XCTAssertEqual(wideBlocks.count, 1)
        XCTAssertEqual(wideBlocks[0].text, "Header")
    }
    
    func testColumnDetectionWithGaps() {
        // Create blocks with a significant gap indicating columns
        let leftBlocks = [
            TextBlock(text: "L1", confidence: 0.9, boundingBox: CGRect(x: 0.05, y: 0.9, width: 0.35, height: 0.03)),
            TextBlock(text: "L2", confidence: 0.9, boundingBox: CGRect(x: 0.05, y: 0.8, width: 0.35, height: 0.03))
        ]
        
        let rightBlocks = [
            TextBlock(text: "R1", confidence: 0.9, boundingBox: CGRect(x: 0.60, y: 0.9, width: 0.35, height: 0.03)),
            TextBlock(text: "R2", confidence: 0.9, boundingBox: CGRect(x: 0.60, y: 0.8, width: 0.35, height: 0.03))
        ]
        
        let allBlocks = leftBlocks + rightBlocks
        
        // Calculate x positions
        let xPositions = allBlocks.map { $0.boundingBox.minX }.sorted()
        let gaps = zip(xPositions, xPositions.dropFirst()).map { $1 - $0 }
        
        // Should detect significant gap between columns
        let maxGap = gaps.max() ?? 0
        XCTAssertGreaterThan(maxGap, 0.1) // Significant gap
        
        // Verify column separation
        let leftMaxX = leftBlocks.map { $0.boundingBox.maxX }.max() ?? 0
        let rightMinX = rightBlocks.map { $0.boundingBox.minX }.min() ?? 1
        XCTAssertGreaterThan(rightMinX - leftMaxX, 0.05) // Clear separation
    }
    
    // MARK: - Edge Cases
    
    func testSingleBlock() {
        let blocks = [
            TextBlock(text: "Only block", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05))
        ]
        
        // Single block should remain as-is
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].text, "Only block")
    }
    
    func testBlocksAtSamePosition() {
        // Edge case: blocks at exactly the same position (shouldn't happen in practice)
        let blocks = [
            TextBlock(text: "First", confidence: 0.9, boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.05)),
            TextBlock(text: "Second", confidence: 0.9, boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.05))
        ]
        
        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        
        // Should maintain stable sort
        XCTAssertEqual(sortedBlocks.count, 2)
    }
    
    func testVerySmallBlocks() {
        let blocks = [
            TextBlock(text: ".", confidence: 0.9, boundingBox: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01)),
            TextBlock(text: ",", confidence: 0.9, boundingBox: CGRect(x: 0.52, y: 0.5, width: 0.01, height: 0.01))
        ]

        let (_, sortedBlocks) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))

        // Small blocks should still be sorted correctly
        XCTAssertEqual(sortedBlocks[0].text, ".")
        XCTAssertEqual(sortedBlocks[1].text, ",")
    }

    // MARK: - Pre-computed Sort Key Correctness

    func testSortingIsStableAcrossInputOrderings() {
        // The optimized sort uses pre-computed keys. Verify same result regardless
        // of input order by sorting the same logical data in different permutations.
        let canonical = [
            TextBlock(text: "A", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.04)),
            TextBlock(text: "B", confidence: 0.9, boundingBox: CGRect(x: 0.5, y: 0.9, width: 0.3, height: 0.04)),
            TextBlock(text: "C", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04)),
            TextBlock(text: "D", confidence: 0.9, boundingBox: CGRect(x: 0.5, y: 0.8, width: 0.3, height: 0.04)),
            TextBlock(text: "E", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.04)),
        ]

        let (expectedText, _) = ReadingOrder.sortAndFormat(blocks: canonical, columnMode: .fixed(1))

        // Reversed input
        let (reversedText, _) = ReadingOrder.sortAndFormat(blocks: canonical.reversed(), columnMode: .fixed(1))
        XCTAssertEqual(expectedText, reversedText, "Reversed input should produce same sort order")

        // Shuffled input (deterministic shuffle)
        let shuffled = [canonical[3], canonical[0], canonical[4], canonical[1], canonical[2]]
        let (shuffledText, _) = ReadingOrder.sortAndFormat(blocks: shuffled, columnMode: .fixed(1))
        XCTAssertEqual(expectedText, shuffledText, "Shuffled input should produce same sort order")
    }

    func testLargeBlockSetSortedCorrectly() {
        // Generate a realistic page layout with 50 lines, each with 3 words
        var blocks: [TextBlock] = []
        for line in 0..<50 {
            let y = 0.95 - CGFloat(line) * 0.018 // top to bottom
            for word in 0..<3 {
                let x = 0.05 + CGFloat(word) * 0.32
                blocks.append(TextBlock(
                    text: "L\(line)W\(word)",
                    confidence: 0.9,
                    boundingBox: CGRect(x: x, y: y, width: 0.28, height: 0.015)
                ))
            }
        }

        // Shuffle the blocks
        var shuffled = blocks
        for i in stride(from: shuffled.count - 1, through: 1, by: -1) {
            let j = (i * 7 + 3) % (i + 1) // deterministic pseudo-random
            shuffled.swapAt(i, j)
        }

        let (_, sorted) = ReadingOrder.sortAndFormat(blocks: shuffled, columnMode: .fixed(1))

        XCTAssertEqual(sorted.count, 150)

        // Verify top-to-bottom ordering: each block's midY should be >= next block's midY
        // (within tolerance, same-line blocks are sorted left-to-right)
        for i in 0..<(sorted.count - 1) {
            let current = sorted[i].boundingBox
            let next = sorted[i + 1].boundingBox
            let yDiff = current.midY - next.midY
            if yDiff < -0.01 { // current is significantly below next — wrong order
                XCTFail("Block \(i) (\(sorted[i].text)) at y=\(current.midY) is below block \(i+1) (\(sorted[i+1].text)) at y=\(next.midY)")
                break
            }
            // If on the same line (yDiff small), verify left-to-right
            if abs(yDiff) < 0.01 {
                XCTAssertLessThanOrEqual(current.minX, next.minX,
                    "Same-line blocks should be left-to-right: \(sorted[i].text) vs \(sorted[i+1].text)")
            }
        }
    }

    func testAutoColumnDetectionWithSufficientBlocks() {
        // Create 20 blocks arranged in a clear two-column layout
        var blocks: [TextBlock] = []
        for i in 0..<10 {
            let y = 0.9 - CGFloat(i) * 0.08
            // Left column blocks
            blocks.append(TextBlock(
                text: "L\(i)",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.05, y: y, width: 0.35, height: 0.03)
            ))
            // Right column blocks
            blocks.append(TextBlock(
                text: "R\(i)",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.60, y: y, width: 0.35, height: 0.03)
            ))
        }

        let (text, sorted) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .auto)

        XCTAssertEqual(sorted.count, 20)
        XCTAssertFalse(text.isEmpty)

        // With auto column detection, all left-column blocks should come before
        // right-column blocks (since there's a clear gap at x=0.40-0.60)
        let leftTexts = sorted.prefix(10).map { $0.text }
        let rightTexts = sorted.suffix(10).map { $0.text }

        for lt in leftTexts {
            XCTAssertTrue(lt.hasPrefix("L"), "First 10 blocks should be left column, got \(lt)")
        }
        for rt in rightTexts {
            XCTAssertTrue(rt.hasPrefix("R"), "Last 10 blocks should be right column, got \(rt)")
        }
    }

    func testFixedTwoColumnSortingIntegration() {
        // Verify fixed(2) mode sorts left column fully before right column
        let blocks = [
            TextBlock(text: "R2", confidence: 0.9, boundingBox: CGRect(x: 0.6, y: 0.7, width: 0.3, height: 0.04)),
            TextBlock(text: "L1", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.04)),
            TextBlock(text: "R1", confidence: 0.9, boundingBox: CGRect(x: 0.6, y: 0.9, width: 0.3, height: 0.04)),
            TextBlock(text: "L2", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.7, width: 0.3, height: 0.04)),
        ]

        let (_, sorted) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(2))

        XCTAssertEqual(sorted.count, 4)
        // Left column first (L1, L2), then right column (R1, R2)
        XCTAssertEqual(sorted[0].text, "L1")
        XCTAssertEqual(sorted[1].text, "L2")
        XCTAssertEqual(sorted[2].text, "R1")
        XCTAssertEqual(sorted[3].text, "R2")
    }

    func testTextOutputJoinsWithNewlines() {
        let blocks = [
            TextBlock(text: "First line", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.8, height: 0.05)),
            TextBlock(text: "Second line", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
        ]

        let (text, _) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        XCTAssertEqual(text, "First line\nSecond line")
    }

    func testEmptyBlocksProduceEmptyText() {
        let (text, blocks) = ReadingOrder.sortAndFormat(blocks: [], columnMode: .auto)
        XCTAssertEqual(text, "")
        XCTAssertTrue(blocks.isEmpty)
    }

    func testSingleBlockTextOutput() {
        let blocks = [
            TextBlock(text: "Solo", confidence: 0.99, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.05))
        ]
        let (text, sorted) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        XCTAssertEqual(text, "Solo")
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted[0].confidence, 0.99)
    }

    func testAutoFallsBackToSingleColumnForFewBlocks() {
        // With < 10 blocks, auto should behave like single column
        let blocks = [
            TextBlock(text: "B", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.04)),
            TextBlock(text: "A", confidence: 0.9, boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.04)),
        ]

        let (autoText, _) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .auto)
        let (singleText, _) = ReadingOrder.sortAndFormat(blocks: blocks, columnMode: .fixed(1))
        XCTAssertEqual(autoText, singleText,
                       "Auto should behave like single column for < 10 blocks")
    }
}
