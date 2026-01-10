import http from 'k6/http';
import { check, sleep } from 'k6';

function generateUUID( ) {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    var r = Math.random() * 16 | 0,
        v = c == 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

export const options = {
  stages: [
    { duration: '1m', target: 5 },
    { duration: '4m', target: 5 },
    { duration: '1m', target: 0 },
  ],
};

export default function () {
  // Test 1: ALLOW case (with consent)
  const allowPayload = JSON.stringify({
    request_id: generateUUID(),
    actor: { id: 'recruiter-1', role: 'recruiter' },
    context: { domain: 'interview', action: 'start', consent: true },
  });

  const allowResponse = http.post('http://localhost:8001/v2/orchestrator/execute', allowPayload, {
    headers: { 'Content-Type': 'application/json' },
  } );

  check(allowResponse, {
    'ALLOW: status 200': (r) => r.status === 200,
    'ALLOW: executed': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.outcome === 'EXECUTED';
      } catch { return false; }
    },
  });

  sleep(1);

  // Test 2: DENY case (without consent)
  const denyPayload = JSON.stringify({
    request_id: generateUUID(),
    actor: { id: 'recruiter-2', role: 'recruiter' },
    context: { domain: 'interview', action: 'start' },
  });

  const denyResponse = http.post('http://localhost:8001/v2/orchestrator/execute', denyPayload, {
    headers: { 'Content-Type': 'application/json' },
  } );

  check(denyResponse, {
    'DENY: status 200': (r) => r.status === 200,
    'DENY: denied': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.outcome === 'DENY';
      } catch { return false; }
    },
  });

  sleep(1);
}
