from __future__ import annotations

from pathlib import Path

from benchmark.engines.base import DockerEngineAdapter


class TesseractAdapter(DockerEngineAdapter):
    name = "tesseract"
    image = "tesseract-bench"

    def __init__(self, work_dir: Path, parallel: int = 1):
        super().__init__(work_dir=work_dir, parallel=parallel)
