"""
Helpers for authenticating REST requests with Firebase ID tokens.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from fastapi import Request

from ..config.settings import settings
from ..lib.logger import logger
from .firebase import admin_auth


def _normalise_headers(headers: Mapping[str, Any] | None) -> dict[str, str]:
    if not headers:
        return {}
    return {str(k).lower(): str(v) for k, v in headers.items()}


def decode_firebase_claims(headers: Mapping[str, Any] | None) -> dict[str, Any] | None:
    normalised = _normalise_headers(headers)
    auth_header = normalised.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        return None

    token = auth_header[7:].strip()
    if not token:
        return None

    try:
        return admin_auth().verify_id_token(token)
    except Exception as exc:
        logger.warn("REST auth: Firebase token verification failed", {
            "error": type(exc).__name__,
            "detail": str(exc),
        })
        return None


def resolve_user_id(
    headers: Mapping[str, Any] | None,
    *,
    explicit_user_id: str | None = None,
) -> str | None:
    claims = decode_firebase_claims(headers)
    if claims:
        uid = claims.get("uid") or claims.get("sub")
        if isinstance(uid, str) and uid:
            return uid

    if not settings.is_production:
        if explicit_user_id:
            return explicit_user_id

        normalised = _normalise_headers(headers)
        fallback = normalised.get("x-juno-user-id", "")
        if fallback:
            logger.warn("REST auth: using dev fallback x-juno-user-id", {
                "user_id": fallback,
            })
            return fallback

    return None


def resolve_user_id_from_request(
    request: Request,
    *,
    explicit_user_id: str | None = None,
) -> str | None:
    return resolve_user_id(request.headers, explicit_user_id=explicit_user_id)


def resolve_user_id_from_event(
    event: dict,
    *,
    body: dict | None = None,
) -> str | None:
    """Extract uid from a Lambda-style event produced by main._to_lambda_event.

    firebase-admin's verify_id_token sets 'uid' at the top level of the claims
    dict AND also includes 'sub' (the JWT standard claim — same value).  We
    prefer 'uid' first for clarity, then fall back to 'sub'.

    In non-production only: also accepts 'user_id' from the request body so
    local curl/Postman tests don't require a live Firebase token.
    """
    try:
        claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
        uid = claims.get("uid") or claims.get("sub")
        if isinstance(uid, str) and uid:
            return uid
    except (KeyError, TypeError):
        pass

    if not settings.is_production and body:
        uid = body.get("user_id")
        if isinstance(uid, str) and uid:
            logger.warn("REST auth: using dev body fallback user_id", {"user_id": uid})
            return uid

    return None
