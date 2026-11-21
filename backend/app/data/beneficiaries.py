# Synthetic beneficiary roster for development and demo only (SPEC §13).
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
