/**
 * Shared k6 helper functions for EWOA fire drill tests
 */

/**
 * Get the base URL for API requests
 * @returns {string} The base URL
 */
export function baseUrl() {
  return __ENV.BASE_URL || "http://localhost:8001";
}

/**
 * Get the headers for API requests, including authentication
 * @returns {object} Headers object
 */
export function headers() {
  const h = {
    "Content-Type": "application/json",
  };
  
  // Add fire drill authentication header if key is provided
  const fireDrillKey = __ENV.EWOA_FIRE_DRILL_KEY;
  if (fireDrillKey) {
    h["X-Fire-Drill-Key"] = fireDrillKey;
  }
  
  return h;
}
