# ── Stage 1: Install dependencies ────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY src/ ./src/

RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir .

# ── Stage 2: Lean runtime image ───────────────────────────────────────────────
FROM python:3.12-slim AS runtime

WORKDIR /app

# Non-root user for security
RUN groupadd -r juno && useradd -r -g juno juno

# Pull installed packages + binaries from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy source (uvicorn resolves src.main:app from /app/src/)
COPY src/ ./src/

RUN chown -R juno:juno /app
USER juno

# Cloud Run injects $PORT at runtime (default 8080).
# VOICE_GATEWAY_PORT is the app-level setting — keep in sync.
ENV VOICE_GATEWAY_PORT=8080
EXPOSE 8080

# Use shell form so ${PORT} is expanded at container start
CMD uvicorn src.main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1
