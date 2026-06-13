from __future__ import annotations

import json
import random
import re
from pathlib import Path
from typing import Iterable


def discover_pdfs(inputs: Iterable[Path]) -> list[Path]:
    pdfs: list[Path] = []
    for input_path in inputs:
        path = input_path.expanduser()
        if path.is_file() and path.suffix.lower() == ".pdf":
            pdfs.append(path)
        elif path.is_dir():
            pdfs.extend(p for p in path.rglob("*") if p.is_file() and p.suffix.lower() == ".pdf")
    return sorted(pdfs)


def sample_pdfs(pdfs: list[Path], n: int | None, seed: int) -> list[Path]:
    if n is None or n >= len(pdfs):
        return pdfs
    rng = random.Random(seed)
    return sorted(rng.sample(pdfs, n))


def _safe_doc_id(pdf: Path, index: int) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", pdf.stem).strip("._-")
    return f"{index:04d}-{stem or 'document'}"


def prepare_corpus(
    pdfs: list[Path],
    out_dir: Path,
    dpi: int,
    skip_first_page: bool = False,
    min_reference_chars: int = 0,
) -> list[dict]:
    try:
        import fitz
    except ImportError as exc:
        raise RuntimeError("PyMuPDF is required. Install benchmark dependencies with `uv sync` or `pip install -e benchmark`.") from exc

    pages_dir = out_dir / "pages"
    truth_dir = out_dir / "ground_truth"
    pages_dir.mkdir(parents=True, exist_ok=True)
    truth_dir.mkdir(parents=True, exist_ok=True)

    manifest: list[dict] = []
    zoom = dpi / 72
    matrix = fitz.Matrix(zoom, zoom)

    for doc_index, pdf in enumerate(pdfs):
        doc_id = _safe_doc_id(pdf, doc_index)
        doc_pages_dir = pages_dir / doc_id
        doc_truth_dir = truth_dir / doc_id
        doc_pages_dir.mkdir(parents=True, exist_ok=True)
        doc_truth_dir.mkdir(parents=True, exist_ok=True)

        with fitz.open(pdf) as document:
            for page_index in range(document.page_count):
                if skip_first_page and page_index == 0:
                    continue
                page = document.load_page(page_index)
                reference_text = page.get_text("text")
                if not reference_text.strip():
                    continue
                if min_reference_chars and len(reference_text) < min_reference_chars:
                    continue

                page_name = f"page-{page_index + 1:03d}"
                image_path = doc_pages_dir / f"{page_name}.png"
                truth_path = doc_truth_dir / f"{page_name}.txt"

                pixmap = page.get_pixmap(matrix=matrix, alpha=False)
                pixmap.save(image_path)
                truth_path.write_text(reference_text, encoding="utf-8")

                manifest.append(
                    {
                        "doc_id": doc_id,
                        "source_pdf": str(pdf),
                        "page_index": page_index,
                        "page_number": page_index + 1,
                        "image_path": str(image_path),
                        "ground_truth_path": str(truth_path),
                        "width": pixmap.width,
                        "height": pixmap.height,
                        "megapixels": round((pixmap.width * pixmap.height) / 1_000_000, 4),
                        "reference_chars": len(reference_text),
                    }
                )

    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest
