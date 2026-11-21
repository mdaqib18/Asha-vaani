from __future__ import annotations

import hashlib
import hmac

# Synthetic worker & beneficiary roster for development and demo only (SPEC §13).
def _hash_worker_pin(worker_code: str, pin: str) -> str:
    payload = f"asha_vaani_v2:{worker_code.strip().lower()}:{pin}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


SYNTHETIC_WORKERS: dict[str, dict[str, str]] = {
    "asha_001": {
        "id": "asha_001",
        "worker_code": "asha_001",
        "name": "Sunita Devi",
        "area": "Sub-center A (Synthetic)",
        "pin_hash": _hash_worker_pin("asha_001", "1234"),
    },
    "asha_002": {
        "id": "asha_002",
        "worker_code": "asha_002",
        "name": "Meena Kumari",
        "area": "Sub-center B (Synthetic)",
        "pin_hash": _hash_worker_pin("asha_002", "1234"),
    },
}

SYNTHETIC_BENEFICIARIES: dict[str, list[dict[str, str]]] = {
    "asha_001": [
        {"id": "1042", "label": "Baby of Sunita (synthetic)"},
        {"id": "1043", "label": "Baby of Kavita (synthetic)"},
        {"id": "1057", "label": "Baby of Lakshmi (synthetic)"},
    ],
    "asha_002": [
        {"id": "2011", "label": "Baby of Meena (synthetic)"},
        {"id": "2014", "label": "Baby of Radha (synthetic)"},
    ],
}


def get_beneficiaries(asha_id: str) -> list[dict[str, str]]:
    """Return synthetic assigned beneficiaries for an ASHA worker ID."""
    return list(SYNTHETIC_BENEFICIARIES.get(asha_id, []))


def get_assigned_ids(asha_id: str) -> set[str]:
    """Return assigned beneficiary IDs for an ASHA worker ID."""
    return {item["id"] for item in SYNTHETIC_BENEFICIARIES.get(asha_id, [])}


def verify_worker_credentials(worker_code: str, pin: str) -> dict[str, str] | None:
    """Verify synthetic worker code + PIN using constant-time SHA-256 comparison."""
    code = worker_code.strip().lower()
    worker = SYNTHETIC_WORKERS.get(code)
    if worker is None or not pin:
        return None
    expected = worker["pin_hash"]
    actual = _hash_worker_pin(code, pin.strip())
    if not hmac.compare_digest(actual, expected):
        return None
    return {
        "id": worker["id"],
        "worker_code": worker["worker_code"],
        "name": worker["name"],
        "area": worker["area"],
    }
