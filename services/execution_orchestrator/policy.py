"""
Policy Module

Determines whether a request should be allowed based on context and authentication.
"""

from typing import Dict, Any


def is_fire_drill_request(payload: Dict[str, Any]) -> bool:
    """
    Determine if a request is a fire drill request.
    
    Args:
        payload: The request payload
        
    Returns:
        True if this is a fire drill request
    """
    context = payload.get("context", {})
    mode = context.get("mode", "")
    
    # Fire drill requests have mode="baseline" or mode="overload"
    return mode in ["baseline", "overload"]


def should_allow_request(payload: Dict[str, Any], is_fire_drill_authenticated: bool) -> bool:
    """
    Determine if a request should be allowed.
    
    Args:
        payload: The request payload
        is_fire_drill_authenticated: Whether fire drill authentication was provided
        
    Returns:
        True if the request should be allowed
    """
    # If it's a fire drill request, require fire drill authentication
    if is_fire_drill_request(payload):
        return is_fire_drill_authenticated
    
    # For non-fire-drill requests, apply normal authentication logic
    # (In production, this would check user tokens, API keys, etc.)
    return True
