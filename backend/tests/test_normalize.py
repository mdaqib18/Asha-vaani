import pytest

from app.services.normalize import (
    parse_digit_sequence,
    parse_number,
    parse_temperature_c,
    parse_weight_kg,
)


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("dhai kilo", 2.5),
        ("dhaai", 2.5),
        ("dedh kg", 1.5),
        ("saadhe teen", 3.5),
        ("sava do", 2.25),
        ("paune teen", 2.75),
        ("two point five", 2.5),
        ("thirty seven point five", 37.5),
        ("2.5 kg hai", 2.5),
        ("eradu vare kg", 2.5),
        ("ippattu", 20.0),
        ("ondu", 1.0),
        ("पैंतीस दशमलव दो", 35.2),
        ("अट्ठानवे दशमलव छह", 98.6),
        ("ಎರಡು ಸಾವಿರದ ಮುನ್ನೂರು", 2300.0),
        ("ಮೂವತ್ತೈದು", 35.0),
        ("ढाई किलो", 2.5),
        ("೨.೫", 2.5),
        ("paanch sau", 500.0),
        ("aadha", 0.5),
        ("haan", None),
        ("", None),
    ],
)
def test_parse_number(text: str, expected: float | None) -> None:
    assert parse_number(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("ek zero chaar do", "1042"),
        ("one zero four two", "1042"),
        ("10 42", "1042"),
        ("beneficiary 1042", "1042"),
        ("ondu sonne naalku eradu", "1042"),
        ("१०४२", "1042"),
        ("haan", None),
        ("", None),
    ],
)
def test_parse_digit_sequence(text: str, expected: str | None) -> None:
    assert parse_digit_sequence(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("dhai kilo", 2.5),
        ("dhaai", 2.5),
        ("dedh kg", 1.5),
        ("2.5 kg hai", 2.5),
        ("2.5kg", 2.5),
        ("2500 gram", 2.5),
        ("do kilo paanch sau gram", 2.5),
        ("sau gram", 0.1),
        ("eradu vare kg", 2.5),
        ("ढाई किलो", 2.5),
        ("೨.೫ ಕೆಜಿ", 2.5),
        ("25", 25.0),
        ("haan", None),
        ("", None),
    ],
)
def test_parse_weight_kg(text: str, expected: float | None) -> None:
    assert parse_weight_kg(text) == expected


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("98.6 F", (37.0, True)),
        ("अट्ठानवे दशमलव छह फारेनहाइट", (37.0, True)),
        ("100.4 ಫ್ಯಾರನ್ಹೀಟ್", (38.0, True)),
        ("100 fahrenheit", (37.8, True)),
        ("100.4°F", (38.0, True)),
        ("37.5 degree", (37.5, False)),
        ("36.8 c", (36.8, False)),
        ("36.8", (36.8, False)),
        ("haan", None),
        ("", None),
    ],
)
def test_parse_temperature_c(text: str, expected: tuple[float, bool] | None) -> None:
    assert parse_temperature_c(text) == expected
