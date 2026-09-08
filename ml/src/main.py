"""
Appwrite Function entrypoint for the Jaipur Safe Route API.

Runtime: python-ml (Debian-based, has scikit-learn/pandas/numpy preinstalled
correctly — the standard "python-3.x" runtime is Alpine-based and often
fails to build scipy/scikit-learn wheels).

Entrypoint: src/main.py
Build command: pip install -r requirements.txt

Deploy data/jaipur_segments_scored.csv and data/danger_model.pkl alongside
this file — they get bundled into the function's deployment and are loaded
once per warm container (module-level code below), not per-request. Cold
starts will pay the CSV/model load cost; warm invocations reuse it.

Call shape (matches the SwiftUI app's expected request/response):
  POST https://<region>.cloud.appwrite.io/v1/functions/<FUNCTION_ID>/executions
  Body (JSON string, since Appwrite passes the raw request body):
    {"start_lat": .., "start_lon": .., "end_lat": .., "end_lon": .., "modes": [...]}
"""

import os
import json
import joblib
import pandas as pd
import numpy as np
from scipy.spatial import cKDTree
import requests

# ---------------------------------------------------------------------------
# Module-level load — runs once when the container starts (warm reuse),
# not on every invocation. This is the pattern Appwrite's own docs
# recommend for ML functions.
# ---------------------------------------------------------------------------
_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

_segments = None
_segment_tree = None
_model = None
_GREEN_MAX = None
_YELLOW_MAX = None


def _ensure_loaded():
    global _segments, _segment_tree, _model, _GREEN_MAX, _YELLOW_MAX
    if _segments is not None:
        return  # already loaded in this warm container

    segments_path = os.path.join(_DATA_DIR, "jaipur_segments_scored.csv")
    model_path = os.path.join(_DATA_DIR, "danger_model.pkl")

    _segments = pd.read_csv(segments_path)
    _segment_tree = cKDTree(_segments[["mid_lat", "mid_lon"]].values)
    _model = joblib.load(model_path)  # loaded for future use; danger_score is precomputed

    _GREEN_MAX = float(_segments["danger_score"].quantile(0.33))
    _YELLOW_MAX = float(_segments["danger_score"].quantile(0.66))


TRAFFIC_CORRECTION = {"driving": 1.4, "cycling": 1.15, "walking": 1.0}
EXPOSURE_MULTIPLIER = {"walking": 1.5, "cycling": 1.15, "driving": 1.0}


