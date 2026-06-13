import pytest

from benchmark.report import aggregate_engine, percentile


def test_percentile_uses_nearest_rank():
    assert percentile([0.1, 0.2, 0.9, 1.0], 50) == 0.2
    assert percentile([0.1, 0.2, 0.9, 1.0], 90) == 1.0


def test_aggregate_engine_computes_macro_micro_and_throughput():
    pages = [
        {
            "engine": "avocr",
            "elapsed_seconds": 2.0,
            "scores": {
                "light": {"cer": 0.1, "wer": 0.2},
                "aggressive": {"cer": 0.05, "wer": 0.1},
            },
            "reference_text": "hello world",
            "hypothesis_text": "hello world",
        },
        {
            "engine": "avocr",
            "elapsed_seconds": 1.0,
            "scores": {
                "light": {"cer": 0.3, "wer": 0.4},
                "aggressive": {"cer": 0.15, "wer": 0.2},
            },
            "reference_text": "goodbye world",
            "hypothesis_text": "goodbye word",
        },
    ]

    aggregate = aggregate_engine("avocr", pages)

    assert aggregate["engine"] == "avocr"
    assert aggregate["pages"] == 2
    assert aggregate["total_ocr_seconds"] == 3.0
    assert aggregate["pages_per_second"] == pytest.approx(2 / 3)
    assert aggregate["macro"]["light"]["mean_cer"] == pytest.approx(0.2)
    assert aggregate["macro"]["light"]["median_wer"] == pytest.approx(0.3)
    assert aggregate["distribution"]["light"]["cer_p50"] == 0.1
    assert "micro" in aggregate
