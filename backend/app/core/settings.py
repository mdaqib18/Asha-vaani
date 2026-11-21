from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_ENV_FILE = Path(__file__).resolve().parent.parent.parent / ".env"


class Settings(BaseSettings):
    """Application environment configuration loaded from .env."""

    GNANI_API_KEY: str | None = None
    GNANI_STT_URL: str = "https://api.vachana.ai/stt/v3"
    GNANI_TTS_URL: str = "https://api.vachana.ai/api/v1/tts/inference"
    GNANI_STT_MODEL: str = "prisma-v3.0"
    GNANI_STT_FORMAT: str = "transcribe"
    GNANI_TTS_MODEL: str = "timbre-v3.0"
    GNANI_TTS_VOICE: str = "Lakshmi"
    GNANI_TIMEOUT_S: float = 30.0
    LLM_PROVIDER: str = "gemini"
    LLM_API_KEY: str | None = None
    LLM_MODEL: str | None = None
    LLM_BASE_URL: str = "https://generativelanguage.googleapis.com/v1beta"
    LLM_TIMEOUT_S: float = 30.0
    DATABASE_URL: str = "sqlite:///./ashavaani.db"
    MAX_FOLLOWUPS: int = 2

    model_config = SettingsConfigDict(
        env_file=_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached Settings instance."""
    return Settings()
