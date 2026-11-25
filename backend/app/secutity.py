"""Security checks for the PBX endpoints."""

import os
import secrets

from fastapi import HTTPException, Request, Security
from fastapi.security import APIKeyHeader

# Tells FastAPI to read the "X-API-Key" header.
# It also adds the "Authorize" button to the /docs page.
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


def allowed_ips() -> set[str]:
    """Read PBX_ALLOWED_IPS from .env, e.g. "127.0.0.1,::1"."""
    value = os.getenv("PBX_ALLOWED_IPS", "")
    return {ip.strip() for ip in value.split(",") if ip.strip()}


def require_pbx(request: Request, api_key: str | None = Security(api_key_header)) -> None:
    """Runs before every PBX endpoint. Stops the request if it isn't from the PBX."""
    # 1. The API key must match. compare_digest compares safely (no timing hints).
    expected = os.getenv("PBX_API_KEY", "")
    if not expected or not api_key or not secrets.compare_digest(api_key, expected):
        raise HTTPException(status_code=401, detail="Missing or wrong API key")

    # 2. The caller's IP address must be on the allowed list.
    client_ip = request.client.host if request.client else ""
    if client_ip not in allowed_ips():
        raise HTTPException(status_code=403, detail="This address is not allowed")
