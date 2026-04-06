"""
Structured logger for Juno backend.

Every log line is emitted as:
  TIMESTAMP  LEVEL     MESSAGE  key='value'  key2='value2'

Errors logged via logger.exception() automatically append the full traceback.

Control verbosity with the LOG_LEVEL environment variable (default: DEBUG).
  LOG_LEVEL=DEBUG   → all messages
  LOG_LEVEL=INFO    → info / warn / error
  LOG_LEVEL=ERROR   → errors only
"""

from __future__ import annotations

import logging
import os
import sys
import traceback
from datetime import datetime, timezone
from typing import Any


def _resolve_level() -> int:
    name = os.environ.get("LOG_LEVEL", "DEBUG").upper()
    return getattr(logging, name, logging.DEBUG)


def _build_stdlib_logger() -> logging.Logger:
    lg = logging.getLogger("juno")
    if lg.handlers:
        return lg
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    handler.setFormatter(logging.Formatter("%(message)s"))
    lg.addHandler(handler)
    lg.propagate = False  # Don't double-emit through root logger
    lg.setLevel(_resolve_level())
    return lg


_stdlib = _build_stdlib_logger()


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _emit(level: str, message: str, metadata: dict[str, Any] | None, include_traceback: bool) -> None:
    log_level = getattr(logging, level, logging.DEBUG)
    if not _stdlib.isEnabledFor(log_level):
        return

    extras = ""
    if metadata:
        extras = "  " + "  ".join(f"{k}={v!r}" for k, v in metadata.items())

    _stdlib.log(log_level, f"{_now()}  {level:<5}  {message}{extras}")

    if include_traceback:
        tb = traceback.format_exc()
        if tb and tb.strip() != "NoneType: None":
            _stdlib.log(log_level, tb)


class Logger:
    """Thin structured logger. Use .exception() inside except blocks for full tracebacks."""

    def debug(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _emit("DEBUG", message, metadata, False)

    def info(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _emit("INFO", message, metadata, False)

    def warn(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _emit("WARN", message, metadata, False)

    def error(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _emit("ERROR", message, metadata, False)

    def exception(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        """Call from inside an except block — captures and prints the full traceback."""
        _emit("ERROR", message, metadata, True)


logger = Logger()
