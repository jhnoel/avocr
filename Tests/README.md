# Test suite

The Swift test suite covers the CLI argument model, file discovery, work planning, OCR processing, output writing, worker protocol, multiprocess coordination, PDF rendering, retry behavior, and reading-order heuristics.

## Run

```bash
swift test
```

Useful spot checks while working on the CLI:

```bash
swift run avocr --help
swift build -c release
.build/release/avocr --version
```

## Notable coverage

- `CLIArgsTests.swift` — defaults, validation, language parsing, ROI/min-height bounds, worker settings.
- `FileEnumeratorTests.swift` — recursive directory traversal, hidden files, supported extensions, symlinks.
- `WorkItemsTests.swift` — image/PDF work-plan creation and PDF page counting.
- `OutputWriterTests.swift` / `OutputStrategiesTests.swift` — text, JSONL, stdout, truncation, filename collisions, ordered writes, searchable-PDF output destinations.
- `MultiprocessCoordinatorTests.swift` — worker EOF/error handling, fail-fast/max-errors behavior, and ordered stdout for multipage PDFs.
- `OCRProcessorTests.swift` / `RetryPolicyTests.swift` — OCR preparation, PDF cache behavior, embedded text shortcut, and transient Vision retries.
- `PDFRendererTests.swift` — page counting, rendering, and searchable-PDF primitives.
- `IntegrationTests.swift` — end-to-end OCR workflows against generated images.

## Notes

Some integration tests call Apple's Vision framework and therefore require macOS. If `swift test` cannot import XCTest in a Command Line Tools-only environment, install full Xcode or use Xcode's test runner:

```bash
xcodebuild test -scheme avocr-Package -destination 'platform=macOS'
```
