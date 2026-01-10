/**
 * k6 Baseline Load Test
 * 
 * Purpose: Establish baseline performance metrics for ASTRA TAWZEEF
 * 
 * Metrics captured:
 * - P50/P95/P99 latency
 * - Request rate
 * - Success rate
 * - Error rate
 * 
 * Usage: k6 run tests/ewoa/01_k6_baseline.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors' );
const executionLatency = new Trend('execution_latency');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 2 },   // Ramp up to 2 VUs
    { duration: '2m', target: 2 },    // Stay at 2 VUs (baseline load)
    { duration: '30s', target: 0 },   // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95 )<100'],  // 95% of requests must complete below 100ms
    'errors': ['rate<0.1'],              // Error rate must be below 10%
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
    request_id: generateUUID( ),
    actor: {
      id: `test_user_${__VU}`,
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
  };
  
  const startTime = Date.now();
  const response = http.post(url, payload, params );
  const endTime = Date.now();
  
  // Record custom metrics
  executionLatency.add(endTime - startTime);
  
  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has artifact': (r) => {
      try {
        const body = JSON.parse(r.body);
        const hasArtifact = body.artifact !== undefined;
        if (!hasArtifact) {
          console.log(`Response missing artifact. Body: ${r.body}`);
        }
        return hasArtifact;
      } catch (e) {
        console.log(`Invalid JSON response body: ${r.body}`);
        return false;
      }
    },
  });
  
  errorRate.add(!success);
  
  // Think time between requests
  sleep(1);
}

// Setup function (runs once at start)
export function setup() {
  console.log('=== EWOA Baseline Load Test ===');
  console.log('Target: 2 VUs for 2 minutes');
  console.log('Threshold: P95 < 100ms');
  console.log('================================');
}

// Teardown function (runs once at end)
export function teardown(data) {
  console.log('=== Baseline Test Complete ===');
}
