import time
from fastapi import FastAPI, HTTPException
from services.astra_core.persistence import insert_decision
from services.astra_core.policy_pack import load_policy_pack
from services.astra_core.decision import evaluate
from shared.metrics import timing_ms, incr

app = FastAPI()

# Load policy pack at startup (in-memory, versioned)
PACK = load_policy_pack()


@app.get("/health")
def health():
    return {"ok": True, "policy_pack_version": PACK.version}


@app.post("/v1/astra/authority/check")
def authority_check(payload: dict):
    t0 = time.time()

    # Fail-closed: request_id required
    if "request_id" not in payload:
        incr("astra_errors_total", 1)
        raise HTTPException(status_code=403, detail="DENY")

    outcome, reason_code = evaluate(PACK, payload)

    # One authoritative decision artifact insert (always)
    decision_id = insert_decision(payload, outcome, reason_code)

    dt_ms = (time.time() - t0) * 1000.0
    timing_ms("astra_decision_latency_ms", dt_ms, tags={"outcome": outcome})
    incr("astra_requests_total", 1)
    incr("astra_outcome_total", 1, tags={"outcome": outcome})

    # Return outcome (Orchestrator will stop on non-ALLOW)
    if outcome != "ALLOW":
        raise HTTPException(status_code=403, detail=outcome)

    return {"decision_id": decision_id, "outcome": outcome, "reason_code": reason_code}
