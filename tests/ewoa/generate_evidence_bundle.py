#!/usr/bin/env python3
"""
EWOA Evidence Bundle Generator

This script generates an EWOA evidence bundle in JSON format based on the
metrics collected during the fire drill, conforming to EWOA_EVIDENCE_AND_ALERT_SPEC_v1.md.
"""

import json
import sys
import uuid
from datetime import datetime, timezone
from typing import List, Dict, Any


def evaluate_alerts(signals: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Evaluate alerts based on the signals collected during the fire drill.
    
    Args:
        signals: List of signal dictionaries
        
    Returns:
        List of alert dictionaries
    """
    alerts = []
    
    for signal in signals:
        if signal["signal_id"] == "exec_latency_p95" and signal["value"] > 100:
            alerts.append({
                "alert_id": "LATENCY_BUDGET_EXCEEDED",
                "severity": "HIGH",
                "triggered": True,
                "triggered_at": datetime.now(timezone.utc).isoformat(),
                "condition": "p95_latency > 100ms",
                "evidence": [signal["signal_id"]]
            })
        elif signal["signal_id"] == "error_rate" and signal["value"] > 5:
            alerts.append({
                "alert_id": "ASTRA_UNAVAILABLE",
                "severity": "CRITICAL",
                "triggered": True,
                "triggered_at": datetime.now(timezone.utc).isoformat(),
                "condition": "ASTRA error rate > 5%",
                "evidence": [signal["signal_id"]]
            })
    
    return alerts


def generate_evidence_bundle(
    drills: List[Dict[str, Any]],
    signals: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """
    Generate an EWOA evidence bundle.
    
    Args:
        drills: List of drill dictionaries
        signals: List of signal dictionaries
        
    Returns:
        Evidence bundle dictionary
    """
    alerts = evaluate_alerts(signals)
    
    # Determine overall result
    highest_severity = "LOW"
    if any(alert["severity"] == "CRITICAL" for alert in alerts):
        highest_severity = "CRITICAL"
    elif any(alert["severity"] == "HIGH" for alert in alerts):
        highest_severity = "HIGH"
    elif any(alert["severity"] == "MEDIUM" for alert in alerts):
        highest_severity = "MEDIUM"
        
    result = "FAIL" if highest_severity in ["HIGH", "CRITICAL"] else "PASS"
    
    return {
        "schema": "EWOA_EVIDENCE_BUNDLE",
        "version": "1.0",
        "bundle_id": str(uuid.uuid4()),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "context": {
            "environment": "local",
            "system": "ASTRA_TAWZEEF",
            "zone": "single-zone-id"
        },
        "drills": drills,
        "signals": signals,
        "alerts": alerts,
        "summary": {
            "drills_total": len(drills),
            "drills_passed": sum(1 for drill in drills if drill["status"] == "PASS"),
            "drills_failed": sum(1 for drill in drills if drill["status"] == "FAIL"),
            "alerts_total": len(alerts),
            "highest_severity": highest_severity,
            "result": result,
            "evidence_complete": True if result == "PASS" else False
        }
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
    
    # Create signals list
    signals = [
        {
            "signal_id": "exec_latency_p95",
            "source": "k6_overload_test",
            "metric": "http_req_duration{p(95 )}",
            "value": p95_latency_ms,
            "unit": "ms",
            "observed_at": datetime.now(timezone.utc).isoformat()
        },
        {
            "signal_id": "error_rate",
            "source": "k6_overload_test",
            "metric": "errors",
            "value": error_rate_percent,
            "unit": "%",
            "observed_at": datetime.now(timezone.utc).isoformat()
        },
        {
            "signal_id": "denial_rate",
            "source": "k6_overload_test",
            "metric": "denials",
            "value": denial_rate_percent,
            "unit": "%",
            "observed_at": datetime.now(timezone.utc).isoformat()
        }
    ]
    
    # Create drills list (placeholder for now)
    drills = [
        {
            "drill_id": "BASELINE_TEST_001",
            "description": "Baseline performance test",
            "started_at": datetime.now(timezone.utc).isoformat(),
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "status": "PASS",
            "signals_observed": [],
            "alerts_triggered": []
        },
        {
            "drill_id": "OVERLOAD_TEST_001",
            "description": "Overload test to trigger latency SLA violation",
            "started_at": datetime.now(timezone.utc).isoformat(),
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "status": "FAIL" if p95_latency_ms > 100 else "PASS",
            "signals_observed": ["exec_latency_p95", "error_rate", "denial_rate"],
            "alerts_triggered": ["LATENCY_BUDGET_EXCEEDED"] if p95_latency_ms > 100 else []
        }
    ]
    
    # Generate evidence bundle
    evidence_bundle = generate_evidence_bundle(drills, signals)
    
    # Output as JSON
    print(json.dumps(evidence_bundle, indent=2))


if __name__ == "__main__":
    main()
