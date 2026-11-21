from fastapi import APIRouter, Query

from app.data.beneficiaries import get_beneficiaries

router = APIRouter(prefix="/v1")


@router.get("/health")
def health() -> dict[str, str]:
    """Liveness check."""
    return {"status": "ok"}


@router.get("/beneficiaries")
def list_beneficiaries(asha_id: str = Query(...)) -> list[dict[str, str]]:
    """Return assigned synthetic beneficiaries for an ASHA worker."""
    return get_beneficiaries(asha_id)
