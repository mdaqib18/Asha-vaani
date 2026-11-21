from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application environment configuration loaded from .env."""

    GNANI_API_KEY: str | None = None
    GNANI_STT_URL: str | None = None
    GNANI_TTS_URL: str | None = None
    LLM_PROVIDER: str | None = None
    LLM_API_KEY: str | None = None
    LLM_MODEL: str | None = None
    DATABASE_URL: str = "sqlite:///./ashavaani.db"
    MAX_FOLLOWUPS: int = 2

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached Settings instance."""
    return Settings()
