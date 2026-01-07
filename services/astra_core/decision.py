from typing import Tuple
from services.astra_core.policy_pack import PolicyPack


def _has_requirement(payload: dict, req: str) -> bool:
    # Requirements are looked up ONLY from payload; no remote calls.
    if req == "consent":
        # Allow consent in either "consent": true or "context": {"consent": true}
        if payload.get("consent") is True:
            return True
        ctx = payload.get("context", {})
        return isinstance(ctx, dict) and ctx.get("consent") is True

    if req == "delegation_token":
        # Allow in "watcher": {"delegation_token": "..."} or top-level "delegation_token"
        if isinstance(payload.get("delegation_token"), str) and payload["delegation_token"]:
            return True
        watcher = payload.get("watcher", {})
        return isinstance(watcher, dict) and isinstance(watcher.get("delegation_token"), str) and bool(watcher.get("delegation_token"))

    # Unknown requirement → fail-closed
    return False


def evaluate(pack: PolicyPack, payload: dict) -> Tuple[str, str]:
    """
    Returns: (outcome, reason_code)
    outcome in {ALLOW, DENY, ESCALATE, DEGRADE}
    """
    # Fail-closed: required structural fields
    actor = payload.get("actor", {})
    ctx = payload.get("context", {})

    if not isinstance(actor, dict) or not isinstance(ctx, dict):
        return ("DENY", "BAD_PAYLOAD")

    actor_role = actor.get("role", "")
    domain = ctx.get("domain", "")
    action = ctx.get("action", "")

    if not actor_role or not domain or not action:
        return ("DENY", "MISSING_FIELDS")

    pol = pack.get_action_policy(domain, action)
    if pol is None:
        return ("DENY", "UNKNOWN_ACTION")

    allow_roles = pol.get("allow_roles", [])
    if not isinstance(allow_roles, list) or actor_role not in allow_roles:
        return ("DENY", "ROLE_NOT_ALLOWED")

    reqs = pol.get("requires", [])
    if not isinstance(reqs, list):
        return ("DENY", "BAD_POLICY")

    for r in reqs:
        if not _has_requirement(payload, str(r)):
            return ("DENY", f"REQUIREMENT_MISSING:{r}")

    return ("ALLOW", "RULE_PASS")
