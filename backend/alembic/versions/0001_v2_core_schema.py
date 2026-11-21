"""V2 core schema: 14 domain tables and 5 performance/uniqueness indexes.

Revision ID: 0001_v2_core_schema
Revises:
Create Date: 2026-11-22
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa

revision = "0001_v2_core_schema"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "workers",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("worker_code", sa.String(length=64), nullable=False, unique=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("language_pref", sa.String(length=16), nullable=False, server_default="hi"),
        sa.Column("area_ids", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("pin_hash", sa.String(length=128), nullable=False, server_default=""),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "areas",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False, unique=True),
    )

    op.create_table(
        "households",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("area_id", sa.String(length=64), sa.ForeignKey("areas.id"), nullable=False),
        sa.Column("note", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "visit_types",
        sa.Column("code", sa.String(length=64), primary_key=True),
        sa.Column("schema_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("name_i18n", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )

    op.create_table(
        "beneficiaries",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("local_code", sa.String(length=32), nullable=False),
        sa.Column("external_id", sa.String(length=64), nullable=True),
        sa.Column("worker_id", sa.String(length=64), sa.ForeignKey("workers.id"), nullable=False),
        sa.Column("area_id", sa.String(length=64), sa.ForeignKey("areas.id"), nullable=True),
        sa.Column("household_id", sa.String(length=64), sa.ForeignKey("households.id"), nullable=True),
        sa.Column("full_name", sa.String(length=200), nullable=False),
        sa.Column("sex", sa.String(length=16), nullable=False, server_default="unknown"),
        sa.Column("dob", sa.String(length=32), nullable=True),
        sa.Column("dob_is_estimated", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("beneficiary_type", sa.String(length=32), nullable=False, server_default="newborn"),
        sa.Column("mother_id", sa.String(length=64), sa.ForeignKey("beneficiaries.id"), nullable=True),
        sa.Column("phone_enc", sa.Text(), nullable=True),
        sa.Column("consent_id", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="active"),
        sa.Column("risk_level", sa.String(length=16), nullable=False, server_default="none"),
        sa.Column("last_visit_at", sa.String(length=64), nullable=True),
        sa.Column("next_due_at", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.String(length=64), nullable=False),
        sa.Column("updated_at", sa.String(length=64), nullable=False),
        sa.Column("deleted_at", sa.String(length=64), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index(
        "ix_beneficiaries_worker_status_due",
        "beneficiaries",
        ["worker_id", "status", "next_due_at"],
    )
    op.create_index(
        "uq_beneficiaries_worker_local_code",
        "beneficiaries",
        ["worker_id", "local_code"],
        unique=True,
    )

    op.create_table(
        "pregnancies",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "beneficiary_id",
            sa.String(length=64),
            sa.ForeignKey("beneficiaries.id"),
            nullable=False,
        ),
        sa.Column("lmp_date", sa.String(length=32), nullable=True),
        sa.Column("edd_date", sa.String(length=32), nullable=True),
        sa.Column("gravida", sa.Integer(), nullable=True),
        sa.Column("parity", sa.Integer(), nullable=True),
        sa.Column("outcome", sa.String(length=64), nullable=True),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="active"),
        sa.Column("created_at", sa.String(length=64), nullable=False),
        sa.Column("updated_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "visits",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("client_id", sa.String(length=64), nullable=True, unique=True),
        sa.Column(
            "beneficiary_id",
            sa.String(length=64),
            sa.ForeignKey("beneficiaries.id"),
            nullable=True,
        ),
        sa.Column("worker_id", sa.String(length=64), sa.ForeignKey("workers.id"), nullable=False),
        sa.Column(
            "visit_type_code",
            sa.String(length=64),
            nullable=False,
            server_default="newborn_home_visit",
        ),
        sa.Column("schema_version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("visited_at", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=24), nullable=False, server_default="draft"),
        sa.Column("payload_json", sa.Text(), nullable=False, server_default="{}"),
        sa.Column("risk_flags_json", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("referral_suggested", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("next_due_at", sa.String(length=64), nullable=True),
        sa.Column("transcript_text", sa.Text(), nullable=False, server_default=""),
        sa.Column("language", sa.String(length=16), nullable=False, server_default="hi"),
        sa.Column("input_method", sa.String(length=16), nullable=False, server_default="voice"),
        sa.Column("started_at", sa.String(length=64), nullable=True),
        sa.Column("confirmed_at", sa.String(length=64), nullable=True),
        sa.Column("updated_at", sa.String(length=64), nullable=False),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index(
        "ix_visits_beneficiary_visited",
        "visits",
        ["beneficiary_id", sa.text("visited_at DESC")],
    )
    op.create_index("ix_visits_worker_visited", "visits", ["worker_id", "visited_at"])

    op.create_table(
        "visit_measurements",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("visit_id", sa.String(length=64), sa.ForeignKey("visits.id"), nullable=False),
        sa.Column(
            "beneficiary_id",
            sa.String(length=64),
            sa.ForeignKey("beneficiaries.id"),
            nullable=True,
        ),
        sa.Column("key", sa.String(length=64), nullable=False),
        sa.Column("value_num", sa.Float(), nullable=False),
        sa.Column("unit", sa.String(length=24), nullable=False, server_default=""),
        sa.Column("measured_at", sa.String(length=64), nullable=False),
    )
    op.create_index(
        "ix_visit_measurements_ben_key_at",
        "visit_measurements",
        ["beneficiary_id", "key", "measured_at"],
    )

    op.create_table(
        "visit_amendments",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("visit_id", sa.String(length=64), sa.ForeignKey("visits.id"), nullable=False),
        sa.Column("changed_by", sa.String(length=64), nullable=False),
        sa.Column("changes_json", sa.Text(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "followups",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("visit_id", sa.String(length=64), sa.ForeignKey("visits.id"), nullable=False),
        sa.Column("question_text", sa.Text(), nullable=False),
        sa.Column("target_fields", sa.Text(), nullable=False, server_default="[]"),
        sa.Column("answer_text", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "audio_assets",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("visit_id", sa.String(length=64), sa.ForeignKey("visits.id"), nullable=True),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("duration_ms", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("state", sa.String(length=24), nullable=False, server_default="local"),
        sa.Column("delete_after", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "consents",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column(
            "beneficiary_id",
            sa.String(length=64),
            sa.ForeignKey("beneficiaries.id"),
            nullable=False,
        ),
        sa.Column(
            "kind", sa.String(length=32), nullable=False, server_default="beneficiary_registration"
        ),
        sa.Column("given_by", sa.String(length=16), nullable=False, server_default="self"),
        sa.Column("method", sa.String(length=16), nullable=False, server_default="verbal"),
        sa.Column("policy_version", sa.String(length=32), nullable=False, server_default="v2_2026_01"),
        sa.Column("given_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "sync_queue",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("entity_id", sa.String(length=64), nullable=False),
        sa.Column("op", sa.String(length=24), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.String(length=64), nullable=False),
    )

    op.create_table(
        "audit_log",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("actor_id", sa.String(length=64), nullable=False),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("entity", sa.String(length=32), nullable=False),
        sa.Column("entity_id", sa.String(length=64), nullable=False),
        sa.Column("device_id", sa.String(length=64), nullable=False, server_default="backend"),
        sa.Column("at", sa.String(length=64), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("audit_log")
    op.drop_table("sync_queue")
    op.drop_table("consents")
    op.drop_table("audio_assets")
    op.drop_table("followups")
    op.drop_table("visit_amendments")
    op.drop_index("ix_visit_measurements_ben_key_at", table_name="visit_measurements")
    op.drop_table("visit_measurements")
    op.drop_index("ix_visits_worker_visited", table_name="visits")
    op.drop_index("ix_visits_beneficiary_visited", table_name="visits")
    op.drop_table("visits")
    op.drop_table("pregnancies")
    op.drop_index("uq_beneficiaries_worker_local_code", table_name="beneficiaries")
    op.drop_index("ix_beneficiaries_worker_status_due", table_name="beneficiaries")
    op.drop_table("beneficiaries")
    op.drop_table("visit_types")
    op.drop_table("households")
    op.drop_table("areas")
    op.drop_table("workers")
