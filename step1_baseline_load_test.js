import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 5 },
    { duration: '4m', target: 5 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95 )<500'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function ( ) {
  const payload = JSON.stringify({
    request_id: `test-${Date.now()}`,
    actor: {
      id: 'recruiter-1',
      role: 'recruiter',
    },
    context: {
      domain: 'interview',
      action: 'start',
      consent: true,
    },
  });

  const response = http.post('http://localhost:8001/v2/orchestrator/execute', payload, {
    headers: { 'Content-Type': 'application/json' },
  } );

  check(response, {
    'status is 200': (r) => r.status === 200,
    'outcome is EXECUTED': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.outcome === 'EXECUTED';
      } catch {
        return false;
      }
    },
  });

  sleep(1);
}
