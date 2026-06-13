from __future__ import annotations

from pathlib import Path

from benchmark.engines.base import DockerEngineAdapter


class PaddleOCRAdapter(DockerEngineAdapter):
    name = "paddleocr"
    image = "paddleocr-bench"
    platform = "linux/amd64"

    def __init__(self, work_dir: Path, parallel: int = 1):
        super().__init__(work_dir=work_dir, parallel=parallel)
