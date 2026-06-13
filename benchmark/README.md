# OCR benchmark

This directory contains a Python benchmark harness for comparing `avocr`, Tesseract, and PaddleOCR on the same rasterized PDF pages.

The harness is intentionally outside the Swift package. It renders sampled PDFs to PNGs, extracts embedded PDF text as reference text, runs each OCR engine over the PNGs, scores output with CER/WER, and writes both JSON and Markdown reports.

Embedded PDF text is reference text, not perfect human-labeled truth. It can include extraction artifacts, unusual reading order, hidden text, ligatures, or header/footer noise.

## Setup

Install Python dependencies from this directory:

```bash
cd benchmark
uv sync --extra test
```

Run the benchmark harness tests:

```bash
uv run --extra test pytest
```

Build `avocr` first:

```bash
swift build -c release
```

Build the Tesseract Docker image:

```bash
uv run run.py --engines tesseract --build-docker --n 1
```

PaddleOCR support remains in the tree, but it is not part of the default run. Native `linux/arm64` PaddlePaddle inference segfaulted under Docker on Apple Silicon during validation, and the `linux/amd64` fallback was too slow to be useful for this benchmark.

## Run

Default run, sampling 10 PDFs from `test_inputs/`:

```bash
uv run run.py
```

Common options:

```bash
uv run run.py \
  --n 10 \
  --seed 42 \
  --engines avocr,tesseract \
  --dpi 300 \
  --parallel 1
```

Full corpus:

```bash
uv run run.py --all
```

Custom input:

```bash
uv run run.py --input /path/to/pdfs --n 25
```

Reports are written under `benchmark/work/<run-id>/` unless `--out` is provided:

- `manifest.json`: prepared page list and metadata
- `results/<engine>/...`: per-page OCR text
- `<engine>-pages.json`: per-page timing and score records
- `report.json`: machine-readable aggregate report
- `report.md`: Markdown summary table

## Timing model

The harness warms each engine before timing. For Docker engines, it starts persistent containers with `/work` bind-mounted to the run directory and sends page paths to a worker process over stdin. PaddleOCR loads its model once per worker. Tesseract runs one OCR subprocess per page inside the already-running container.

Measured time is the OCR call reported by the engine worker. Docker image build, container startup, model preload, page preparation, scoring, and report generation are outside the per-page OCR timing.

`--parallel N` creates up to `N` concurrent page workers per engine. For PaddleOCR, that means `N` model-loaded containers, so memory use can grow quickly.

## Metrics

For each page and engine:

- `light`: NFC normalization plus whitespace collapse
- `aggressive`: light normalization plus lowercasing and ASCII punctuation stripping
- CER and WER via `jiwer`
- OCR elapsed seconds
- page dimensions, megapixels, and reference character count

For each engine:

- macro mean and median CER/WER
- micro CER/WER over concatenated page text
- total OCR seconds
- pages per second
- P50/P90/P99 page CER distribution
