import os
import time
import requests
from typing import Optional
from fastapi import FastAPI, HTTPException, Header
from services.execution_orchestrator.persistence import insert_execution
from services.execution_orchestrator.fire_drill_auth import verify_fire_drill_auth
from services.execution_orchestrator.policy import should_allow_request, is_fire_drill_request
from shared.metrics import timing_ms, incr

app = FastAPI()

ASTRA_URL = os.getenv("ASTRA_URL", "http://astra-core:8000/v1/astra/authority/check")
ASTRA_TIMEOUT_S = float(os.getenv("ASTRA_TIMEOUT_S", "0.3"))


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/v2/orchestrator/execute")
def execute(payload: dict, x_fire_drill_key: Optional[str] = Header(None)):
    t0 = time.time()
    incr("exec_requests_total", 1)

    # Check if fire drill authentication is provided and valid
    is_fire_drill_authenticated = False
    if x_fire_drill_key:
        try:
            verify_fire_drill_auth(x_fire_drill_key)
            is_fire_drill_authenticated = True
        except HTTPException:
            # Invalid fire drill key provided
            pass

    # Apply policy: determine if request should be allowed
    if not should_allow_request(payload, is_fire_drill_authenticated):
        incr("exec_denied_total", 1, tags={"reason": "auth_required"})
        raise HTTPException(status_code=403, detail="DENIED")

    # For fire drill requests with valid auth, skip ASTRA and return success immediately
    if is_fire_drill_request(payload) and is_fire_drill_authenticated:
        # Generate a mock execution ID for fire drill
        execution_id = f"fire_drill_{int(time.time() * 1000)}"
        timing_ms("exec_total_latency_ms", (time.time() - t0) * 1000.0)
        return {
            "execution_id": execution_id,
            "outcome": "EXECUTED",
            "fire_drill": True
        }

    # One synchronous ASTRA gate (no retries)
    t_astra0 = time.time()
    try:
        res = requests.post(ASTRA_URL, json=payload, timeout=ASTRA_TIMEOUT_S)
    except Exception:
        incr("exec_denied_total", 1)
        raise HTTPException(status_code=503, detail="ASTRA_UNAVAILABLE")
    timing_ms("exec_astra_latency_ms", (time.time() - t_astra0) * 1000.0)

    if res.status_code != 200:
        incr("exec_denied_total", 1)
        raise HTTPException(status_code=403, detail="DENIED")

    decision = res.json()
    if decision.get("outcome") != "ALLOW":
        incr("exec_denied_total", 1, tags={"outcome": decision.get("outcome", "UNKNOWN")})
        return {"outcome": decision.get("outcome"), "astra_decision_id": decision.get("decision_id")}

    # One execution artifact insert
    t_db0 = time.time()
    execution_id = insert_execution(decision["decision_id"], payload, "EXECUTED")
    timing_ms("exec_db_insert_latency_ms", (time.time() - t_db0) * 1000.0)

    timing_ms("exec_total_latency_ms", (time.time() - t0) * 1000.0)
    return {"execution_id": execution_id, "astra_decision_id": decision["decision_id"], "outcome": "EXECUTED"}
