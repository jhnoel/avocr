FROM --platform=linux/amd64 python:3.10-slim

ENV PIP_NO_CACHE_DIR=1 \
    PADDLEOCR_HOME=/opt/paddleocr \
    OMP_NUM_THREADS=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 libglib2.0-0 libgl1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install "paddlepaddle==3.2.0" -i https://www.paddlepaddle.org.cn/packages/stable/cpu/ \
    && pip install "paddleocr==3.3.0" opencv-python-headless

RUN python - <<'PY'
from paddleocr import PaddleOCR
PaddleOCR(
    lang="en",
    text_detection_model_name="PP-OCRv5_mobile_det",
    text_recognition_model_name="en_PP-OCRv5_mobile_rec",
    use_doc_orientation_classify=False,
    use_doc_unwarping=False,
    use_textline_orientation=False,
)
PY

COPY worker.py /usr/local/bin/ocr_worker.py
RUN chmod +x /usr/local/bin/ocr_worker.py
