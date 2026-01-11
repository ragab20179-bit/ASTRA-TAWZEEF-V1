import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

export const errors = new Rate("errors");
export const execution_latency = new Trend("execution_latency", true);

const BASE_URL = __ENV.BASE_URL || "http://localhost:8001";

export const options = {
  vus: 2,
  duration: "3m",
  thresholds: {
    errors: ["rate<0.1"],
    http_req_duration: ["p(95)<100"],
  },
};

export default function () {
  const payload = JSON.stringify({
    request_id: `baseline-${__VU}-${__ITER}`,
    action: "baseline_ping",
    subject: { type: "candidate", id: "test_candidate" },
    context: { mode: "baseline" },
  });

  const res = http.post(`${BASE_URL}/v2/orchestrator/execute`, payload, {
    headers: { "Content-Type": "application/json" },
    timeout: "10s",
  });

  if (__ITER < 3) {
    console.log(`STATUS=${res.status}`);
    console.log(`BODY=${res.body && res.body.length ? res.body.substring(0, 300) : "EMPTY"}`);
  }

  const ok = check(res, {
    "status is 200 or 503": (r) => r.status === 200 || r.status === 503,
    "no 500s": (r) => r.status !== 500,
  });

  const okId = check(res, {
    "execution_id present when 200": (r) => {
      if (r.status !== 200) return true;
      try {
        const j = r.json();
        return j && typeof j.execution_id === "string" && j.execution_id.length > 0;
      } catch (_) { return false; }
    },
  });

  errors.add(!ok || !okId);

  if (res && res.timings && typeof res.timings.duration === "number") {
    execution_latency.add(res.timings.duration);
  }

  sleep(1);
}
