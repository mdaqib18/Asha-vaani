import httpx

from app.services.gnani_common import parse_gnani_error


def test_parse_stt_envelope_error() -> None:
    resp = httpx.Response(
        400,
        json={"success": False, "error": {"type": "EMPTY_AUDIO", "message": "Empty audio file received"}},
    )
    assert parse_gnani_error(resp) == ("EMPTY_AUDIO", "Empty audio file received")


def test_parse_gateway_timeout_504() -> None:
    resp = httpx.Response(
        504,
        json={
            "error": "Gateway Timeout",
            "code": "UPSTREAM_TIMEOUT",
            "message": "The speech-to-text model failed to respond.",
        },
    )
    assert parse_gnani_error(resp) == ("UPSTREAM_TIMEOUT", "The speech-to-text model failed to respond.")


def test_parse_auth_or_rate_limit_detail_dict() -> None:
    resp = httpx.Response(
        429,
        json={
            "detail": {
                "error_code": "RATE_LIMITED",
                "message": "Only 1 active request is allowed at a time.",
                "status_code": 429,
            }
        },
    )
    assert parse_gnani_error(resp) == ("RATE_LIMITED", "Only 1 active request is allowed at a time.")


def test_parse_422_validation_detail_list() -> None:
    resp = httpx.Response(
        422,
        json={"detail": [{"type": "missing", "loc": ["body", "audio_file"], "msg": "Field required"}]},
    )
    code, msg = parse_gnani_error(resp)
    assert code == "VALIDATION_ERROR"
    assert "audio_file" in msg


def test_parse_flat_tts_error() -> None:
    resp = httpx.Response(
        400,
        json={"success": False, "message": "Invalid voice", "status_code": 400},
    )
    assert parse_gnani_error(resp) == ("HTTP_400", "Invalid voice")


def test_parse_non_json_body() -> None:
    resp = httpx.Response(502, text="Bad Gateway from proxy")
    assert parse_gnani_error(resp) == ("HTTP_502", "Bad Gateway from proxy")
