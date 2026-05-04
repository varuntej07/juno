"""
Fetches job listings from free sources: Remotive API and Adzuna free tier.
No API key needed for Remotive. Adzuna requires a free account (app_id + app_key).
Used by HuntMode.
"""

from __future__ import annotations

import httpx

from ...config.settings import settings
from ...lib.logger import logger

REMOTIVE_URL = "https://remotive.com/api/remote-jobs"


async def fetch_remotive_jobs(
    search: str = "machine learning",
    limit: int = 10,
) -> list[dict]:
    """Fetches remote jobs from Remotive. Free, no auth required."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                REMOTIVE_URL,
                params={"search": search, "limit": limit},
            )
            r.raise_for_status()
            jobs = r.json().get("jobs", [])
            return [
                {
                    "title": j.get("title", ""),
                    "company": j.get("company_name", ""),
                    "location": j.get("candidate_required_location", "Remote"),
                    "url": j.get("url", ""),
                    "tags": j.get("tags", []),
                    "source": "remotive",
                }
                for j in jobs
                if j.get("title")
            ]
    except Exception as e:
        logger.error("Jobs: Remotive fetch failed", {"error": str(e), "search": search})
        return []


async def fetch_adzuna_jobs(
    what: str = "machine learning engineer",
    where: str = "us",
    limit: int = 10,
) -> list[dict]:
    """
    Fetches jobs from Adzuna. Requires ADZUNA_APP_ID and ADZUNA_APP_KEY in settings.
    Returns empty list gracefully if credentials are missing.
    """
    app_id = getattr(settings, "ADZUNA_APP_ID", None)
    app_key = getattr(settings, "ADZUNA_APP_KEY", None)
    if not app_id or not app_key:
        logger.info("Jobs: Adzuna credentials not configured, skipping")
        return []

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(
                f"https://api.adzuna.com/v1/api/jobs/{where}/search/1",
                params={
                    "app_id": app_id,
                    "app_key": app_key,
                    "what": what,
                    "results_per_page": limit,
                    "content-type": "application/json",
                },
            )
            r.raise_for_status()
            results = r.json().get("results", [])
            return [
                {
                    "title": j.get("title", ""),
                    "company": j.get("company", {}).get("display_name", ""),
                    "location": j.get("location", {}).get("display_name", ""),
                    "url": j.get("redirect_url", ""),
                    "description": j.get("description", "")[:300],
                    "source": "adzuna",
                }
                for j in results
                if j.get("title")
            ]
    except Exception as e:
        logger.error("Jobs: Adzuna fetch failed", {"error": str(e)})
        return []
