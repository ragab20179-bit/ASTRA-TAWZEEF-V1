import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";
import { baseUrl, headers } from "./_k6_common.js";

export const errors = new Rate("errors");
export const execution_latency = new Trend("execution_latency", true);

export const options = {
  vus: Number(__ENV.VUS || 2),
  duration: __ENV.DURATION || "3m",
  thresholds: {
    errors: ["rate<0.1"],
    http_req_duration: ["p(95)<200"],
  },
};

export default function () {
  const payload = JSON.stringify({
    request_id: `baseline-${__VU}-${__ITER}`,
    action: "baseline_ping",
    subject: { type: "candidate", id: "test_candidate" },
    context: { mode: "baseline" },
  });

  const res = http.post(`${baseUrl()}/v2/orchestrator/execute`, payload, {
    headers: headers(),
    timeout: "10s",
  });

  if (__ITER < 3) {
    console.log(`STATUS=${res.status}`);
    console.log(`BODY=${res.body && res.body.length ? res.body.substring(0, 300) : "EMPTY"}`);
  }

  const ok = check(res, {
    "status is 200": (r) => r.status === 200,
    "has execution_id": (r) => {
      try {
        const j = r.json();
        return !!j.execution_id;
      } catch (_) {
        return false;
      }
    },
  });

  errors.add(!ok);
  execution_latency.add(res.timings.duration);

  sleep(1);
}
