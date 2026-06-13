#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

if __package__ is None:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import click
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

from benchmark.engines import AVOCRAdapter, PaddleOCRAdapter, TesseractAdapter
from benchmark.prepare import discover_pdfs, prepare_corpus, sample_pdfs
from benchmark.report import build_report, write_json_report, write_markdown_report
from benchmark.score import score_text

console = Console()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def default_run_dir() -> Path:
    run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
    return repo_root() / "benchmark" / "work" / run_id


def build_docker_image(name: str, docker_dir: Path, platform: str | None = None) -> None:
    command = ["docker", "build", "-t", name]
    if platform:
        command.extend(["--platform", platform])
    command.append(str(docker_dir))
    subprocess.run(command, check=True)


def instantiate_engine(name: str, work_dir: Path, parallel: int):
    if name == "avocr":
        return AVOCRAdapter(repo_root())
    if name == "tesseract":
        return TesseractAdapter(work_dir=work_dir, parallel=parallel)
    if name == "paddleocr":
        return PaddleOCRAdapter(work_dir=work_dir, parallel=parallel)
    raise click.ClickException(f"Unknown engine: {name}")


def score_engine_results(engine_results: list[dict]) -> list[dict]:
    scored: list[dict] = []
    for result in engine_results:
        reference_path = Path(result["ground_truth_path"])
        output_path = Path(result["output_path"])
        reference = reference_path.read_text(encoding="utf-8")
        hypothesis = output_path.read_text(encoding="utf-8") if output_path.exists() else ""
        scored.append(
            {
                **result,
                "reference_text": reference,
                "hypothesis_text": hypothesis,
                "scores": score_text(reference, hypothesis),
            }
        )
    return scored


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.option("--input", "inputs", multiple=True, type=click.Path(path_type=Path), default=[Path("test_inputs")], help="PDF file or directory. Can be repeated.")
@click.option("--n", type=click.IntRange(min=1), default=10, show_default=True, help="Number of PDFs to sample.")
@click.option("--all", "use_all", is_flag=True, help="Use every discovered PDF.")
@click.option("--seed", type=int, default=42, show_default=True, help="Random seed for PDF sampling.")
@click.option("--engines", default="avocr,tesseract", show_default=True, help="Comma-separated engine list.")
@click.option("--dpi", type=int, default=300, show_default=True, help="Rasterization DPI.")
@click.option("--parallel", type=click.IntRange(min=1), default=1, show_default=True, help="Pages to OCR concurrently per engine.")
@click.option("--out", "out_dir", type=click.Path(path_type=Path), default=None, help="Run output directory.")
@click.option("--build-docker", is_flag=True, help="Build selected Docker engine images before running.")
@click.option("--skip-first-page", is_flag=True, help="Skip the first page of every document (typically a cover page).")
@click.option("--min-chars", type=int, default=0, show_default=True, help="Skip pages whose embedded reference text is shorter than this (filters image-heavy pages).")
def main(inputs: tuple[Path, ...], n: int, use_all: bool, seed: int, engines: str, dpi: int, parallel: int, out_dir: Path | None, build_docker: bool, skip_first_page: bool, min_chars: int) -> None:
    root = repo_root()
    selected_engines = [engine.strip() for engine in engines.split(",") if engine.strip()]
    work_dir = (out_dir or default_run_dir()).resolve()
    work_dir.mkdir(parents=True, exist_ok=True)

    pdf_inputs = [path if path.is_absolute() else root / path for path in inputs]
    pdfs = discover_pdfs(pdf_inputs)
    if not pdfs:
        raise click.ClickException(f"No PDFs found under: {', '.join(str(p) for p in pdf_inputs)}")
    selected_pdfs = sample_pdfs(pdfs, None if use_all else n, seed)

    if build_docker:
        if "tesseract" in selected_engines:
            build_docker_image("tesseract-bench", root / "benchmark" / "docker" / "tesseract")
        if "paddleocr" in selected_engines:
            build_docker_image("paddleocr-bench", root / "benchmark" / "docker" / "paddleocr", platform="linux/amd64")

    with Progress(SpinnerColumn(), TextColumn("[progress.description]{task.description}"), console=console) as progress:
        task = progress.add_task("Preparing pages", total=None)
        manifest = prepare_corpus(selected_pdfs, work_dir, dpi, skip_first_page=skip_first_page, min_reference_chars=min_chars)
        progress.update(task, description=f"Prepared {len(manifest)} pages")

    if not manifest:
        raise click.ClickException("No pages with extractable reference text were found.")

    all_page_results: list[dict] = []
    run_started = time.time()

    for engine_name in selected_engines:
        adapter = instantiate_engine(engine_name, work_dir, parallel)
        try:
            console.print(f"Running {engine_name} over {len(manifest)} pages")
            adapter.warm(manifest)
            output_dir = work_dir / "results" / engine_name
            raw_results = adapter.run_pages(manifest, output_dir, parallel=parallel)
            pages_by_key = {(page["doc_id"], page["page_number"]): page for page in manifest}
            joined = [
                {**result, **pages_by_key[(result["doc_id"], result["page_number"])]}
                for result in raw_results
            ]
            scored = score_engine_results(joined)
            (work_dir / f"{engine_name}-pages.json").write_text(json.dumps(scored, indent=2), encoding="utf-8")
            all_page_results.extend(scored)
        finally:
            close = getattr(adapter, "close", None)
            if close:
                close()

    metadata = {
        "run_dir": str(work_dir),
        "input_count": len(pdfs),
        "sampled_pdfs": len(selected_pdfs),
        "prepared_pages": len(manifest),
        "dpi": dpi,
        "parallel": parallel,
        "engines": ",".join(selected_engines),
        "seed": seed,
        "wall_seconds": round(time.time() - run_started, 3),
    }
    report = build_report(metadata, all_page_results)
    write_json_report(report, work_dir / "report.json")
    write_markdown_report(report, work_dir / "report.md")

    console.print(f"Wrote {work_dir / 'report.md'}")
    console.print(f"Wrote {work_dir / 'report.json'}")


if __name__ == "__main__":
    main()
