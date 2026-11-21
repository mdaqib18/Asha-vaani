from app.schemas.newborn_visit import (
    Breastfeeding,
    CordStatus,
    DangerSign,
    ExtractedField,
    LimbAbnormality,
    LimbLocation,
    NewbornVisitRecord,
)
from app.services.risk_rules import apply_risk, evaluate


def _healthy_record() -> NewbornVisitRecord:
    return NewbornVisitRecord(
        beneficiary_id=ExtractedField(value="1042"),
        baby_weight_kg=ExtractedField(value=3.0),
        temperature_c=ExtractedField(value=36.8),
        breastfeeding=ExtractedField(value=Breastfeeding.exclusive),
        cord_status=ExtractedField(value=CordStatus.clean_dry),
        jaundice=ExtractedField(value=False),
        breathing_rate_per_min=ExtractedField(value=45),
        limb_abnormality=ExtractedField(value=LimbAbnormality(present=False)),
    )


def test_healthy_record_no_flags(newborn_config) -> None:
    flags, referral = evaluate(_healthy_record(), newborn_config)
    assert flags == []
    assert referral is False


def test_low_birth_weight_boundary(newborn_config) -> None:
    low = _healthy_record()
    low.baby_weight_kg = ExtractedField(value=2.4)
    flags, referral = evaluate(low, newborn_config)
    assert flags == ["low_birth_weight"]
    assert referral is True

    borderline = _healthy_record()
    borderline.baby_weight_kg = ExtractedField(value=2.5)
    flags_ok, referral_ok = evaluate(borderline, newborn_config)
    assert flags_ok == []
    assert referral_ok is False


def test_temperature_flags(newborn_config) -> None:
    fever = _healthy_record()
    fever.temperature_c = ExtractedField(value=37.5)
    assert evaluate(fever, newborn_config) == (["fever"], True)

    hypo = _healthy_record()
    hypo.temperature_c = ExtractedField(value=35.4)
    assert evaluate(hypo, newborn_config) == (["hypothermia"], True)

    normal = _healthy_record()
    normal.temperature_c = ExtractedField(value=36.8)
    assert evaluate(normal, newborn_config) == ([], False)


def test_breathing_rate_boundary(newborn_config) -> None:
    fast = _healthy_record()
    fast.breathing_rate_per_min = ExtractedField(value=61)
    assert evaluate(fast, newborn_config) == (["fast_breathing"], True)

    borderline = _healthy_record()
    borderline.breathing_rate_per_min = ExtractedField(value=60)
    assert evaluate(borderline, newborn_config) == ([], False)


def test_cord_feeding_jaundice_limb_and_danger_signs(newborn_config) -> None:
    cord_pus = _healthy_record()
    cord_pus.cord_status = ExtractedField(value=CordStatus.pus_discharge)
    assert evaluate(cord_pus, newborn_config) == (["cord_infection"], True)

    cord_red = _healthy_record()
    cord_red.cord_status = ExtractedField(value=CordStatus.red_swollen)
    assert evaluate(cord_red, newborn_config) == (["cord_infection"], True)

    not_feeding = _healthy_record()
    not_feeding.breastfeeding = ExtractedField(value=Breastfeeding.not_feeding)
    assert evaluate(not_feeding, newborn_config) == (["not_feeding"], True)

    jaundice = _healthy_record()
    jaundice.jaundice = ExtractedField(value=True)
    assert evaluate(jaundice, newborn_config) == (["jaundice"], True)

    limb = _healthy_record()
    limb.limb_abnormality = ExtractedField(
        value=LimbAbnormality(present=True, location=LimbLocation.left_leg)
    )
    assert evaluate(limb, newborn_config) == (["limb_abnormality"], True)

    danger = _healthy_record()
    danger.danger_signs = ExtractedField(value=[DangerSign.convulsions])
    assert evaluate(danger, newborn_config) == (["danger_sign:convulsions"], True)


def test_implausible_numeric_values_ignored_by_risk_rules(newborn_config) -> None:
    record = _healthy_record()
    record.baby_weight_kg = ExtractedField(value=25.0)
    record.temperature_c = ExtractedField(value=10.0)
    record.breathing_rate_per_min = ExtractedField(value=150)

    flags, referral = evaluate(record, newborn_config)
    assert flags == []
    assert referral is False


def test_thresholds_read_from_config(newborn_config) -> None:
    custom_config = newborn_config.model_copy(deep=True)
    custom_config.risk_thresholds.low_birth_weight_kg_below = 2.2

    record = _healthy_record()
    record.baby_weight_kg = ExtractedField(value=2.4)
    assert evaluate(record, custom_config) == ([], False)

    record.baby_weight_kg = ExtractedField(value=2.1)
    assert evaluate(record, custom_config) == (["low_birth_weight"], True)


def test_apply_risk_returns_copy_without_mutating_input(newborn_config) -> None:
    record = _healthy_record()
    record.baby_weight_kg = ExtractedField(value=2.1)

    updated = apply_risk(record, newborn_config)
    assert record.risk_flags == []
    assert record.referral_suggested is False
    assert updated.risk_flags == ["low_birth_weight"]
    assert updated.referral_suggested is True
