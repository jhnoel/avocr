from __future__ import annotations

import re
import string
import unicodedata
from typing import Literal

import jiwer

Normalization = Literal["light", "aggressive"]


def normalize_text(text: str, mode: Normalization) -> str:
    normalized = unicodedata.normalize("NFC", text)
    normalized = re.sub(r"\s+", " ", normalized).strip()

    if mode == "light":
        return normalized

    if mode == "aggressive":
        normalized = normalized.lower()
        normalized = normalized.translate(str.maketrans("", "", string.punctuation))
        return re.sub(r"\s+", " ", normalized).strip()

    raise ValueError(f"Unknown normalization mode: {mode}")


def _error_rate(metric, reference: str, hypothesis: str) -> float:
    if not reference:
        return 0.0 if not hypothesis else 1.0
    return float(metric(reference, hypothesis))


def score_text(reference: str, hypothesis: str) -> dict[str, dict[str, float]]:
    scores: dict[str, dict[str, float]] = {}
    for mode in ("light", "aggressive"):
        ref = normalize_text(reference, mode)
        hyp = normalize_text(hypothesis, mode)
        scores[mode] = {
            "cer": _error_rate(jiwer.cer, ref, hyp),
            "wer": _error_rate(jiwer.wer, ref, hyp),
        }
    return scores
