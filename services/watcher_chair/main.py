import os
import time
import requests
from fastapi import FastAPI, HTTPException
from services.watcher_chair.persistence import insert_watcher
from shared.metrics import timing_ms, incr

app = FastAPI()

ASTRA_URL = os.getenv("ASTRA_URL", "http://astra-core:8000/v1/astra/authority/check")
ASTRA_TIMEOUT_S = float(os.getenv("ASTRA_TIMEOUT_S", "0.3"))
WATCHER_ENABLED = os.getenv("WATCHER_ENABLED", "false").lower() == "true"


@app.get("/health")
def health():
    return {"ok": True, "enabled": WATCHER_ENABLED}


@app.post("/v2/watcher/submit")
def watcher_submit(payload: dict):
    if not WATCHER_ENABLED:
        raise HTTPException(status_code=403, detail="WATCHER_DISABLED")

    t0 = time.time()

    watcher = payload.get("watcher", {})
    watcher_id = watcher.get("id", "")
    if not watcher_id:
        raise HTTPException(status_code=403, detail="DENIED")

    incr("watch_requests_total", 1)

    # Gate via ASTRA (no retries)
    try:
        res = requests.post(ASTRA_URL, json=payload, timeout=ASTRA_TIMEOUT_S)
    except Exception:
        raise HTTPException(status_code=503, detail="ASTRA_UNAVAILABLE")

    if res.status_code != 200:
        raise HTTPException(status_code=403, detail="DENIED")

    decision = res.json()
    allowed = decision.get("outcome") == "ALLOW"

    # One watcher artifact (does not override execution)
    t_db0 = time.time()
    watcher_artifact_id = insert_watcher(
        decision.get("decision_id", "00000000-0000-0000-0000-000000000000"),
        watcher_id,
        payload,
        "APPLIED" if allowed else "DENIED",
    )
    timing_ms("watch_db_insert_latency_ms", (time.time() - t_db0) * 1000.0)
    timing_ms("watch_total_latency_ms", (time.time() - t0) * 1000.0)

    return {
        "watcher_action_id": watcher_artifact_id,
        "astra_decision_id": decision.get("decision_id"),
        "outcome": "APPLIED" if allowed else "DENIED",
    }
