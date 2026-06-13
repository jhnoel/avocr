from benchmark.score import normalize_text, score_text


def test_light_normalization_collapses_whitespace_and_preserves_case_and_punctuation():
    assert normalize_text("Hello,\n\n  WORLD!\t", "light") == "Hello, WORLD!"


def test_aggressive_normalization_lowercases_and_strips_punctuation():
    assert normalize_text("Hello, WORLD!\nCase #123", "aggressive") == "hello world case 123"


def test_score_text_reports_cer_and_wer_for_both_normalizations():
    result = score_text("Hello world", "Hello brave world")

    assert set(result) == {"light", "aggressive"}
    assert result["light"]["wer"] > 0
    assert result["light"]["cer"] > 0
    assert result["aggressive"]["wer"] > 0
    assert result["aggressive"]["cer"] > 0
