import Foundation
import PDFKit

struct ValidationStats {
    var files: Int = 0
    var pages: Int = 0
    var refChars: Int = 0
    var ocrChars: Int = 0
    var errors: Int = 0

    mutating func add(_ other: ValidationStats) {
        files += other.files
        pages += other.pages
        refChars += other.refChars
        ocrChars += other.ocrChars
        errors += other.errors
    }
}

struct OCRValidator {
    static func validate(
        files: [URL],
        args: CLIArgs,
        logger: Logger = NullLogger()
    ) {
        guard let outputDir = args.outputDir else { return }

        let jsonlMap = args.format == .jsonl ? loadJSONLTextMap(outputDir: outputDir) : [:]
        var total = ValidationStats()

        for file in files where FileEnumerator.isPDF(file) {
            guard let pdf = PDFRenderer.loadPDF(url: file) else {
                logger.warn("Cannot load PDF for validation: \(file.path)")
                continue
            }

            let fileStats = validatePDF(
                file: file,
                pdf: pdf,
                outputDir: outputDir,
                args: args,
                jsonlMap: jsonlMap,
                logger: logger
            )

            if fileStats.pages > 0 {
                let accuracy = accuracyPercent(errors: fileStats.errors, refChars: fileStats.refChars)
                logger.info(
                    "Validation: \(file.lastPathComponent) pages=\(fileStats.pages) accuracy=\(String(format: "%.2f", accuracy))%"
                )
                total.add(fileStats)
            }
        }

        if total.pages > 0 {
            let overallAccuracy = accuracyPercent(errors: total.errors, refChars: total.refChars)
            logger.info(
                "Validation summary: files=\(total.files) pages=\(total.pages) accuracy=\(String(format: "%.2f", overallAccuracy))%"
            )
        } else {
            logger.info("Validation: No embedded text available for comparison")
        }
    }

    private static func validatePDF(
        file: URL,
        pdf: PDFDocument,
        outputDir: String,
        args: CLIArgs,
        jsonlMap: [String: [Int: String]],
        logger: Logger
    ) -> ValidationStats {
        var stats = ValidationStats()
        let baseName = file.deletingPathExtension().lastPathComponent
        let filePath = file.path
        let usePerPageOutput = args.perPage || args.format == .jsonl
        var missingOutputs = 0

        if usePerPageOutput {
            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex) else { continue }
                guard let refText = PDFRenderer.extractTextFromPage(page: page) else { continue }
                if refText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

                let ocrText: String?
                if args.format == .jsonl {
                    ocrText = jsonlMap[filePath]?[pageIndex]
                } else {
                    let outputPath = (outputDir as NSString)
                        .appendingPathComponent("\(baseName)_page\(pageIndex).txt")
                    ocrText = try? String(contentsOfFile: outputPath, encoding: .utf8)
                }

                guard let ocrText = ocrText else {
                    missingOutputs += 1
                    continue
                }

                let pageStats = compareText(reference: refText, ocr: ocrText)
                stats.pages += 1
                stats.refChars += pageStats.refChars
                stats.ocrChars += pageStats.ocrChars
                stats.errors += pageStats.errors
            }
        } else {
            var referenceParts: [String] = []
            for pageIndex in 0..<pdf.pageCount {
                guard let page = pdf.page(at: pageIndex) else { continue }
                guard let text = PDFRenderer.extractTextFromPage(page: page) else { continue }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                referenceParts.append(text)
            }

            let referenceText = referenceParts.joined(separator: "\n")
            if !referenceText.isEmpty {
                let outputPath = (outputDir as NSString).appendingPathComponent("\(baseName).txt")
                if let ocrText = try? String(contentsOfFile: outputPath, encoding: .utf8) {
                    let docStats = compareText(reference: referenceText, ocr: ocrText)
                    stats.pages += max(referenceParts.count, 1)
                    stats.refChars += docStats.refChars
                    stats.ocrChars += docStats.ocrChars
                    stats.errors += docStats.errors
                } else {
                    missingOutputs = 1
                }
            }
        }

        if stats.pages > 0 {
            stats.files = 1
        }

        if missingOutputs > 0 {
            logger.warn(
                "Missing OCR output for validation (\(missingOutputs) pages) in \(file.lastPathComponent)"
            )
        }

        return stats
    }

    private static func loadJSONLTextMap(outputDir: String) -> [String: [Int: String]] {
        let jsonlPath = (outputDir as NSString).appendingPathComponent("results.jsonl")
        guard let content = try? String(contentsOfFile: jsonlPath, encoding: .utf8) else {
            return [:]
        }

        var map: [String: [Int: String]] = [:]
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let path = json["path"] as? String, let text = json["text"] as? String else { continue }
            let page = json["page"] as? Int ?? -1
            var pathMap = map[path, default: [:]]
            pathMap[page] = text
            map[path] = pathMap
        }

        return map
    }

    private static func compareText(reference: String, ocr: String) -> (refChars: Int, ocrChars: Int, errors: Int) {
        let refScalars = normalizeText(reference)
        let ocrScalars = normalizeText(ocr)
        let errors = levenshteinDistance(refScalars, ocrScalars)
        return (refScalars.count, ocrScalars.count, errors)
    }

    private static func normalizeText(_ text: String) -> [UInt32] {
        let parts = text.lowercased().split { $0.isWhitespace }
        if parts.isEmpty { return [] }
        let joined = parts.joined(separator: " ")
        return joined.unicodeScalars.map { $0.value }
    }

    private static func levenshteinDistance(_ lhs: [UInt32], _ rhs: [UInt32]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var a = lhs
        var b = rhs
        if a.count < b.count {
            swap(&a, &b)
        }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            let aVal = a[i - 1]
            for j in 1...b.count {
                let cost = aVal == b[j - 1] ? 0 : 1
                let deletion = previous[j] + 1
                let insertion = current[j - 1] + 1
                let substitution = previous[j - 1] + cost
                current[j] = min(deletion, insertion, substitution)
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }

    private static func accuracyPercent(errors: Int, refChars: Int) -> Double {
        guard refChars > 0 else { return 0 }
        let ratio = 1.0 - (Double(errors) / Double(refChars))
        return max(0.0, ratio * 100.0)
    }
}
