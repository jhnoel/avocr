import Foundation
import Vision

/// A block of text detected by OCR with position and confidence information
public struct TextBlock: Sendable {
    /// The detected text content
    public let text: String
    
    /// Confidence score (0-1) for the recognition
    public let confidence: Float
    
    /// Bounding box in normalized coordinates (0-1)
    public let boundingBox: CGRect
    
    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct ReadingOrder {
    /// Pre-computed sort key to avoid redundant CGRect property access during sorting.
    /// Sorting accesses midY and minX O(n log n) times; pre-computing reduces this to O(n).
    private struct SortKey {
        let index: Int
        let midY: CGFloat
        let minX: CGFloat
    }

    static func sortAndFormat(
        observations: [VNRecognizedTextObservation],
        columnMode: ColumnMode
    ) -> (text: String, blocks: [TextBlock]) {
        // Reserve capacity to avoid repeated array resizing
        var blocks: [TextBlock] = []
        blocks.reserveCapacity(observations.count)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            blocks.append(TextBlock(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            ))
        }

        if blocks.isEmpty {
            return ("", [])
        }

        let yTolerance = lineTolerance(for: blocks)

        let sortedBlocks: [TextBlock]
        switch columnMode {
        case .auto:
            sortedBlocks = detectAndSortColumns(blocks: blocks, yTolerance: yTolerance)
        case .fixed(let count):
            if count == 1 {
                sortedBlocks = sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
            } else {
                sortedBlocks = sortFixedColumns(blocks: blocks, columnCount: count, yTolerance: yTolerance)
            }
        }

        let text = sortedBlocks.map { $0.text }.joined(separator: "\n")
        return (text, sortedBlocks)
    }

    static func sortAndFormat(
        blocks: [TextBlock],
        columnMode: ColumnMode
    ) -> (text: String, blocks: [TextBlock]) {
        if blocks.isEmpty {
            return ("", [])
        }

        let yTolerance = lineTolerance(for: blocks)

        let sortedBlocks: [TextBlock]
        switch columnMode {
        case .auto:
            sortedBlocks = detectAndSortColumns(blocks: blocks, yTolerance: yTolerance)
        case .fixed(let count):
            if count == 1 {
                sortedBlocks = sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
            } else {
                sortedBlocks = sortFixedColumns(blocks: blocks, columnCount: count, yTolerance: yTolerance)
            }
        }

        let text = sortedBlocks.map { $0.text }.joined(separator: "\n")
        return (text, sortedBlocks)
    }

    private static func sortSingleColumn(blocks: [TextBlock], yTolerance: CGFloat) -> [TextBlock] {
        // Pre-compute midY and minX to avoid O(n log n) CGRect property accesses
        var keys = [SortKey]()
        keys.reserveCapacity(blocks.count)
        for i in 0..<blocks.count {
            let box = blocks[i].boundingBox
            keys.append(SortKey(index: i, midY: box.midY, minX: box.minX))
        }

        // Vision uses bottom-left origin: higher y = higher on page
        // Sort descending midY (top to bottom), then ascending minX (left to right)
        keys.sort { a, b in
            let yDiff = abs(a.midY - b.midY)
            if yDiff > yTolerance {
                return a.midY > b.midY
            }
            return a.minX < b.minX
        }

        return keys.map { blocks[$0.index] }
    }

    private static func detectAndSortColumns(blocks: [TextBlock], yTolerance: CGFloat) -> [TextBlock] {
        if blocks.count < 10 {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        // Pre-compute minX and width to avoid repeated property access
        var narrowMinXValues: [CGFloat] = []
        narrowMinXValues.reserveCapacity(blocks.count)
        for block in blocks where block.boundingBox.width <= 0.7 {
            narrowMinXValues.append(block.boundingBox.minX)
        }

        if narrowMinXValues.count < 10 {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        narrowMinXValues.sort()
        let gaps = zip(narrowMinXValues, narrowMinXValues.dropFirst()).map { $1 - $0 }

        let sortedGaps = gaps.sorted()
        let medianGap = sortedGaps[sortedGaps.count / 2]
        let minGap = max(0.08, medianGap * 6)
        let significantGaps = gaps.enumerated().filter { $0.element > minGap }

        if significantGaps.isEmpty {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        let bestGap = significantGaps.max { $0.element < $1.element }!
        let splitX = narrowMinXValues[bestGap.offset + 1]

        var leftColumn: [TextBlock] = []
        var rightColumn: [TextBlock] = []
        var leftMaxX: CGFloat = 0
        var rightMinX: CGFloat = 1

        for block in blocks {
            let bMinX = block.boundingBox.minX
            if bMinX < splitX {
                leftColumn.append(block)
                let bMaxX = block.boundingBox.maxX
                if bMaxX > leftMaxX { leftMaxX = bMaxX }
            } else {
                rightColumn.append(block)
                if bMinX < rightMinX { rightMinX = bMinX }
            }
        }

        let minCount = max(5, Int(Double(blocks.count) * 0.2))
        guard leftColumn.count >= minCount, rightColumn.count >= minCount else {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        guard rightMinX - leftMaxX > 0.05 else {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        let sortedLeft = sortSingleColumn(blocks: leftColumn, yTolerance: yTolerance)
        let sortedRight = sortSingleColumn(blocks: rightColumn, yTolerance: yTolerance)

        return sortedLeft + sortedRight
    }

    private static func sortFixedColumns(
        blocks: [TextBlock],
        columnCount: Int,
        yTolerance: CGFloat
    ) -> [TextBlock] {
        guard columnCount > 1 else {
            return sortSingleColumn(blocks: blocks, yTolerance: yTolerance)
        }

        let columnWidth = 1.0 / Double(columnCount)
        var columns: [[TextBlock]] = Array(repeating: [], count: columnCount)

        for block in blocks {
            let columnIndex = min(Int(block.boundingBox.midX / columnWidth), columnCount - 1)
            columns[columnIndex].append(block)
        }

        return columns.flatMap { sortSingleColumn(blocks: $0, yTolerance: yTolerance) }
    }

    private static func lineTolerance(for blocks: [TextBlock]) -> CGFloat {
        // Single-pass: collect positive heights without intermediate allocation via filter
        var heights: [CGFloat] = []
        heights.reserveCapacity(blocks.count)
        for block in blocks {
            let h = block.boundingBox.height
            if h > 0 { heights.append(h) }
        }
        guard !heights.isEmpty else { return 0.01 }

        heights.sort()
        let median = heights[heights.count / 2]
        return max(0.005, min(0.03, median * 0.6))
    }
}
