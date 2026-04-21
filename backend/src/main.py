"""
Juno backend — FastAPI application.

Routes:
  GET  /health -> liveness probe
  WebSocket /voice/stream -> real-time Nova Sonic voice session
  POST /chat -> text conversation (Claude)
  POST /nutrition/analyze -> OCR nutrition analysis
  POST /notification-reply -> notification reply -> chat
  POST /scheduler/tick -> deliver due reminders (call from cron)

Local dev:
  uvicorn src.main:app --reload --port 8000
"""

from __future__ import annotations

import asyncio
import json
import os
import time
import uuid

from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2.id_token import verify_oauth2_token
from fastapi import Depends, FastAPI, HTTPException, Request, WebSocket
from fastapi.responses import JSONResponse, StreamingResponse
from mangum import Mangum
from starlette.middleware.base import BaseHTTPMiddleware

from .config.settings import settings
from .handlers.chat import handle_chat_stream
from .handlers.devices import register_device
from .handlers.connectors import (
    connect_google_calendar,
    disconnect_google_calendar,
    get_connectors,
    google_calendar_webhook,
    sync_google_calendar,
)
from .handlers.dietary_profile import handle_get_dietary_profile, handle_save_dietary_profile
from .handlers.daily_notification import (
    handle_plan_all_users,
    handle_plan_one_user,
    handle_send_nudge,
)
from .handlers.engagement import (
    handle_engagement_notify,
    handle_engagement_orchestrate,
    handle_engagement_responded,
)
from .handlers.notification_reply import handle_notification_reply_request
from .handlers.nutrition import handle_nutrition_analyze_request, handle_nutrition_scan_request
from .handlers.scheduler import handle_scheduler_tick
from .lib.logger import logger
from .services.gemini_client import get_gemini_client
from .services.request_auth import decode_firebase_claims
from .voice_gateway.ws_handler import voice_stream_handler

app = FastAPI(title="Juno Backend", version="1.0.0")


# Request / Response logging middleware
class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = str(uuid.uuid4())[:8]
        start = time.monotonic()

        # Skip noisy health checks
        if request.url.path != "/health":
            logger.info("→ HTTP request", {
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
            })

        try:
            response = await call_next(request)
            if request.url.path != "/health":
                duration_ms = int((time.monotonic() - start) * 1000)
                level_fn = logger.error if response.status_code >= 500 else (
                    logger.warn if response.status_code >= 400 else logger.info
                )
                level_fn("← HTTP response", {
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status": response.status_code,
                    "duration_ms": duration_ms,
                })
            return response
        except Exception as exc:
            duration_ms = int((time.monotonic() - start) * 1000)
            logger.exception("← HTTP unhandled exception", {
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "duration_ms": duration_ms,
                "error": str(exc),
            })
            raise


app.add_middleware(RequestLoggingMiddleware)


@app.get("/health")
async def health() -> dict[str, bool]:
    return {"ok": True}


# Voice Gateway
@app.websocket("/voice/stream")
async def voice_stream(ws: WebSocket) -> None:
    await voice_stream_handler(ws)


# REST endpoints
def _to_lambda_event(request: Request, body: bytes) -> dict:
    """Convert FastAPI Request into a Lambda-style event dict."""
    claims = decode_firebase_claims(request.headers) or {}
    return {
        "body": body.decode("utf-8"),
        "requestContext": {
            "authorizer": {
                "jwt": {
                    "claims": claims
                }
            }
        },
        "headers": dict(request.headers),
    }


def _lambda_response(result: dict) -> JSONResponse:
    """
    Lambda-style handlers return {"statusCode": int, "body": str}.
    result["body"] is already a JSON string — parse it back to a dict so
    JSONResponse doesn't double-encode it into a JSON-wrapped string.
    """
    body_str = result.get("body", "{}")
    try:
        body_dict = json.loads(body_str) if isinstance(body_str, str) else body_str
    except (json.JSONDecodeError, TypeError):
        body_dict = {"raw": body_str}
    return JSONResponse(content=body_dict, status_code=result.get("statusCode", 500))


@app.post("/devices/register")
async def devices_register_endpoint(request: Request) -> JSONResponse:
    return await register_device(request)


@app.post("/chat")
async def chat_endpoint(request: Request) -> StreamingResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    return await handle_chat_stream(event)


@app.post("/nutrition/scan")
async def nutrition_scan_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_nutrition_scan_request(event)
    return _lambda_response(result)


@app.post("/nutrition/analyze")
async def nutrition_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_nutrition_analyze_request(event)
    return _lambda_response(result)


@app.get("/nutrition/profile")
async def nutrition_profile_get_endpoint(request: Request) -> JSONResponse:
    event = _to_lambda_event(request, b"")
    result = await handle_get_dietary_profile(event)
    return _lambda_response(result)


@app.post("/nutrition/profile")
async def nutrition_profile_save_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_save_dietary_profile(event)
    return _lambda_response(result)


@app.post("/notification-reply")
async def notification_reply_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_notification_reply_request(event)
    return _lambda_response(result)


_CLOUD_RUN_AUDIENCE = "https://juno-backend-620715294422.us-central1.run.app"
_google_auth_transport = GoogleRequest()


