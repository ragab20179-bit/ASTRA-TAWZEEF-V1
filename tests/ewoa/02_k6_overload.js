/**
 * k6 Overload Test
 * 
 * Purpose: Test system behavior under load exceeding designed capacity
 * 
 * Expected behavior:
 * - Latency increases gradually
 * - System remains stable (no crash)
 * - Graceful degradation
 * - EWOA alert fires when latency exceeds budget
 * 
 * Usage: k6 run tests/ewoa/02_k6_overload.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const executionLatency = new Trend('execution_latency');
const denialCount = new Counter('denials');
const timeoutCount = new Counter('timeouts');

// Test configuration - aggressive load
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 VUs
    { duration: '1m', target: 50 },    // Spike to 50 VUs (overload)
    { duration: '1m', target: 50 },    // Sustain overload
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    // We EXPECT these to fail under overload - that's the point
    'http_req_duration': ['p(95)<500'],  // Relaxed threshold
    'errors': ['rate<0.3'],              // Allow up to 30% errors
  },
};

// Generate UUID for request_id
function generateUUID() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

// Main test function
export default function () {
  const url = 'http://orchestrator:8001/v2/orchestrator/execute';
  
  const payload = JSON.stringify({
    request_id: generateUUID(),
    actor: {
      id: `overload_user_${__VU}_${__ITER}`,
      role: 'recruiter'
    },
    context: {
      domain: 'interview',
      action: 'start',
      consent: true
    }
  });
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    timeout: '10s',  // 10 second timeout
  };
  
  const startTime = Date.now();
  const response = http.post(url, payload, params);
  const endTime = Date.now();
  
  // Record custom metrics
  executionLatency.add(endTime - startTime);
  
  // Check response
  const success = check(response, {
    'status is 200 or 503': (r) => r.status === 200 || r.status === 503,
    'no 500 errors': (r) => r.status !== 500,
  });
  
  // Track denials and timeouts
  if (response.status === 503) {
    denialCount.add(1);
  }
  
  if (response.status === 0) {  // Timeout
    timeoutCount.add(1);
  }
  
  errorRate.add(!success);
  
  // Minimal think time (aggressive)
  sleep(0.1);
}

// Setup function (runs once at start)
export function setup() {
  console.log('=== EWOA Overload Test ===');
  console.log('Target: 50 VUs (overload)');
  console.log('Expected: Latency increase, possible denials');
  console.log('Alert: exec_total_latency_ms_p95 > 100ms');
  console.log('==========================');
  
  // Verify services are up before starting
  const healthCheck = http.get('http://astra-core:8000/health');
  if (healthCheck.status !== 200) {
    throw new Error('Services not ready - health check failed');
  }
}

// Teardown function (runs once at end)
export function teardown(data) {
  console.log('=== Overload Test Complete ===');
  console.log('Check EWOA alerts for latency threshold breach');
}