def _get_osrm_routes_for_mode(start_lat, start_lon, end_lat, end_lon, mode):
    base = "https://routing.openstreetmap.de/routed-" + (
        "foot" if mode == "walking" else "bike" if mode == "cycling" else "car"
    )
    url = (
        f"{base}/route/v1/driving/"
        f"{start_lon},{start_lat};{end_lon},{end_lat}"
        f"?alternatives=true&overview=full&geometries=geojson"
    )
    resp = requests.get(url, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    if data.get("code") != "Ok":
        raise RuntimeError(f"OSRM error ({mode}): {data.get('message', data.get('code'))}")
    return data["routes"]


# The scored dataset only covers Jaipur. cKDTree.query() always returns the
# NEAREST point with no distance cap, so a route far outside Jaipur (e.g. a
# different city entirely) would silently get matched against whichever
# Jaipur segment happens to be geometrically closest, producing a
# meaningless score instead of an honest "not covered" error. ~0.05 degrees
# is roughly 5-6km at this latitude — generous enough to cover GPS/sampling
# noise at the edge of the dataset without accepting genuinely-elsewhere
# coordinates.
_MAX_COVERAGE_DEGREES = 0.05


def _score_route_with_mode(route_geometry, mode, sample_every_n=3):
    coords = route_geometry[::sample_every_n] or route_geometry
    lats = [c[1] for c in coords]
    lons = [c[0] for c in coords]
    dists, idxs = _segment_tree.query(np.c_[lats, lons])

    if float(np.max(dists)) > _MAX_COVERAGE_DEGREES:
        raise ValueError(
            "This route passes outside the area we have safety data for "
            "(Jaipur only). Safety scoring isn't available for this trip."
        )

    matched_scores = _segments.iloc[idxs]["danger_score"].values
    worst = float(matched_scores.max())
    adjusted_worst = min(worst * EXPOSURE_MULTIPLIER[mode], 1.0)
    return {
        "worst_score": worst,
        "adjusted_worst_score": adjusted_worst,
        "avg_score": float(matched_scores.mean()),
    }


def _classify_tier(adjusted_score):
    if adjusted_score <= _GREEN_MAX:
        return "green"
    elif adjusted_score <= _YELLOW_MAX:
        return "yellow"
    else:
        return "red"


def _get_safe_routes_multimodal(start_lat, start_lon, end_lat, end_lon, modes):
    results = {}
    for mode in modes:
        try:
            routes = _get_osrm_routes_for_mode(start_lat, start_lon, end_lat, end_lon, mode)
        except Exception as e:
            results[mode] = {"error": str(e)}
            continue

        scored_routes = []
        coverage_error = None
        for i, route in enumerate(routes):
            geometry = route["geometry"]["coordinates"]
            try:
                score = _score_route_with_mode(geometry, mode)
            except ValueError as e:
                # This specific route falls outside the scored dataset's
                # coverage area — skip it rather than fabricate a score,
                # but keep trying the other candidate routes for this mode.
                coverage_error = str(e)
                continue
            tier = _classify_tier(score["adjusted_worst_score"])
            realistic_duration = route["duration"] * TRAFFIC_CORRECTION[mode]

            scored_routes.append({
                "route_index": i,
                "geometry": geometry,
                "distance_m": route["distance"],
                "duration_s": realistic_duration,
                "worst_score": score["worst_score"],
                "adjusted_score": score["adjusted_worst_score"],
                "tier": tier,
            })

        if not scored_routes:
            results[mode] = {"error": coverage_error or "No routable path found for this mode."}
            continue

        best_per_tier = {}
        for tier in ["green", "yellow", "red"]:
            tier_routes = [r for r in scored_routes if r["tier"] == tier]
            if tier_routes:
                best_per_tier[tier] = min(tier_routes, key=lambda r: r["adjusted_score"])

        results[mode] = {"best_per_tier": best_per_tier}

    return results


# ---------------------------------------------------------------------------
# Appwrite entrypoint. Appwrite calls this function with (context) — context
# exposes .req (the incoming request) and .res (helpers to build a response).
# See: https://appwrite.io/docs/products/functions/develop
# ---------------------------------------------------------------------------
def main(context):
    _ensure_loaded()

    # Health check via GET (no body) — lets you verify deployment quickly
    if context.req.method == "GET":
        return context.res.json({
            "status": "ok",
            "segments_loaded": len(_segments),
        })

    try:
        body = context.req.body_json or {}
    except (json.JSONDecodeError, TypeError, AttributeError):
        return context.res.json({"error": "Invalid JSON body"}, 400)

    required = ["start_lat", "start_lon", "end_lat", "end_lon"]
    missing = [k for k in required if k not in body]
    if missing:
        return context.res.json({"error": f"Missing required fields: {missing}"}, 400)

    try:
        start_lat = float(body["start_lat"])
        start_lon = float(body["start_lon"])
        end_lat = float(body["end_lat"])
        end_lon = float(body["end_lon"])
    except (TypeError, ValueError):
        return context.res.json({"error": "lat/lon values must be numeric"}, 400)

    requested_modes = body.get("modes")
    if requested_modes:
        modes = tuple(m for m in requested_modes if m in TRAFFIC_CORRECTION)
        if not modes:
            return context.res.json({"error": "No valid modes requested"}, 400)
    else:
        modes = ("walking", "cycling", "driving")

    results = _get_safe_routes_multimodal(start_lat, start_lon, end_lat, end_lon, modes)

    return context.res.json({
        "start": {"lat": start_lat, "lon": start_lon},
        "end": {"lat": end_lat, "lon": end_lon},
        "modes": results,
        "tier_thresholds": {"green_max": _GREEN_MAX, "yellow_max": _YELLOW_MAX},
    })
