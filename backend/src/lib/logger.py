import logging
import sys
from typing import Any


def _build_logger() -> logging.Logger:
    logger = logging.getLogger("juno")
    if logger.handlers:
        return logger

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter(
            fmt="%(asctime)s  %(levelname)-8s  %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger


_logger = _build_logger()


def _fmt(message: str, metadata: dict[str, Any] | None) -> str:
    if not metadata:
        return message
    pairs = "  ".join(f"{k}={v!r}" for k, v in metadata.items())
    return f"{message}  {pairs}"


class Logger:
    def info(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _logger.info(_fmt(message, metadata))

    def warn(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _logger.warning(_fmt(message, metadata))

    def error(self, message: str, metadata: dict[str, Any] | None = None) -> None:
        _logger.error(_fmt(message, metadata))


logger = Logger()
