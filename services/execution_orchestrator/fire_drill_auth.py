"""
Fire Drill Authentication Module

Provides authentication for EWOA fire drill requests using ephemeral keys.
"""

import os
from typing import Optional
from fastapi import Header, HTTPException


def verify_fire_drill_auth(x_fire_drill_key: Optional[str] = Header(None)) -> bool:
    """
    Verify fire drill authentication using ephemeral key.
    
    Args:
        x_fire_drill_key: The fire drill key from request header
        
    Returns:
        True if authentication is valid
        
    Raises:
        HTTPException: If authentication fails
    """
    expected_key = os.getenv("EWOA_FIRE_DRILL_KEY")
    
    # If no key is configured, fire drill auth is disabled
    if not expected_key:
        raise HTTPException(
            status_code=403,
            detail="Fire drill authentication not configured"
        )
    
    # Verify the provided key matches
    if not x_fire_drill_key or x_fire_drill_key != expected_key:
        raise HTTPException(
            status_code=403,
            detail="Invalid or missing fire drill authentication key"
        )
    
    return True
