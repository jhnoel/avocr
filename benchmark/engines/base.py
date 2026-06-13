from __future__ import annotations

import abc
import json
import queue
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


class EngineAdapter(abc.ABC):
    name: str

    def warm(self, pages: list[dict]) -> None:
        return None

    @abc.abstractmethod
    def ocr_page(self, page: dict, output_path: Path) -> dict:
        raise NotImplementedError

    def run_pages(self, pages: list[dict], output_dir: Path, parallel: int) -> list[dict]:
        output_dir.mkdir(parents=True, exist_ok=True)
        workers = max(1, parallel)
        if workers == 1:
            return [self.ocr_page(page, self.output_path(output_dir, page)) for page in pages]

        results: list[dict] = []
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = {executor.submit(self.ocr_page, page, self.output_path(output_dir, page)): page for page in pages}
            for future in as_completed(futures):
                results.append(future.result())
        return sorted(results, key=lambda item: (item["doc_id"], item["page_number"]))

    def output_path(self, output_dir: Path, page: dict) -> Path:
        doc_dir = output_dir / page["doc_id"]
        doc_dir.mkdir(parents=True, exist_ok=True)
        return doc_dir / f"page-{page['page_number']:03d}.txt"


class DockerWorker:
    def __init__(self, image: str, work_dir: Path):
        self.image = image
        self.work_dir = work_dir.resolve()
        self._lock = threading.Lock()
        self._process: subprocess.Popen[str] | None = None
        self._stderr: queue.Queue[str] = queue.Queue()
        self.platform: str | None = None

    def start(self) -> None:
        if self._process is not None:
            return
        command = [
            "docker",
            "run",
            "--rm",
            "-i",
            "--shm-size=8g",
            "-v",
            f"{self.work_dir}:/work",
        ]
        if self.platform:
            command.extend(["--platform", self.platform])
        command.extend([self.image, "/usr/local/bin/ocr_worker.py"])
        self._process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if self._process.stderr is not None:
            threading.Thread(target=self._drain_stderr, args=(self._process.stderr,), daemon=True).start()

    def stop(self) -> None:
        if self._process is None:
            return
        if self._process.stdin:
            self._process.stdin.close()
        try:
            self._process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait()
        self._process = None

    def request(self, image_path: Path, output_path: Path) -> dict:
        self.start()
        assert self._process is not None
        assert self._process.stdin is not None
        assert self._process.stdout is not None

        payload = {
            "image": self._container_path(image_path),
            "output": self._container_path(output_path),
        }
        with self._lock:
            self._process.stdin.write(json.dumps(payload) + "\n")
            self._process.stdin.flush()
            line = self._read_json_line()

        if not line:
            exit_code = self._process.poll()
            stderr = self._recent_stderr()
            message = f"Docker OCR worker exited unexpectedly for image {self.image}"
            if exit_code is not None:
                message += f" with exit code {exit_code}"
            if stderr:
                message += f":\n{stderr}"
            raise RuntimeError(message)

        response = json.loads(line)
        if not response.get("ok"):
            raise RuntimeError(response.get("error", f"Docker OCR worker failed for {self.image}"))
        return response

    def _read_json_line(self) -> str:
        assert self._process is not None
        assert self._process.stdout is not None

        noise: list[str] = []
        while True:
            line = self._process.stdout.readline()
            if not line:
                if noise:
                    self._stderr.put("Ignored non-protocol stdout before worker exit:")
                    for item in noise[-20:]:
                        self._stderr.put(item)
                return ""
            try:
                json.loads(line)
                return line
            except json.JSONDecodeError:
                noise.append(line.rstrip())
                if len(noise) > 200:
                    raise RuntimeError(
                        f"Docker OCR worker for image {self.image} emitted too much non-JSON stdout. "
                        f"Recent output:\n" + "\n".join(noise[-20:])
                    )

    def _container_path(self, path: Path) -> str:
        resolved = path.resolve()
        return "/work/" + str(resolved.relative_to(self.work_dir))

    def _drain_stderr(self, stderr) -> None:
        for line in stderr:
            self._stderr.put(line.rstrip())

    def _recent_stderr(self) -> str:
        lines: list[str] = []
        while True:
            try:
                lines.append(self._stderr.get_nowait())
            except queue.Empty:
                break
        return "\n".join(lines[-40:])


class DockerEngineAdapter(EngineAdapter):
    image: str
    platform: str | None = None

    def __init__(self, work_dir: Path, parallel: int = 1):
        self.work_dir = work_dir.resolve()
        self.parallel = max(1, parallel)
        self._check_image()
        self._workers = [DockerWorker(self.image, self.work_dir) for _ in range(self.parallel)]
        for worker in self._workers:
            worker.platform = self.platform
        self._next_worker = 0
        self._worker_lock = threading.Lock()

    def _check_image(self) -> None:
        completed = subprocess.run(
            ["docker", "image", "inspect", self.image],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()
            raise RuntimeError(
                f"Docker image `{self.image}` is not available. "
                "Run `uv run run.py --build-docker --engines tesseract,paddleocr --n 1` first."
                + (f"\nDocker said: {detail}" if detail else "")
            )

    def warm(self, pages: list[dict]) -> None:
        if not pages:
            return
        warmup_output = self.work_dir / "_warmup" / f"{self.name}.txt"
        warmup_output.parent.mkdir(parents=True, exist_ok=True)
        for worker in self._workers:
            worker.request(Path(pages[0]["image_path"]), warmup_output)

    def ocr_page(self, page: dict, output_path: Path) -> dict:
        worker = self._checkout_worker()
        response = worker.request(Path(page["image_path"]), output_path)
        return {
            "engine": self.name,
            "doc_id": page["doc_id"],
            "page_number": page["page_number"],
            "page_index": page["page_index"],
            "image_path": page["image_path"],
            "output_path": str(output_path),
            "elapsed_seconds": response["elapsed_seconds"],
        }

    def close(self) -> None:
        for worker in self._workers:
            worker.stop()

    def _checkout_worker(self) -> DockerWorker:
        with self._worker_lock:
            worker = self._workers[self._next_worker]
            self._next_worker = (self._next_worker + 1) % len(self._workers)
            return worker


def timed_subprocess(command: list[str], output_path: Path) -> float:
    start = time.perf_counter()
    completed = subprocess.run(command, check=True, capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    output_path.write_text(completed.stdout, encoding="utf-8")
    return elapsed


def run_timed(command: list[str]) -> float:
    start = time.perf_counter()
    subprocess.run(command, check=True, capture_output=True, text=True)
    return time.perf_counter() - start
