import pytest

from app.core.config_loader import VisitTypeConfig, load_visit_config


@pytest.fixture
def newborn_config() -> VisitTypeConfig:
    """Return a fresh copy of the newborn_home_visit configuration."""
    return load_visit_config("newborn_home_visit").model_copy(deep=True)
