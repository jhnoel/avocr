FROM alpine:3.20

RUN apk add --no-cache python3 tesseract-ocr tesseract-ocr-data-eng

COPY worker.py /usr/local/bin/ocr_worker.py
RUN chmod +x /usr/local/bin/ocr_worker.py
