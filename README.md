# avocr

`avocr` is a fast, macOS-native OCR command-line tool powered by Apple's Vision framework. It handles images and PDFs, scales across worker processes, and can write plain text, JSON Lines, or searchable PDFs.

## Highlights

- **Native OCR** using `VNRecognizeTextRequest` — no model downloads or OCR server required.
- **Fast batch processing** with multiple worker processes and bounded prefetching.
- **PDF-aware behavior**: renders scanned pages, reuses embedded PDF text by default, or forces OCR when needed.
- **Flexible outputs**: stdout, per-document text files, per-page text files, JSONL with bounding boxes, or searchable PDFs.
- **Predictable ordering**: stdout and file output are emitted in input/page order even when workers finish out of order.
- **Safe defaults**: output files are regenerated per run; searchable PDF mode avoids accidental same-path overwrites unless `--overwrite` is used.

## Requirements

- macOS 13.0+ (macOS 14.0+ recommended)
- Swift 5.9+
- Apple Silicon or Intel Mac

Runtime OCR/PDF support comes from Apple system frameworks: Vision, PDFKit, CoreGraphics, ImageIO, and AppKit. Swift Package Manager resolves the only package dependency, [Swift Argument Parser](https://github.com/apple/swift-argument-parser).

## Installation

```bash
git clone https://github.com/fctrbl/avocr
cd avocr
swift build -c release
```

The binary is written to `.build/release/avocr`.

To install it on your `PATH`:

```bash
sudo cp .build/release/avocr /usr/local/bin/avocr
```

## Quick start

```bash
# OCR a PDF or image; writes ./document.txt
avocr document.pdf

# Stream text to stdout instead of creating files
avocr --stdout document.pdf > document.txt

# Process a directory recursively
avocr --output ./text ~/Documents/scans

# Faster, lower-accuracy mode with 8 workers
avocr --workers 8 --fast large-scan.pdf

# JSON Lines with text blocks and bounding boxes
avocr --stdout --format jsonl document.pdf > document.jsonl
```

Progress and logs are written to stderr, so `--stdout` is safe to pipe or redirect.

## Input formats

Supported file extensions are:

- PDFs: `.pdf`
- Images: `.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff`, `.bmp`, `.gif`, `.heic`, `.heif`, `.webp`

Directories are scanned recursively. Hidden files and hidden directories are skipped unless `--include-hidden` is set.

## Output behavior

By default, `avocr` writes output files to the current directory. Use `--stdout` to stream results, or `--output <dir>` to choose a destination directory.

Text output paths:

- Image: `<basename>.txt`
- PDF combined text: `<basename>.txt`
- PDF with `--per-page`: `<basename>_page<page>.txt` (0-based page numbers)
- JSONL file output: `results.jsonl`

Output files are truncated/regenerated on each run. If a batch contains multiple inputs with the same basename, later collisions get path-derived filenames instead of merging or overwriting earlier results.

Examples:

```bash
avocr ~/scans/invoice.pdf
# writes ./invoice.txt

avocr --output ./text ~/scans/invoice.pdf
# writes ./text/invoice.txt

avocr --output ./text --per-page ~/scans/invoice.pdf
# writes ./text/invoice_page0.txt, ./text/invoice_page1.txt, ...

avocr --output ./text --format jsonl ~/scans
# writes ./text/results.jsonl
```

### Plain text

```text
=== Page 0 ===
Text from the first page.

=== Page 1 ===
Text from the second page.
```

Use `--no-headers` for raw text only.

### JSON Lines

Each line is one page/image result:

```json
{"path":"doc.pdf","page":0,"text":"Extracted text...","blocks":[{"text":"Line 1","confidence":0.95,"bbox":{"x":0.1,"y":0.8,"width":0.8,"height":0.05}}]}
```

Fields:

- `path`: source file path
- `page`: 0-based page number; omitted for images
- `text`: full extracted text for that page/image
- `blocks`: OCR text blocks with confidence and normalized bounding boxes

## PDF behavior

### Embedded text vs OCR

For PDFs, `avocr` uses embedded text when a page already has enough extractable text. This is much faster and avoids OCR noise on born-digital PDFs.

```bash
# Default: use embedded text when available, OCR scanned pages
avocr document.pdf

# Force OCR even if the PDF has an existing text layer
avocr --force-ocr document.pdf
```

### Searchable PDFs

`--embed-text-layer` creates PDFs that preserve the original page image and add invisible OCR text so the result is searchable/selectable.

```bash
# Write ./scan_ocr.pdf if scan.pdf is in the current directory
avocr --embed-text-layer scan.pdf

# Write ./searchable/scan.pdf
avocr --embed-text-layer --output ./searchable scan.pdf

# Replace the original file intentionally
avocr --embed-text-layer --overwrite scan.pdf
```

Notes:

- Searchable PDF mode only accepts PDF inputs.
- It cannot be combined with `--stdout`, `--format jsonl`, or `--per-page`.
- Without `--overwrite`, `avocr` will not write to the same source path; it appends `_ocr` when the destination would otherwise equal the input file.

## OCR options

```bash
# Multiple languages; whitespace is OK
avocr --lang "en-US, fr-FR, de-DE" document.pdf

# Disable language correction
avocr --no-correction handwritten-or-code.png

# Region of interest: x,y,w,h in normalized 0-1 coordinates
avocr --roi 0.5,0.5,0.5,0.5 document.pdf

# Ignore very small text blocks
avocr --min-text-height 0.02 document.pdf
```

### Columns

```bash
# Auto-detect columns (default)
avocr --columns auto newspaper.pdf

# Force a fixed layout
avocr --columns 1 document.pdf
avocr --columns 2 newspaper.pdf
avocr --columns 3 tri-fold.pdf
```

Column detection is heuristic-based; use fixed columns when you know the layout.

## Performance tuning

### Workers

```bash
avocr --workers 8 scans/
avocr --workers max scans/
```

Default worker count is the active CPU count. More workers can improve throughput but also increase memory use. For very large PDFs or high DPI, reduce `--workers` first if you see memory pressure.

Starting points:

- Apple Silicon M1/M2: `--workers 8` to `--workers 12`
- Apple Silicon M3/M4: `--workers 12` to `--workers 16`
- Intel Macs: `--workers 4` to `--workers 8`

### DPI

```bash
avocr --dpi 200 clean-scan.pdf   # faster
avocr --dpi 300 document.pdf     # default balance
avocr --dpi 400 tiny-text.pdf    # slower, often more accurate
```

Allowed range is 72–600 DPI. Higher DPI can significantly increase memory and processing time.

### Fast mode

```bash
avocr --fast clean-printed-text.pdf
```

`--fast` is usually best for clean printed text. Leave it off for small text, noisy scans, or complex layouts.

### Prefetch

```bash
avocr --prefetch 1 huge.pdf
avocr --prefetch 4 many-small-images/
```

`--prefetch` controls in-flight tasks per worker. Lower values reduce memory use; higher values can help when image/PDF loading is the bottleneck.

## Progress, logs, and automation

```bash
# Quiet output except OCR text/files
avocr --no-progress document.pdf

# Machine-readable progress on stderr
avocr --progress-format json --stdout document.pdf > document.txt

# JSON-formatted logs on stderr
avocr --log-format json --verbose document.pdf
```

`--progress-format quiet` is equivalent to disabling progress. `--fail-fast`, `--max-errors <N>`, and `--retries <N>` are useful for batch jobs.

## Command-line options

```text
-h, --help                         Show help information
--version                          Show version
-i, --input <path>                 Input file/directory; can be repeated
--include-hidden                   Include hidden files during directory scans
-o, --output <dir>                 Output directory (default: current directory)
--stdout                           Write OCR results to stdout
-f, --format <text|jsonl>          Output format (default: text)
--per-page                         Write one text file per PDF page
--no-headers                       Suppress text page headers
--no-progress                      Disable progress output
--progress-format <bar|json|quiet> Progress output format (stderr)
-v, --verbose                      Enable debug logging
--log-format <text|json>           Log format (stderr)
--fast                             Use fast recognition level
-c, --columns <auto|1|2|3>         Column layout mode
-l, --lang <codes>                 Comma-separated language codes
--no-correction                    Disable Vision language correction
--min-text-height <0-1>            Minimum normalized text height
--roi <x,y,w,h>                    Normalized region of interest
--dpi <72-600>                     PDF render DPI (default: 300)
--use-existing-text                Explicitly request default embedded-text behavior
--force-ocr                        OCR PDFs even when embedded text exists
--embed-text-layer                 Create searchable PDFs
--overwrite                        Replace originals in searchable PDF mode
-j, --workers <N|max>              Worker processes
--prefetch <N>                     In-flight tasks per worker
--fail-fast                        Stop after first processing error
--max-errors <N>                   Stop after N processing errors
--retries <N>                      Retry transient Vision errors
--graceful-timeout <seconds>       Cleanup time after cancellation
```

## Troubleshooting

**The command prints help instead of running**

Pass at least one input path, or use `-i/--input`:

```bash
avocr -i ./scans -i ./photos -o ./text
```

**Out of memory or the Mac becomes sluggish**

- Reduce `--workers`
- Reduce `--prefetch`
- Lower `--dpi`
- Process a smaller batch

**Poor OCR accuracy**

- Remove `--fast`
- Increase `--dpi` to 400
- Set the correct `--lang`
- Try `--columns 1`, `--columns 2`, or `--columns 3` for known layouts
- Check scan quality and page rotation

**Born-digital PDFs return text too quickly / do not look OCR'd**

That is the default embedded-text shortcut. Use `--force-ocr` when you need OCR output specifically.

**I need deterministic output for a pipeline**

Use `--stdout --no-progress` or redirect stderr separately. Page results are emitted in input/page order even with multiple workers.

## Development

```bash
swift test
swift run avocr --help
swift build -c release
```

The repository also includes a Python benchmark harness in `benchmark/` for comparing `avocr` with other OCR engines.

## Architecture

- `FileEnumerator`: recursive input discovery and filtering
- `WorkItems`: PDF/image work-plan construction
- `AVOCREngine`: Vision OCR wrapper
- `PDFRenderer`: PDF rendering, embedded text extraction, searchable PDF creation
- `ReadingOrder`: text block sorting and column heuristics
- `OutputWriter`: text/JSONL/stdout/file output
- `MultiprocessCoordinator`: worker orchestration, cancellation, ordered output

## Known limitations

- Handwriting recognition depends on Apple's Vision capabilities and works best for clear printed text.
- Column detection is heuristic and may need manual `--columns` for complex layouts.
- Tables are emitted as text blocks, not structured table data.
- Fully rotated pages/text may require preprocessing.
- Available OCR languages are limited to the languages supported by the installed macOS Vision framework.

## License

This is free and unencumbered software released into the public domain. See [LICENSE](LICENSE) for details.

## Credits

Built with Apple's Vision framework, PDFKit, and Swift Argument Parser.
