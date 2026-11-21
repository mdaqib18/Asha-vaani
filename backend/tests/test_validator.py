from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    ExtractedField,
    FieldSource,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services.validator import validate


def _full_valid_record() -> NewbornVisitRecord:
    return NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042", confidence=0.95, source=FieldSource.selected),
        baby_weight_kg=ExtractedField(value=3.0, confidence=0.9, source=FieldSource.speech),
        temperature_c=ExtractedField(value=36.8, confidence=0.9, source=FieldSource.speech),
        breastfeeding=ExtractedField(value=Breastfeeding.exclusive, confidence=0.9, source=FieldSource.speech),
        cord_status=ExtractedField(value=CordStatus.clean_dry, confidence=0.9, source=FieldSource.speech),
        jaundice=ExtractedField(value=False, confidence=0.9, source=FieldSource.speech),
        limb_abnormality=ExtractedField(
            value=LimbAbnormality(present=False),
            confidence=0.9,
            source=FieldSource.speech,
        ),
    )


def test_out_of_range_weight_flagged_not_altered(newborn_config) -> None:
    record = _full_valid_record()
    record.baby_weight_kg = ExtractedField(value=25.0, confidence=0.9, source=FieldSource.speech)

    result = validate(record, newborn_config, assigned_ids={"1042"})

    assert any(f.field == "baby_weight_kg" and f.reason == "out_of_range" for f in result.flags)
    assert result.record.baby_weight_kg is not None
    assert result.record.baby_weight_kg.value == 25.0
    assert result.record.baby_weight_kg.needs_confirmation is True


def test_out_of_range_temperature_and_breathing_flagged(newborn_config) -> None:
    record = _full_valid_record()
    record.temperature_c = ExtractedField(value=42.0, confidence=0.8, source=FieldSource.typed)
    record.breathing_rate_per_min = ExtractedField(value=120, confidence=0.8, source=FieldSource.speech)

    result = validate(record, newborn_config, assigned_ids={"1042"})

    assert any(f.field == "temperature_c" and f.reason == "out_of_range" for f in result.flags)
    assert result.record.temperature_c.value == 42.0
    assert result.record.temperature_c.needs_confirmation is True
    assert any(f.field == "breathing_rate_per_min" and f.reason == "out_of_range" for f in result.flags)
    assert result.record.breathing_rate_per_min.value == 120
    assert result.record.breathing_rate_per_min.needs_confirmation is True


def test_unknown_beneficiary_flagged(newborn_config) -> None:
    record = _full_valid_record()
    record.beneficiary_id = ExtractedField(value="9999", confidence=0.7, source=FieldSource.speech)

    result = validate(record, newborn_config, assigned_ids={"1042", "1043"})

    assert any(f.field == "beneficiary_id" and f.reason == "unknown_beneficiary" for f in result.flags)
    assert result.record.beneficiary_id.needs_confirmation is True


def test_spec_section_7_example_missing_required(newborn_config) -> None:
    record = NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042", confidence=0.7, source=FieldSource.speech),
        baby_weight_kg=ExtractedField(value=2.5, confidence=0.9, source=FieldSource.speech),
        limb_abnormality=ExtractedField(
            value=LimbAbnormality(present=True, location=LimbLocation.unspecified),
            confidence=0.8,
            source=FieldSource.speech,
        ),
    )

    result = validate(record, newborn_config, assigned_ids={"1042"})

    assert result.missing_required == [
        "temperature_c",
        "breastfeeding",
        "cord_status",
        "jaundice",
    ]
    missing_flag_fields = [f.field for f in result.flags if f.reason == "missing_required"]
    assert missing_flag_fields == result.missing_required
    assert result.record.beneficiary_id.needs_confirmation is True
    assert result.record.baby_weight_kg.needs_confirmation is True


def test_validate_does_not_mutate_input(newborn_config) -> None:
    record = _full_valid_record()
    record.baby_weight_kg = ExtractedField(
        value=25.0,
        confidence=0.9,
        source=FieldSource.speech,
        needs_confirmation=False,
    )

    result = validate(record, newborn_config, assigned_ids={"1042"})

    assert record.baby_weight_kg.needs_confirmation is False
    assert result.record.baby_weight_kg.needs_confirmation is True
