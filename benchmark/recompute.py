#!/usr/bin/env python3
"""Re-generate a report from an existing run's report.json with optional page filters.

Example:
    uv run python -m benchmark.recompute \\
        --run work/20260509-183851 \\
        --skip-first-page \\
        --min-chars 300
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

if __package__ is None:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import click
from rich.console import Console

from benchmark.report import build_report, write_json_report, write_markdown_report

console = Console()


def _is_cover_page(page: dict) -> bool:
    return "COMMISSIONER FOR PATENTS" in page.get("reference_text", "")


@click.command(context_settings={"help_option_names": ["-h", "--help"]})
@click.option("--run", "run_dir", required=True, type=click.Path(path_type=Path), help="Existing benchmark run directory (contains report.json).")
@click.option("--skip-first-page", is_flag=True, help="Exclude page 1 of every document.")
@click.option("--skip-cover", is_flag=True, help="Exclude pages whose reference text contains 'COMMISSIONER FOR PATENTS' (USPTO cover pages).")
@click.option("--min-chars", type=int, default=0, show_default=True, help="Exclude pages with fewer than this many reference characters.")
@click.option("--out", "out_path", type=click.Path(path_type=Path), default=None, help="Output markdown path (default: <run_dir>/report-filtered.md).")
def main(run_dir: Path, skip_first_page: bool, skip_cover: bool, min_chars: int, out_path: Path | None) -> None:
    report_json = run_dir / "report.json"
    if not report_json.exists():
        raise click.ClickException(f"No report.json found in {run_dir}")

    report = json.loads(report_json.read_text(encoding="utf-8"))
    all_pages = report["pages"]
    original_count = len(all_pages)

    filtered = all_pages
    if skip_first_page:
        filtered = [p for p in filtered if p["page_number"] != 1]
    if skip_cover:
        filtered = [p for p in filtered if not _is_cover_page(p)]
    if min_chars:
        filtered = [p for p in filtered if p["reference_chars"] >= min_chars]

    dropped = original_count - len(filtered)
    engines = sorted({p["engine"] for p in filtered})
    console.print(f"Pages: {original_count} → {len(filtered)} (dropped {dropped}), engines: {', '.join(engines)}")

    metadata = {
        **report["metadata"],
        "filtered_pages": len(filtered),
        "filter_skip_first_page": skip_first_page,
        "filter_skip_cover": skip_cover,
        "filter_min_chars": min_chars,
    }
    new_report = build_report(metadata, filtered)

    md_path = out_path or (run_dir / "report-filtered.md")
    json_path = md_path.with_suffix(".json")
    write_json_report(new_report, json_path)
    write_markdown_report(new_report, md_path)
    console.print(f"Wrote {md_path}")


if __name__ == "__main__":
    main()
