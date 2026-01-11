#!/usr/bin/env python3
"""
EWOA Evidence Bundle Generator

This script generates an EWOA evidence bundle in JSON format based on the
metrics collected during the fire drill.
"""

import json
import sys
from datetime import datetime
from typing import List, Dict, Any


def evaluate_alerts(metrics: Dict[str, float]) -> List[Dict[str, Any]]:
    """
    Evaluate alerts based on the metrics collected during the fire drill.
    
    Args:
        metrics: Dictionary containing the metrics
        
    Returns:
        List of alert dictionaries
    """
    alerts = []
    
    # High Latency Alert
    if metrics.get("p95_latency_ms", 0) > 100:
        alerts.append({
            "name": "High Latency",
            "severity": "HIGH",
            "details": f"P95 latency ({metrics["p95_latency_ms"]}ms) exceeds threshold (100ms)"
        })
    
    # High Error Rate Alert
    if metrics.get("error_rate_percent", 0) > 10:
        alerts.append({
            "name": "High Error Rate",
            "severity": "CRITICAL",
            "details": f"Error rate ({metrics["error_rate_percent"]}%) exceeds threshold (10%)"
        })
    
    # High Denial Rate Alert
    if metrics.get("denial_rate_percent", 0) > 5:
        alerts.append({
            "name": "High Denial Rate",
            "severity": "MEDIUM",
            "details": f"Denial rate ({metrics["denial_rate_percent"]}%) exceeds threshold (5%)"
        })
    
    return alerts


def generate_evidence_bundle(
    drills: List[Dict[str, Any]],
    metrics: Dict[str, float]
) -> Dict[str, Any]:
    """
    Generate an EWOA evidence bundle.
    
    Args:
        drills: List of drill dictionaries
        metrics: Dictionary containing the aggregated metrics
        
    Returns:
        Evidence bundle dictionary
    """
    alerts = evaluate_alerts(metrics)
    
    # Determine overall result
    result = "FAIL" if any(alert["severity"] in ["HIGH", "CRITICAL"] for alert in alerts) else "PASS"
    
    return {
        "schema": "EWOA_EVIDENCE_BUNDLE",
        "version": "1.0",
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "drills": drills,
        "metrics": metrics,
        "alerts": alerts,
        "result": result
    }


def main():
    """Main entry point for the script."""
    if len(sys.argv) < 2:
        print("Usage: generate_evidence_bundle.py <p95_latency_ms> [error_rate_percent] [denial_rate_percent]")
        sys.exit(1)
    
    # Parse command-line arguments
    p95_latency_ms = float(sys.argv[1])
    error_rate_percent = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    denial_rate_percent = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    
    # Create metrics dictionary
    metrics = {
        "p95_latency_ms": p95_latency_ms,
        "error_rate_percent": error_rate_percent,
        "denial_rate_percent": denial_rate_percent
    }
    
    # Create drills list (placeholder for now)
    drills = [
        {
            "name": "Baseline Test",
            "status": "PASS",
            "metrics": {}
        },
        {
            "name": "Overload Test",
            "status": "FAIL" if p95_latency_ms > 100 else "PASS",
            "metrics": {
                "p95_latency_ms": p95_latency_ms
            }
        }
    ]
    
    # Generate evidence bundle
    evidence_bundle = generate_evidence_bundle(drills, metrics)
    
    # Output as JSON
    print(json.dumps(evidence_bundle, indent=2))


if __name__ == "__main__":
    main()
