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

from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse
from mangum import Mangum

from .config.settings import settings
from .handlers.chat import handle_chat_request
from .handlers.notification_reply import handle_notification_reply_request
from .handlers.nutrition import handle_nutrition_analyze_request
from .handlers.scheduler import handle_scheduler_tick
from .lib.logger import logger
from .voice_gateway.ws_handler import voice_stream_handler

app = FastAPI(title="Juno Backend", version="1.0.0")


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


@app.post("/chat")
async def chat_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_chat_request(event)
    return JSONResponse(content=result["body"], status_code=result["statusCode"],
                        media_type="application/json")


@app.post("/nutrition/analyze")
async def nutrition_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_nutrition_analyze_request(event)
    return JSONResponse(content=result["body"], status_code=result["statusCode"],
                        media_type="application/json")


@app.post("/notification-reply")
async def notification_reply_endpoint(request: Request) -> JSONResponse:
    body = await request.body()
    event = _to_lambda_event(request, body)
    result = await handle_notification_reply_request(event)
    return JSONResponse(content=result["body"], status_code=result["statusCode"],
                        media_type="application/json")


@app.post("/scheduler/tick")
async def scheduler_tick_endpoint() -> JSONResponse:
    result = await handle_scheduler_tick()
    return JSONResponse(content=result["body"], status_code=result["statusCode"],
                        media_type="application/json")


# ─── Startup / shutdown ───────────────────────────────────────────────────────

@app.on_event("startup")
async def on_startup() -> None:
    logger.info("Juno backend starting", {
        "env": settings.ENV,
        "host": settings.VOICE_GATEWAY_HOST,
        "port": settings.VOICE_GATEWAY_PORT,
    })


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
