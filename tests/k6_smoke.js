import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = { vus: 1, duration: '30s' };

export default function () {
  const url = 'http://localhost:8001/v2/orchestrator/execute';
  const payload = JSON.stringify({
    request_id: '11111111-1111-1111-1111-111111111111',
    actor: { id: 'user-1', role: 'recruiter' },
    context: { domain: 'interview', action: 'start', consent: true }
  });

  const res = http.post(url, payload, { headers: { 'Content-Type': 'application/json' } });
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.2);
}
