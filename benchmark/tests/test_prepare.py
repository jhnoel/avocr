from pathlib import Path

from benchmark.prepare import discover_pdfs, sample_pdfs


def test_discover_pdfs_finds_pdf_files_in_sorted_order(tmp_path):
    (tmp_path / "b.pdf").write_text("", encoding="utf-8")
    (tmp_path / "a.PDF").write_text("", encoding="utf-8")
    (tmp_path / "not-pdf.txt").write_text("", encoding="utf-8")

    assert discover_pdfs([tmp_path]) == [tmp_path / "a.PDF", tmp_path / "b.pdf"]


def test_sample_pdfs_is_seeded_and_limited():
    pdfs = [Path(f"{i}.pdf") for i in range(10)]

    assert sample_pdfs(pdfs, n=3, seed=42) == sample_pdfs(pdfs, n=3, seed=42)
    assert len(sample_pdfs(pdfs, n=3, seed=42)) == 3
    assert sample_pdfs(pdfs, n=None, seed=42) == pdfs
