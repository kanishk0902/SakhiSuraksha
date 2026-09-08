"""
Local dev server for the Jaipur Safe Route API.

Wraps the exact same scoring/routing logic in main.py (unchanged) with a
FastAPI app so it can run directly on this Mac instead of as an Appwrite
Cloud Function. main.py's core functions (_ensure_loaded,
_get_safe_routes_multimodal, etc.) are imported as-is — nothing about the
scoring, tier thresholds, or OSRM routing was touched.

Run:
    cd ml
    .venv/bin/uvicorn src.local_server:app --host 0.0.0.0 --port 8000 --reload

The iOS Simulator reaches this via http://localhost:8000. A physical
iPhone on the same Wi-Fi network reaches it via http://<your-Mac-LAN-IP>:8000
(see README.txt for how to find that IP and why --host 0.0.0.0 matters).
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import main as backend  # main.py, unmodified

app = FastAPI(title="Jaipur Safe Route API (local dev)")


@app.on_event("startup")
def _load_on_startup():
    # Load once at process startup rather than on first request, so the
    # first real request isn't slow.
    backend._ensure_loaded()


@app.get("/")
@app.get("/safe-routes")
def health():
    backend._ensure_loaded()
    return {
        "status": "ok",
        "segments_loaded": len(backend._segments),
        "tier_thresholds": {
            "green_max": backend._GREEN_MAX,
            "yellow_max": backend._YELLOW_MAX,
        },
    }


@app.post("/safe-routes")
async def safe_routes(request: Request):
    backend._ensure_loaded()

    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    required = ["start_lat", "start_lon", "end_lat", "end_lon"]
    missing = [k for k in required if k not in body]
    if missing:
        return JSONResponse({"error": f"Missing required fields: {missing}"}, status_code=400)

    try:
        start_lat = float(body["start_lat"])
        start_lon = float(body["start_lon"])
        end_lat = float(body["end_lat"])
        end_lon = float(body["end_lon"])
    except (TypeError, ValueError):
        return JSONResponse({"error": "lat/lon values must be numeric"}, status_code=400)

    requested_modes = body.get("modes")
    if requested_modes:
        modes = tuple(m for m in requested_modes if m in backend.TRAFFIC_CORRECTION)
        if not modes:
            return JSONResponse({"error": "No valid modes requested"}, status_code=400)
    else:
        modes = ("walking", "cycling", "driving")

    results = backend._get_safe_routes_multimodal(start_lat, start_lon, end_lat, end_lon, modes)

    return {
        "start": {"lat": start_lat, "lon": start_lon},
        "end": {"lat": end_lat, "lon": end_lon},
        "modes": results,
        "tier_thresholds": {
            "green_max": backend._GREEN_MAX,
            "yellow_max": backend._YELLOW_MAX,
        },
    }
