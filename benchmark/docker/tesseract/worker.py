#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path


for line in sys.stdin:
    try:
        request = json.loads(line)
        image = request["image"]
        output = Path(request["output"])
        output.parent.mkdir(parents=True, exist_ok=True)

        start = time.perf_counter()
        completed = subprocess.run(["tesseract", image, "stdout"], check=True, capture_output=True, text=True)
        elapsed = time.perf_counter() - start

        output.write_text(completed.stdout, encoding="utf-8")
        print(json.dumps({"ok": True, "elapsed_seconds": elapsed}), flush=True)
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}), flush=True)
