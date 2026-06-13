from __future__ import annotations

import os
from pathlib import Path

from benchmark.engines.base import EngineAdapter, run_timed


class AVOCRAdapter(EngineAdapter):
    name = "avocr"

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root.resolve()
        self.binary = self.repo_root / ".build" / "release" / "avocr"
        self._check_binary()

    def _check_binary(self) -> None:
        if not self.binary.exists():
            raise RuntimeError("Missing .build/release/avocr. Run `swift build -c release` before benchmarking avocr.")
        binary_mtime = self.binary.stat().st_mtime
        source_paths = list((self.repo_root / "Sources").rglob("*.swift")) + [self.repo_root / "Package.swift"]
        if any(path.stat().st_mtime > binary_mtime for path in source_paths):
            raise RuntimeError(".build/release/avocr is older than Swift sources. Run `swift build -c release` before benchmarking.")
        if not os.access(self.binary, os.X_OK):
            raise RuntimeError(f"{self.binary} is not executable.")

    def warm(self, pages: list[dict]) -> None:
        if not pages:
            return
        warmup_dir = self.repo_root / "benchmark" / "work" / "_avocr-warmup"
        warmup_dir.mkdir(parents=True, exist_ok=True)
        self.ocr_page(pages[0], warmup_dir / f"{Path(pages[0]['image_path']).stem}.txt")

    def ocr_page(self, page: dict, output_path: Path) -> dict:
        command = [
            str(self.binary),
            "--output",
            str(output_path.parent),
            "--no-headers",
            "--no-progress",
            "--workers",
            "1",
            str(Path(page["image_path"])),
        ]
        output_path.unlink(missing_ok=True)
        elapsed = run_timed(command)
        if not output_path.exists():
            raise RuntimeError(f"avocr did not produce expected output file: {output_path}")
        return {
            "engine": self.name,
            "doc_id": page["doc_id"],
            "page_number": page["page_number"],
            "page_index": page["page_index"],
            "image_path": page["image_path"],
            "output_path": str(output_path),
            "elapsed_seconds": elapsed,
        }
