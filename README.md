# avocr

A high-performance, macOS-native OCR command-line tool powered by Apple's Vision framework. Designed to scale across CPU cores with worker processes and handle large-scale batch OCR operations on images and PDFs.

## Features

- **Fast & Native**: Uses Apple's Vision framework (`VNRecognizeTextRequest`) for OCR
- **Parallel Processing**: Multi-process OCR workers for scalable throughput
- **Batch Processing**: Handle thousands of files with recursive directory scanning
- **Multi-format Support**: Images (PNG, JPG, TIFF, HEIC, etc.) and multi-page PDFs
- **Flexible Output**: Plain text, JSON Lines, or individual files per page
- **Smart PDF Handling**: Skip OCR for PDFs with extractable text
- **Column Detection**: Basic multi-column layout support
- **Memory Efficient**: Streams PDF pages without loading entire documents into memory

## Requirements

- macOS 13.0+ (macOS 14.0+ recommended)
- Swift 5.9+
- Apple Silicon or Intel Mac

## Dependencies

Runtime OCR and PDF handling use Apple system frameworks available on macOS:
- Vision
- PDFKit
- CoreGraphics
- ImageIO
- AppKit

The Swift package depends on [Swift Argument Parser](https://github.com/apple/swift-argument-parser) for command-line parsing. Swift Package Manager resolves it automatically during `swift build` or `swift test`; no separate OCR engine, model download, or external binary is required.

## Installation

### Build from source

```bash
git clone https://github.com/fctrbl/avocr
cd avocr
swift build -c release
```

The binary will be available at `.build/release/avocr`.

### Install to PATH

```bash
swift build -c release
sudo cp .build/release/avocr /usr/local/bin/avocr
```

## Usage

### Basic Examples

OCR a single image (writes `document.txt` to the current directory):
```bash
avocr document.jpg
```

OCR a PDF with all pages (writes `report.txt` to the current directory):
```bash
avocr report.pdf
```

OCR all images in a directory:
```bash
avocr images/
```

Use 8 concurrent workers with fast mode:
```bash
avocr --workers 8 --fast large-document.pdf
```

### Output Options

Output to individual text files:
```bash
avocr --output ./output documents/
```

Split PDF pages into separate files:
```bash
avocr --output ./output --per-page report.pdf
```

Output as JSON Lines with bounding boxes:
```bash
avocr --stdout --format jsonl document.pdf > results.jsonl
```

Quiet mode (text only, no headers):
```bash
avocr --no-headers document.pdf
```

### Default Output Paths

By default, `avocr` writes files to the current working directory. Use `--stdout` to stream results instead, or `--output <dir>` to choose a destination directory.

File output uses these names:
- Single image: `<basename>.txt`
- PDF combined text: `<basename>.txt`
- PDF with `--per-page`: `<basename>_page<page>.txt`
- File JSONL output: `results.jsonl`

Output files are regenerated on each run rather than appended to. If one batch contains multiple files with the same basename from different directories, `avocr` keeps the first simple filename and gives later collisions a path-derived filename so results are not merged or overwritten.

Examples:
```bash
avocr ~/scans/invoice.pdf
# writes ./invoice.txt

avocr --output ./text ~/scans/invoice.pdf
# writes ./text/invoice.txt

avocr --output ./text --per-page ~/scans/invoice.pdf
# writes ./text/invoice_page0.txt, ./text/invoice_page1.txt, ...

avocr --output ./text --format jsonl ~/scans/
# writes ./text/results.jsonl
```


### Advanced Options

**Language Support**
```bash
# Multiple languages
avocr --lang en-US,fr-FR,de-DE document.pdf

# Disable language correction
avocr --no-correction handwritten.jpg
```

**PDF Optimization**
```bash
# Lower DPI for faster processing (trades quality for speed)
avocr --dpi 200 large.pdf

# Prefer embedded text when available (default)
avocr mixed-content.pdf

# Force OCR even when PDF has embedded text
avocr --force-ocr mixed-content.pdf

# High DPI for better accuracy on low-quality scans
avocr --dpi 400 poor-quality-scan.pdf

# Retry transient OCR errors (e.g. GPU busy)
avocr --retries 2 large.pdf
```

**Column Detection**
```bash
# Auto-detect columns (default)
avocr --columns auto newspaper.pdf

# Force single column
avocr --columns 1 document.pdf

# Force 2-column layout
avocr --columns 2 newspaper.pdf
```

**Progress Tracking**
```bash
avocr documents/
```

**Region of Interest**
```bash
# OCR only top-right quadrant (normalized 0-1 coordinates)
avocr --roi 0.5,0.5,0.5,0.5 document.pdf
```

### Batch Processing Examples

Process entire directory tree:
```bash
avocr --workers 12 --output ./ocr-output ~/Documents/scans/
```

Include hidden files:
```bash
avocr --include-hidden ~/Documents/
```

High-quality OCR with maximum accuracy:
```bash
avocr --dpi 400 --lang en-US --columns auto important-document.pdf
```

## Command-Line Options

```
-h, --help                 Show help message
--workers <N>              Number of worker processes (default: CPU count; use 'max')
--fast                     Use fast recognition level (less accurate, faster)
--lang <langs>             Comma-separated language codes (default: en-US)
--no-correction            Disable language correction
--min-text-height <f>      Minimum text height in normalized coordinates (0-1)
--roi <x,y,w,h>            Region of interest in normalized coordinates (0-1)
--dpi <N>                  PDF render DPI (default: 300, range: 72-600)
--force-ocr                Force OCR even when PDF has embedded text
--use-existing-text        Use embedded PDF text when available (default)
--embed-text-layer         Output searchable PDFs with an OCR text layer
--output <dir>             Write output files to directory (default: current directory)
--stdout                   Write output to stdout
--per-page                 Write one .txt file per page
--format <text|jsonl>      Output format (default: text)
--no-headers               Suppress headers, output only raw text
--no-progress              Disable progress output
--columns <auto|1|2|3>     Column detection mode (default: auto)
--include-hidden           Include hidden files when scanning directories
--retries <N>               Retries for transient OCR errors (default: 0)
```

## Performance Tuning

### Concurrency (`--workers`)

- **Default**: CPU core count
- **Apple Silicon M1/M2**: Try `--workers 8` to `--workers 12` for optimal throughput
- **Apple Silicon M3/M4**: Try `--workers 12` to `--workers 16`
- **Intel Macs**: Start with `--workers 4` to `--workers 8`

Higher concurrency increases throughput but also memory usage. Monitor Activity Monitor if processing very large files.

### Recognition Level

- **`--fast`**: ~2-3x faster, good for clean printed text
- **Default (accurate)**: Best quality, use for complex layouts or poor scans

### DPI Settings

- **200 DPI**: Fast, good for clean documents
- **300 DPI** (default): Balanced quality and speed
- **400 DPI**: Best for low-quality scans or small text

Higher DPI increases memory usage and processing time significantly.

### Benchmark Example

```bash
$ avocr --workers 12 --fast test-pdfs/
Found 50 file(s) to process
Using 12 concurrent workers

Completed: 500 pages
Errors: 0
Duration: 45.2s
Throughput: 11.06 pages/sec
```

## Output Formats

### Plain Text (Default)

```
=== Page 0 ===
This is the OCR text from page 1.

=== Page 1 ===
This is the OCR text from page 2.
```

### JSON Lines (`--format jsonl`)

Each line is a JSON object:
```json
{"path":"doc.pdf","page":0,"text":"Extracted text...","blocks":[{"text":"Line 1","confidence":0.95,"bbox":{"x":0.1,"y":0.8,"width":0.8,"height":0.05}}]}
{"path":"doc.pdf","page":1,"text":"More text...","blocks":[...]}
```

Fields:
- `path`: Source file path
- `page`: Page number (null for images)
- `text`: Full extracted text
- `blocks`: Array of text blocks with confidence and bounding boxes

## Self-Test


## Known Limitations

- **Handwriting**: Vision's handwriting recognition is limited; works best on printed text
- **Complex Layouts**: Auto column detection is heuristic-based and may not handle very complex multi-column layouts perfectly
- **Rotated Text**: Vision handles minor skew but not fully rotated text
- **Tables**: No special table extraction; text is read in visual order
- **Languages**: Limited to languages supported by Vision framework (see Apple documentation)

## Architecture

- **CLIArgs**: Command-line argument parsing
- **FileEnumerator**: Recursive directory traversal and file filtering
- **AVOCREngine**: Core OCR using VNRecognizeTextRequest
- **PDFRenderer**: PDF page to CGImage rendering via PDFKit
- **ReadingOrder**: Text block sorting with column detection
- **OutputWriter**: Multi-format output (stdout, files, JSONL)
- **MultiprocessCoordinator**: Worker process orchestration and result ordering

## Performance Characteristics

- **Memory**: ~100-200 MB baseline + ~10-50 MB per concurrent page (depends on DPI)
- **CPU**: Scales with `--workers` up to CPU core count
- **Throughput**: On Apple Silicon M1, expect 5-15 pages/sec depending on complexity and settings

## Troubleshooting

**Out of memory errors:**
- Reduce `--workers` concurrency
- Lower `--dpi` setting
- Process files in smaller batches

**Poor accuracy:**
- Increase `--dpi` to 400
- Remove `--fast` flag
- Verify correct `--lang` setting
- Check if input quality is sufficient

**Slow performance:**
- Increase `--workers` to match CPU cores
- Add `--fast` flag
- Reduce `--dpi` to 200
- Default behavior uses embedded PDF text when available

## Contributing

Contributions welcome! Areas for improvement:
- Better column detection algorithms
- Table extraction support
- Watch mode (`--watch`) for directory monitoring
- Additional output formats

## License

This is free and unencumbered software released into the public domain. See [LICENSE](LICENSE) for details.

## Credits

Built using Apple's Vision framework, PDFKit, and Swift Argument Parser.
