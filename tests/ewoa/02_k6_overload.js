import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";

export const errorRate = new Rate("errors");
export const execLatency = new Trend("execution_latency", true);
export const denials = new Counter("denials"); // must be a real metric to appear in summary JSON

const BASE_URL = __ENV.BASE_URL || "http://localhost:8001";

export const options = {
  vus: 50,
  duration: "3m",
  thresholds: {
    errors: ["rate<0.3"],
    http_req_duration: ["p(95)<500"],
  },
};

export default function () {
  const payload = JSON.stringify({
    request_id: `overload-${__VU}-${__ITER}`,
    action: "execute",
    subject: { type: "candidate", id: "test_candidate" },
    context: { mode: "overload" },
  });

  const res = http.post(`${BASE_URL}/v2/orchestrator/execute`, payload, {
    headers: { "Content-Type": "application/json" },
    timeout: "10s",
  });

  // allow 503 in overload mode, but never 500
  const ok = check(res, {
    "status is 200 or 503": (r) => r.status === 200 || r.status === 503,
    "no 500 errors": (r) => r.status !== 500,
  });

  if (!ok) errorRate.add(true);
  else errorRate.add(false);

  if (res && typeof res.timings?.duration === "number") {
    execLatency.add(res.timings.duration);
  }

  // Count denials if server reports them (adjust to your API response shape)
  if (res && res.status === 503) {
    denials.add(1);
  } else {
    // If your API returns a reason code, detect it:
    try {
      const j = res.json();
      if (j && j.decision === "DENY") denials.add(1);
    } catch (_) {}
  }

  sleep(1);
}
