import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";
import { baseUrl, headers } from "./_k6_common.js";

export const errors = new Rate("errors");
export const execution_latency = new Trend("execution_latency", true);
export const denials = new Counter("denials");

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

  const res = http.post(`${baseUrl()}/v2/orchestrator/execute`, payload, {
    headers: headers(),
    timeout: "10s",
  });

  const ok = check(res, {
    "status is 200 or 503": (r) => r.status === 200 || r.status === 503,
    "no 500 errors": (r) => r.status !== 500,
  });

  errors.add(!ok);

  if (res && res.timings && typeof res.timings.duration === "number") {
    execution_latency.add(res.timings.duration);
  }

  // Count denials based on your API behavior:
  // - if overload returns 503 when ASTRA denies/blocks, count it
  if (res.status === 503) denials.add(1);

  sleep(1);
}
