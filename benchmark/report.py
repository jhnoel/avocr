from __future__ import annotations

import json
import math
import statistics
from pathlib import Path

from benchmark.score import score_text


def percentile(values: list[float], pct: int) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, math.ceil((pct / 100) * len(ordered)))
    return ordered[rank - 1]


def _median(values: list[float]) -> float:
    return float(statistics.median(values)) if values else 0.0


def _mean(values: list[float]) -> float:
    return float(statistics.mean(values)) if values else 0.0


def aggregate_engine(engine: str, page_results: list[dict]) -> dict:
    total_seconds = sum(float(page["elapsed_seconds"]) for page in page_results)
    aggregate = {
        "engine": engine,
        "pages": len(page_results),
        "total_ocr_seconds": total_seconds,
        "pages_per_second": (len(page_results) / total_seconds) if total_seconds > 0 else 0.0,
        "macro": {},
        "micro": {},
        "distribution": {},
    }

    for mode in ("light", "aggressive"):
        cers = [float(page["scores"][mode]["cer"]) for page in page_results]
        wers = [float(page["scores"][mode]["wer"]) for page in page_results]
        aggregate["macro"][mode] = {
            "mean_cer": _mean(cers),
            "median_cer": _median(cers),
            "mean_wer": _mean(wers),
            "median_wer": _median(wers),
        }
        aggregate["distribution"][mode] = {
            "cer_p50": percentile(cers, 50),
            "cer_p90": percentile(cers, 90),
            "cer_p99": percentile(cers, 99),
        }

    reference = "\n".join(page["reference_text"] for page in page_results)
    hypothesis = "\n".join(page["hypothesis_text"] for page in page_results)
    aggregate["micro"] = score_text(reference, hypothesis)
    return aggregate


def build_report(run_metadata: dict, page_results: list[dict]) -> dict:
    engines = sorted({page["engine"] for page in page_results})
    return {
        "metadata": run_metadata,
        "engines": [aggregate_engine(engine, [p for p in page_results if p["engine"] == engine]) for engine in engines],
        "pages": page_results,
    }


def write_json_report(report: dict, path: Path) -> None:
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")


def write_markdown_report(report: dict, path: Path) -> None:
    lines = [
        "# OCR Benchmark Report",
        "",
        "Embedded PDF text is used as reference text. It can contain extraction artifacts, so these numbers should be treated as comparative benchmark data rather than perfect OCR truth.",
        "",
        "## Run",
        "",
    ]
    for key, value in report["metadata"].items():
        lines.append(f"- **{key}**: `{value}`")

    lines.extend(
        [
            "",
            "## Aggregate",
            "",
            "| Engine | Pages | OCR seconds | Pages/sec | Light CER mean | Light WER mean | Aggressive CER mean | Aggressive WER mean | Light CER P90 |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for engine in report["engines"]:
        lines.append(
            "| {engine} | {pages} | {seconds:.3f} | {pps:.3f} | {lcer:.4f} | {lwer:.4f} | {acer:.4f} | {awer:.4f} | {p90:.4f} |".format(
                engine=engine["engine"],
                pages=engine["pages"],
                seconds=engine["total_ocr_seconds"],
                pps=engine["pages_per_second"],
                lcer=engine["macro"]["light"]["mean_cer"],
                lwer=engine["macro"]["light"]["mean_wer"],
                acer=engine["macro"]["aggressive"]["mean_cer"],
                awer=engine["macro"]["aggressive"]["mean_wer"],
                p90=engine["distribution"]["light"]["cer_p90"],
            )
        )

    lines.extend(["", "## Micro Average", ""])
    lines.append("| Engine | Light CER | Light WER | Aggressive CER | Aggressive WER |")
    lines.append("| --- | ---: | ---: | ---: | ---: |")
    for engine in report["engines"]:
        lines.append(
            "| {engine} | {lcer:.4f} | {lwer:.4f} | {acer:.4f} | {awer:.4f} |".format(
                engine=engine["engine"],
                lcer=engine["micro"]["light"]["cer"],
                lwer=engine["micro"]["light"]["wer"],
                acer=engine["micro"]["aggressive"]["cer"],
                awer=engine["micro"]["aggressive"]["wer"],
            )
        )

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
