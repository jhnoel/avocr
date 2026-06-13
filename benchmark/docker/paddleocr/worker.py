#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

protocol_stdout = sys.stdout

from paddleocr import PaddleOCR


def make_ocr():
    try:
        return PaddleOCR(
            lang="en",
            text_detection_model_name="PP-OCRv5_mobile_det",
            text_recognition_model_name="en_PP-OCRv5_mobile_rec",
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
        )
    except TypeError:
        return PaddleOCR(use_angle_cls=True, lang="en", show_log=False, use_gpu=False)


ocr = make_ocr()


def extract_text(result) -> str:
    lines: list[str] = []
    if not result:
        return ""

    for page in result:
        data = getattr(page, "json", None)
        if isinstance(data, dict):
            page = data.get("res", data)
        elif hasattr(page, "to_dict"):
            page = page.to_dict()

        if isinstance(page, dict):
            texts = page.get("rec_texts") or page.get("texts") or page.get("text")
            if isinstance(texts, list):
                lines.extend(str(text) for text in texts)
            elif isinstance(texts, str):
                lines.append(texts)
            continue

        if not page:
            continue
        for item in page:
            if isinstance(item, dict):
                text = item.get("text") or item.get("transcription")
                if text:
                    lines.append(str(text))
                continue
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                payload = item[1]
                if isinstance(payload, (list, tuple)) and payload:
                    lines.append(str(payload[0]))
                elif isinstance(payload, str):
                    lines.append(payload)
    return "\n".join(lines)


for line in sys.stdin:
    try:
        request = json.loads(line)
        image = request["image"]
        output = Path(request["output"])
        output.parent.mkdir(parents=True, exist_ok=True)

        start = time.perf_counter()
        if hasattr(ocr, "predict"):
            result = ocr.predict(image)
        else:
            result = ocr.ocr(image, cls=True)
        elapsed = time.perf_counter() - start

        output.write_text(extract_text(result), encoding="utf-8")
        print(json.dumps({"ok": True, "elapsed_seconds": elapsed}), file=protocol_stdout, flush=True)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), file=protocol_stdout, flush=True)