def _verify_scheduler_token(request: Request) -> None:
    """Allow only Cloud Scheduler calls signed by the juno-scheduler service account."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = auth_header.removeprefix("Bearer ")
    try:
        claims = verify_oauth2_token(token, _google_auth_transport, audience=_CLOUD_RUN_AUDIENCE)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid OIDC token")
    if claims.get("email") != settings.SCHEDULER_SA_EMAIL:
        raise HTTPException(status_code=403, detail="Forbidden service account")


@app.post("/scheduler/tick")
async def scheduler_tick_endpoint(
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    result = await handle_scheduler_tick()
    return _lambda_response(result)


# Engagement endpoints (internal — Cloud Tasks only)
@app.post("/internal/engage/orchestrate")
async def engage_orchestrate_endpoint(
    request: Request,
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    body = await request.json()
    result = await handle_engagement_orchestrate(body)
    return JSONResponse(content=result)


@app.post("/internal/engage/notify")
async def engage_notify_endpoint(
    request: Request,
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    body = await request.json()
    result = await handle_engagement_notify(body)
    return JSONResponse(content=result)


# Daily notification endpoints (this is internal with Cloud Scheduler + Cloud Tasks only)
@app.post("/internal/daily-notify/plan-all")
async def daily_notify_plan_all_endpoint(
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    result = await handle_plan_all_users()
    return JSONResponse(content=result)


@app.post("/internal/daily-notify/plan/{user_id}")
async def daily_notify_plan_user_endpoint(
    user_id: str,
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    result = await handle_plan_one_user(user_id)
    return JSONResponse(content=result)


@app.post("/internal/daily-notify/send")
async def daily_notify_send_endpoint(
    request: Request,
    _: None = Depends(_verify_scheduler_token),
) -> JSONResponse:
    body = await request.json()
    result = await handle_send_nudge(body)
    return JSONResponse(content=result)


@app.post("/internal/engage/responded")
async def engage_responded_endpoint(request: Request) -> JSONResponse:
    claims = decode_firebase_claims(request.headers)
    if not claims:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    user_id: str = claims.get("uid") or claims.get("sub") or ""
    if not user_id:
        return JSONResponse({"error": "Unauthorized"}, status_code=401)
    body = await request.json()
    engagement_id: str = body.get("engagement_id", "")
    result = await handle_engagement_responded(user_id, engagement_id)
    status = 404 if result.get("error") == "not_found" else 200
    return JSONResponse(content=result, status_code=status)


@app.get("/connectors")
async def connectors_endpoint(request: Request) -> JSONResponse:
    return await get_connectors(request)


@app.post("/connectors/google-calendar/connect")
async def connectors_google_calendar_connect_endpoint(request: Request) -> JSONResponse:
    return await connect_google_calendar(request)


@app.post("/connectors/google-calendar/disconnect")
async def connectors_google_calendar_disconnect_endpoint(request: Request) -> JSONResponse:
    return await disconnect_google_calendar(request)


@app.post("/connectors/google-calendar/sync")
async def connectors_google_calendar_sync_endpoint(request: Request) -> JSONResponse:
    return await sync_google_calendar(request)


@app.post("/integrations/google-calendar/webhook", name="google_calendar_webhook")
async def google_calendar_webhook_endpoint(request: Request) -> JSONResponse:
    return await google_calendar_webhook(request)


def _check_env() -> None:
    """Log the status of every critical env var so you can spot missing config instantly."""
    checks = {
        "ANTHROPIC_API_KEY": bool(settings.ANTHROPIC_API_KEY),
        "ANTHROPIC_MODEL": settings.ANTHROPIC_MODEL,
        "AWS_REGION": bool(settings.AWS_REGION),
        "BEDROCK_MODEL": settings.BEDROCK_SONIC_MODEL_ID,
        "GOOGLE_CALENDAR": settings.google_calendar_configured,
        "GOOGLE_CALENDAR_WEBHOOK_URL": bool(settings.GOOGLE_CALENDAR_WEBHOOK_URL),
        "GEMINI_API_KEY": settings.gemini_configured,
        "GEMINI_MODEL": settings.GEMINI_MODEL,
        "ENV": settings.ENV,
    }

    # AWS credential sources (precedence order)
    aws_key = os.environ.get("AWS_ACCESS_KEY_ID", "")
    aws_role = os.environ.get("AWS_ROLE_ARN", "")
    aws_profile = os.environ.get("AWS_PROFILE", "")
    if aws_key:
        checks["AWS_CREDS"] = f"env key ...{aws_key[-4:]}"
    elif aws_role:
        checks["AWS_CREDS"] = f"role {aws_role}"
    elif aws_profile:
        checks["AWS_CREDS"] = f"profile {aws_profile}"
    else:
        checks["AWS_CREDS"] = "default chain (~/.aws)"

    logger.info("Juno backend starting", checks)

    # Warn on missing critical keys
    if not settings.ANTHROPIC_API_KEY:
        logger.warn("ANTHROPIC_API_KEY is not set — /chat will fail")
    if not aws_key and not aws_role and not aws_profile:
        logger.warn("No explicit AWS credentials found — Bedrock will use ~/.aws/credentials or IAM role")


@app.on_event("startup")
async def on_startup() -> None:
    _check_env()
    # Pre-warm Vertex AI / Gemini so the first nutrition scan doesn't stall the event loop during SDK initialisation 
    # (vertexai.init makes gRPC + metadata service calls that can take 1-5 s on a cold instance).
    try:
        await asyncio.to_thread(get_gemini_client)
        logger.info("Gemini client pre-warmed")
    except Exception as exc:
        logger.warn("Gemini client pre-warm failed — nutrition scan will init lazily", {
            "error": str(exc),
        })


# Lambda adapter
# Use `handler` as the Lambda function entrypoint for REST-only deployments.
# The WebSocket /voice/stream route must run on a persistent server.
handler = Mangum(app, lifespan="off")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.main:app",
        host=settings.VOICE_GATEWAY_HOST,
        port=settings.VOICE_GATEWAY_PORT,
        reload=settings.ENV == "development",
        log_level="info",
    )
