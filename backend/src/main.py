"""
Juno backend — FastAPI application.

Routes:
  GET  /health                  → liveness probe
  WebSocket /voice/stream       → real-time Nova Sonic voice session
  POST /chat                    → text conversation (Claude)
  POST /nutrition/analyze       → OCR nutrition analysis
  POST /notification-reply      → notification reply → chat
  POST /scheduler/tick          → deliver due reminders (call from cron)

Local dev:
  uvicorn src.main:app --reload --port 8000

Lambda (REST handlers only):
  from src.main import handler  # Mangum adapter
"""

from __future__ import annotations

import json
import os
import time
import uuid

from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse
from mangum import Mangum
from starlette.middleware.base import BaseHTTPMiddleware

from .config.settings import settings
from .handlers.chat import handle_chat_request
from .handlers.notification_reply import handle_notification_reply_request
from .handlers.nutrition import handle_nutrition_analyze_request
from .handlers.scheduler import handle_scheduler_tick
from .lib.logger import logger
from .voice_gateway.ws_handler import voice_stream_handler

app = FastAPI(title="Juno Backend", version="1.0.0")


# ─── Request / Response logging middleware ────────────────────────────────────

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


# ─── Health ──────────────────────────────────────────────────────────────────

@app.get("/health")
async def health() -> dict[str, bool]:
    return {"ok": True}


# ─── Voice Gateway ───────────────────────────────────────────────────────────

@app.websocket("/voice/stream")
async def voice_stream(ws: WebSocket) -> None:
    await voice_stream_handler(ws)


# ─── REST endpoints ──────────────────────────────────────────────────────────

def _to_lambda_event(request: Request, body: bytes) -> dict:
    """Convert FastAPI Request into a Lambda-style event dict."""
    return {
        "body": body.decode("utf-8"),
        "requestContext": {
            "authorizer": {
                "jwt": {
                    "claims": {
                        # API Gateway JWT claims land here; populated by middleware
                        # when deployed behind API Gateway with Cognito/JWT authorizer.
                        # For direct FastAPI use, auth is handled in each handler.
                    }
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


@app.post("/chat")
async def chat_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_chat_request(event)
    return _lambda_response(result)


@app.post("/nutrition/analyze")
async def nutrition_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_nutrition_analyze_request(event)
    return _lambda_response(result)


@app.post("/notification-reply")
async def notification_reply_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_notification_reply_request(event)
    return _lambda_response(result)


@app.post("/scheduler/tick")
async def scheduler_tick_endpoint() -> JSONResponse:
    result = await handle_scheduler_tick()
    return _lambda_response(result)


# ─── Startup ─────────────────────────────────────────────────────────────────

def _check_env() -> None:
    """Log the status of every critical env var so you can spot missing config instantly."""
    checks = {
        "ANTHROPIC_API_KEY": bool(settings.ANTHROPIC_API_KEY),
        "AWS_REGION": bool(settings.AWS_REGION),
        "BEDROCK_MODEL": settings.BEDROCK_SONIC_MODEL_ID,
        "GOOGLE_CALENDAR": settings.google_calendar_configured,
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


# ─── Lambda adapter ───────────────────────────────────────────────────────────
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
