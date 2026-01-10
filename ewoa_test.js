import http from 'k6/http';
import { check, sleep } from 'k6';

// Custom UUID v4 generator (since k6 doesn't support experimental uuid module )
function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

export const options = {
  stages: [
    { duration: '1m', target: 2 },   // Baseline: 2 VUs
    { duration: '2m', target: 2 },   // Sustained: 2 VUs
    { duration: '30s', target: 0 },  // Cool down
  ],
};

export default function () {
  // Test ALLOW case (with consent)
  const allowRes = http.post('http://localhost:8001/v2/orchestrator/execute', JSON.stringify({
    request_id: generateUUID( ),
    actor: { id: 'recruiter-1', role: 'recruiter' },
    context: { domain: 'interview', action: 'start', consent: true }
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(allowRes, {
    'ALLOW: status 200': (r) => r.status === 200,
    'ALLOW: executed': (r) => r.json('outcome') === 'EXECUTED',
  });

  sleep(1);

  // Test DENY case (without consent)
  const denyRes = http.post('http://localhost:8001/v2/orchestrator/execute', JSON.stringify({
    request_id: generateUUID( ),
    actor: { id: 'recruiter-2', role: 'recruiter' },
    context: { domain: 'interview', action: 'start' }
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(denyRes, {
    'DENY: status 200': (r) => r.status === 200,
    'DENY: denied': (r) => r.json('outcome') === 'DENY',
  });

  sleep(1);
}
