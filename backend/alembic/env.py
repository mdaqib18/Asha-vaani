"""Alembic migration environment for Asha Vaani V2."""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.core.settings import get_settings
from app.db.engine import normalize_database_url
from app.db.models import Base

config = context.config

if config.config_file_name is not None and not config.attributes.get("skip_logging_config"):
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def _resolve_url() -> str:
    configured = config.get_main_option("sqlalchemy.url")
    if configured:
        return normalize_database_url(configured)
    return normalize_database_url(get_settings().DATABASE_URL)


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = _resolve_url()
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        render_as_batch=url.startswith("sqlite"),
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = config.attributes.get("connection")
    if connectable is not None:
        context.configure(
            connection=connectable,
            target_metadata=target_metadata,
            render_as_batch=connectable.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()
        return

    url = _resolve_url()
    section = config.get_section(config.config_ini_section, {})
    section["sqlalchemy.url"] = url
    engine = engine_from_config(
        section,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with engine.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            render_as_batch=connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
