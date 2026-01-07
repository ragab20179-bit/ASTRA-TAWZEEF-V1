import json
import os
from typing import Any, Dict


class PolicyPack:
    def __init__(self, raw: Dict[str, Any]):
        self.raw = raw
        self.version = str(raw.get("version", "0.0.0"))
        self.domains = raw.get("domains", {})

    def get_action_policy(self, domain: str, action: str) -> Dict[str, Any] | None:
        d = self.domains.get(domain)
        if not isinstance(d, dict):
            return None
        actions = d.get("actions")
        if not isinstance(actions, dict):
            return None
        pol = actions.get(action)
        if not isinstance(pol, dict):
            return None
        return pol


def load_policy_pack() -> PolicyPack:
    path = os.getenv("ASTRA_POLICY_PACK_PATH", "/app/services/astra_core/policy_pack.json")
    with open(path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    # Minimal validation (fail-fast startup if wrong)
    if "domains" not in raw or not isinstance(raw["domains"], dict):
        raise RuntimeError("Invalid policy pack: missing domains")
    return PolicyPack(raw)
