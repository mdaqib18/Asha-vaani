"""Deterministic validation for extracted NewbornVisitRecord instances."""

from __future__ import annotations

from pydantic import BaseModel, Field

from app.core.config_loader import VisitTypeConfig
from app.schemas.newborn_visit import FieldSource, Flag, NewbornVisitRecord


class ValidationResult(BaseModel):
    """Result of validating a NewbornVisitRecord against visit-type rules."""

    record: NewbornVisitRecord
    flags: list[Flag] = Field(default_factory=list)
    missing_required: list[str] = Field(default_factory=list)


def validate(
    record: NewbornVisitRecord,
    config: VisitTypeConfig,
    assigned_ids: set[str] | None = None,
) -> ValidationResult:
    """Validate ranges, assigned beneficiary IDs, confirmation flags, and required fields."""
    validated = record.model_copy(deep=True)
    flags: list[Flag] = []
    missing_required: list[str] = []

    # 1. Plausible range checks (never silently alter out-of-range values).
    for field_name, bounds in config.ranges.items():
        field_obj = getattr(validated, field_name, None)
        if field_obj is not None and field_obj.value is not None:
            if field_obj.value < bounds.min or field_obj.value > bounds.max:
                flags.append(Flag(field=field_name, reason="out_of_range"))
                field_obj.needs_confirmation = True

    # 2. Assigned beneficiary ID check.
    if assigned_ids is not None:
        ben_field = validated.beneficiary_id
        if ben_field is not None and ben_field.value is not None:
            if ben_field.value not in assigned_ids:
                flags.append(Flag(field="beneficiary_id", reason="unknown_beneficiary"))
                ben_field.needs_confirmation = True

    # 3. Always require read-back confirmation on key spoken fields.
    for field_name in config.confirm_always:
        field_obj = getattr(validated, field_name, None)
        if (
            field_obj is not None
            and field_obj.value is not None
            and field_obj.source == FieldSource.speech
        ):
            field_obj.needs_confirmation = True

    # 4. Required-field completeness check in config order.
    for field_name in config.required_fields:
        field_obj = getattr(validated, field_name, None)
        if field_obj is None or field_obj.value is None:
            missing_required.append(field_name)
            flags.append(Flag(field=field_name, reason="missing_required"))

    return ValidationResult(
        record=validated,
        flags=flags,
        missing_required=missing_required,
    )
