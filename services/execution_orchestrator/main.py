import os
import time
import requests
from fastapi import FastAPI, HTTPException
from services.execution_orchestrator.persistence import insert_execution
from shared.metrics import timing_ms, incr

app = FastAPI()

ASTRA_URL = os.getenv("ASTRA_URL", "http://astra-core:8000/v1/astra/authority/check")
ASTRA_TIMEOUT_S = float(os.getenv("ASTRA_TIMEOUT_S", "0.3"))


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/v2/orchestrator/execute")
def execute(payload: dict):
    t0 = time.time()
    incr("exec_requests_total", 1)

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
