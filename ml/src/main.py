"""
Jaipur Safe Route — ML scoring engine (v2)

ARCHITECTURE CHANGE FROM v1: this file is now a self-contained FastAPI app
(defines `app` directly) rather than an Appwrite Function entrypoint
(`def main(context)`). Run it directly:
    cd ml
    .venv/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload
local_server.py (the old thin FastAPI wrapper around the Appwrite-style
entrypoint) is now superseded/obsolete — see local_server.py's own header.

CHANGES FROM v1:
- lighting_risk (dead constant) -> lighting_risk_for_danger (real, road-type derived)
- crime_risk (dead constant) -> real NCRB 2001-2005 data, applied as a citywide
  multiplier on top of the model output (NOT a per-segment ML input — see note below)
- Score direction INVERTED: danger_score (0-1, high=dangerous) -> safety_score
  (0-100, high=SAFE). Every comparison below is safety-direction, not danger-direction.
- Route aggregation: MAX(danger) -> MIN(safety) along sampled route points
  (same worst-case principle, just inverted along with the score direction)
- Tier thresholds: now >=70 green / >=35 yellow on a CALIBRATED score (see
  calibrate_to_city). The earlier fixed >75/25-75/<25 cut-offs were applied to
  the model's raw output, whose real range is only ~23-85 with a ~40 median —
  so under 0.5% of Jaipur could ever read "Safer" and ~79% collapsed into a
  single undifferentiated "yellow" band. Scores are now percentile ranks
  against ~357k real segments, so the thresholds mean "top 30% / middle /
  bottom 35% of Jaipur streets".
- Route selection: v1 returned best-per-tier (1 green+1 yellow+1 red). v2 returns
  TOP 3 SAFEST overall, ranked — could all be the same tier, that's expected.
- model.predict() IS NOW CALLED LIVE per request. v1 loaded the pickle but read
  danger_score straight from the CSV without ever invoking the model — that's
  fixed here. The CSV's safety_score column still exists and is used ONLY as a
  fallback if live prediction fails (e.g. malformed feature row), not as the
  primary path.

KNOWN LIMITATIONS (unchanged from v1's honest disclosure, still true):
- Crime data is NCRB 2001-2005, city-wide only, not neighborhood-level
- Only 16 police stations found in OSM data for Jaipur (likely an undercount)
- lighting_risk_for_danger and road_type_risk are real but modest contributors
  (single-digit % feature importance) — police_risk dominates the scoring,
  which is a genuine data finding, not an oversight
- Scores are RELATIVE (a percentile rank against other Jaipur streets), not an
  absolute measure of danger. "80" means "safer than 80% of Jaipur's mapped
  streets", NOT "80% safe" — in a city with generally poor scores, a high
  percentile is still only a comparison against that same city.
- OSRM won't always return 3 alternatives for short/direct trips
- No ground-truth validation exists (unchanged gap from v1) — surfaced in the
  API response's disclosed_limitations and should stay visible wherever the
  app shows its Beta badge / provenance labeling.

MODEL VERSION NOTE: danger_model_v2.pkl was pickled with scikit-learn 1.6.1;
this environment has 1.9.0 installed (`pip show scikit-learn`). Loading logs a
version-mismatch warning per internal DecisionTreeRegressor (the RandomForest
contains many). This has been verified to load successfully and expose the
expected 4 features in the expected order (see MODEL_FEATURE_COLS) — the
mismatch is the same class of issue v1 had and remains harmless for this
tree-based model's pickle format, but if results ever look suspicious,
re-pickle with a matching scikit-learn version rather than assuming it's fine.
"""

import os
import warnings
import joblib
import pandas as pd
import numpy as np
from scipy.spatial import cKDTree
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import requests

app = FastAPI(title="Jaipur Safe Route ML Engine v2")

# ---------------------------------------------------------------------------
# Load model + segments ONCE at startup (module-level, not per-request)
# ---------------------------------------------------------------------------
DATA_DIR = os.environ.get("DATA_DIR", os.path.join(os.path.dirname(__file__), "..", "data"))
SEGMENTS_PATH = os.path.join(DATA_DIR, "jaipur_segments_safety_final.csv")
MODEL_PATH = os.path.join(DATA_DIR, "danger_model_v2.pkl")
REFERENCE_QUANTILES_PATH = os.path.join(DATA_DIR, "safety_reference_quantiles.npy")

print(f"Loading segments from {SEGMENTS_PATH} ...")
segments = pd.read_csv(SEGMENTS_PATH, low_memory=False)
print(f"  {len(segments)} segments loaded")

segment_tree = cKDTree(segments[["mid_lat", "mid_lon"]].values)

print(f"Loading model from {MODEL_PATH} ...")
with warnings.catch_warnings(record=True) as w:
    warnings.simplefilter("always")
    model = joblib.load(MODEL_PATH)
    version_warnings = [str(warning.message) for warning in w]
    if version_warnings:
        print(f"  [model load] {len(version_warnings)} scikit-learn version-mismatch "
              f"warning(s) — pickled with an older sklearn than this environment's. "
              f"See this file's module docstring ('MODEL VERSION NOTE') for context.")

# Reference distribution of raw safety scores across ALL segments, used to
# rescale a raw score to a citywide percentile (see calibrate_to_city).
# Regenerate with scripts/build_reference_quantiles.py whenever the model or
# segment data changes — a stale curve would silently mis-rank every score.
SAFETY_REFERENCE_QUANTILES = np.load(REFERENCE_QUANTILES_PATH)
print(f"  reference curve loaded (raw range "
      f"{SAFETY_REFERENCE_QUANTILES[0]:.1f}-{SAFETY_REFERENCE_QUANTILES[-1]:.1f})")

# The 4 independent features the model was actually trained on — must match
# training exactly, in this order, or predict() will silently misinterpret columns.
MODEL_FEATURE_COLS = ["road_type_risk", "lighting_risk_for_danger", "police_risk", "footfall_risk"]

missing_cols = [c for c in MODEL_FEATURE_COLS if c not in segments.columns]
if missing_cols:
    raise RuntimeError(
        f"segments CSV is missing required model feature columns: {missing_cols}. "
        f"This means the wrong CSV is loaded, or the v2 pipeline wasn't fully re-run."
    )

# Citywide crime multiplier — applied AFTER model prediction, not as a model
# input. This was a deliberate design decision: every per-segment crime proxy
# tested during development correlated too strongly with police_risk/footfall_risk
# to count as independent signal, so real NCRB data is applied honestly as a
# citywide adjustment instead of fabricated per-segment precision.
CRIME_SEVERITY_MULTIPLIER = float(os.environ.get("CRIME_SEVERITY_MULTIPLIER", 1.0523))

# Coverage guard — unchanged from v1's honest design. Without this, a route
# from outside Jaipur would silently snap to the nearest Jaipur segment and
# produce a meaningless score instead of an honest error.
MAX_COVERAGE_DEGREES = 0.05  # ~5-6km

# ---------------------------------------------------------------------------
# Live model scoring
# ---------------------------------------------------------------------------
def predict_danger_for_segments(segment_rows: pd.DataFrame) -> np.ndarray:
    """
    Calls model.predict() LIVE on the given segment rows' features, then
    applies the citywide crime multiplier. Falls back to the precomputed
    danger_score column only if live prediction throws (should be rare —
    logged loudly if it happens, not silently swallowed).
    """
    try:
        X = segment_rows[MODEL_FEATURE_COLS]
        raw_danger = model.predict(X)
        danger = np.clip(raw_danger * CRIME_SEVERITY_MULTIPLIER, 0, 1)
        return danger
    except Exception as e:
        print(f"  [WARNING] Live model.predict() failed ({e}) — falling back to "
              f"precomputed danger_score column for this batch. This should be rare; "
              f"investigate if it happens often.")
        return segment_rows["danger_score"].values


def danger_to_safety(danger_scores: np.ndarray) -> np.ndarray:
    """0-1 danger (high=bad) -> 0-100 safety (high=good), then rescaled to a
    citywide percentile rank (see calibrate_to_city below)."""
    raw = np.clip(100 * (1 - danger_scores), 0, 100)
    return calibrate_to_city(raw)


def calibrate_to_city(raw_safety: np.ndarray) -> np.ndarray:
    """
    Rescale a raw safety score to its percentile rank against the real
    distribution of all 368k scored Jaipur segments.

    WHY: the model's raw output only spans ~17-85 (median ~39), because
    real Jaipur streets don't vary across the theoretical full range.
    Read on a raw 0-100 scale that made almost everywhere look mid-to-low
    risk, and with green>75 only 0.4% of the city could EVER show as
    "Safer" while 79% collapsed into one undifferentiated "yellow" blob —
    the score carried almost no comparative information.

    After rescaling, a score means something precise and checkable:
    "safer than N% of Jaipur's mapped streets". This is a change of SCALE,
    not of judgement — the ranking of any two streets is identical before
    and after. It is explicitly NOT a flat bonus added to make numbers look
    better; that would decouple the score from reality and make a genuinely
    risky street read as safe.
    """
    return np.interp(raw_safety, SAFETY_REFERENCE_QUANTILES,
                     np.linspace(0, 100, len(SAFETY_REFERENCE_QUANTILES)))


# Tier thresholds, derived from the calibrated (percentile) scale rather than
# guessed. On a percentile scale these read directly as "top 30% of Jaipur
# streets", "middle 35%", "bottom 35%" — which is why they're defensible in a
# way the old fixed 75/25 cut-offs on a compressed raw scale were not.
GREEN_MIN = 70
YELLOW_MIN = 35


def classify_tier(safety_score: float) -> str:
    if safety_score >= GREEN_MIN:
        return "green"
    elif safety_score >= YELLOW_MIN:
        return "yellow"
    else:
        return "red"


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------
TRAFFIC_CORRECTION = {"driving": 1.4, "cycling": 1.15, "walking": 1.0}
EXPOSURE_MULTIPLIER = {"walking": 1.5, "cycling": 1.15, "driving": 1.0}


def get_osrm_routes(start_lat, start_lon, end_lat, end_lon, mode="driving"):
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


def check_coverage(lat, lon):
    """Raise an honest error if a point is too far from any known Jaipur
    segment, rather than silently matching to the nearest one regardless
    of distance."""
    dist, _ = segment_tree.query([lat, lon])
    if dist > MAX_COVERAGE_DEGREES:
        raise HTTPException(
            status_code=422,
            detail=f"Location ({lat}, {lon}) is outside the Jaipur coverage area "
                   f"this model was trained on. Safety scoring isn't available here."
        )


def score_route(route_geometry, mode: str, sample_every_n: int = 3) -> dict:
    coords = route_geometry[::sample_every_n] or route_geometry
    lats = [c[1] for c in coords]
    lons = [c[0] for c in coords]

    _, idxs = segment_tree.query(np.c_[lats, lons])
    matched_rows = segments.iloc[idxs]

    danger_scores = predict_danger_for_segments(matched_rows)
    safety_scores = danger_to_safety(danger_scores)

    # Worst-case: the LOWEST safety segment on the route drags the route's
    # rating down — same worst-case principle as v1's MAX(danger), just
    # inverted for the safety-score direction.
    worst_safety = float(safety_scores.min())
    avg_safety = float(safety_scores.mean())

    # NOTE: the old code returned worst_safety / EXPOSURE_MULTIPLIER here
    # (walking 1.5, cycling 1.15, driving 1.0). That was defensible when the
    # score was a raw 0-100 danger inversion, but scores are now percentile
    # ranks against the city (see calibrate_to_city) — and dividing a
    # percentile by 1.5 has no meaning. It also produced visibly incoherent
    # output: a route whose worst segment ranked 99.9 reported an overall
    # score of 66.6, i.e. "worse than its own worst part".
    #
    # Travel mode genuinely does change how exposed someone is, so it is still
    # reported — as its own honest field, not by silently deflating the score.
    return {
        "worst_safety": worst_safety,
        "adjusted_safety": worst_safety,
        "avg_safety": avg_safety,
        "exposure_multiplier": EXPOSURE_MULTIPLIER.get(mode, 1.0),
    }


def get_top3_safest_routes(start_lat, start_lon, end_lat, end_lon, mode="driving"):
    check_coverage(start_lat, start_lon)
    check_coverage(end_lat, end_lon)

    routes = get_osrm_routes(start_lat, start_lon, end_lat, end_lon, mode)

    scored = []
    for i, route in enumerate(routes):
        geometry = route["geometry"]["coordinates"]
        score = score_route(geometry, mode)
        tier = classify_tier(score["adjusted_safety"])
        scored.append({
            "route_index": i,
            "geometry": geometry,
            "distance_m": route["distance"],
            "duration_s": route["duration"] * TRAFFIC_CORRECTION.get(mode, 1.0),
            "safety_score": round(score["adjusted_safety"], 1),
            "tier": tier,
        })

    # Rank by safety descending — highest safety first. Returns up to 3;
    # if OSRM found fewer alternatives, returns however many exist rather
    # than padding or erroring (a known, disclosed OSRM limitation, not a bug).
    ranked = sorted(scored, key=lambda r: r["safety_score"], reverse=True)
    top3 = ranked[:3]
    labels = {1: "Safest", 2: "Second safest", 3: "Third safest"}
    for rank, r in enumerate(top3, start=1):
        r["rank"] = rank
        r["label"] = labels[rank]

    return top3


TIER_COLORS = {"green": "#2ecc71", "yellow": "#f1c40f", "red": "#e74c3c"}


def format_route_for_response(r: dict) -> dict:
    return {
        "rank": r["rank"],
        "label": r["label"],
        "tier": r["tier"],
        "color": TIER_COLORS[r["tier"]],
        "safety_score": r["safety_score"],
        "distance_km": round(r["distance_m"] / 1000, 2),
        "duration_min": round(r["duration_s"] / 60, 1),
        "geometry": r["geometry"],
    }


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
class SafeRouteRequest(BaseModel):
    start_lat: float
    start_lon: float
    end_lat: float
    end_lon: float
    modes: list[str] = ["walking", "cycling", "driving"]


@app.post("/safe-routes")
def safe_routes(req: SafeRouteRequest):
    valid_modes = [m for m in req.modes if m in TRAFFIC_CORRECTION]
    if not valid_modes:
        raise HTTPException(status_code=400, detail="No valid modes requested")

    results = {}
    for mode in valid_modes:
        try:
            top3 = get_top3_safest_routes(
                req.start_lat, req.start_lon, req.end_lat, req.end_lon, mode
            )
            results[mode] = {"routes": [format_route_for_response(r) for r in top3]}
        except HTTPException:
            raise
        except Exception as e:
            results[mode] = {"error": str(e)}

    return {
        "start": {"lat": req.start_lat, "lon": req.start_lon},
        "end": {"lat": req.end_lat, "lon": req.end_lon},
        "modes": results,
        "tier_thresholds": {"green_min": GREEN_MIN, "yellow_min": YELLOW_MIN},
        "model_version": "v2",
        "disclosed_limitations": [
            "Crime data: NCRB 2001-2005, citywide only, not neighborhood-level",
            "Only 16 police stations found in Jaipur OSM data (likely undercount)",
            "police_risk dominates scoring; lighting/road-type are modest contributors",
            "Score is a percentile rank vs ~357k Jaipur street segments, not an absolute safety rating",
        ],
    }


def build_factor_breakdown(row) -> list:
    """
    The individual factors behind a location's score, each with the REAL
    underlying measurement (not just the model's internal 0-1 risk value)
    so the app can show a user why a street scored the way it did.

    `risk` is the model's own 0-1 input (1 = worst); `detail` is the real
    measured quantity it came from. Ordered by how much each actually moves
    the score — police proximity dominates, which is a genuine finding from
    feature importance, not a display choice.

    Crime is listed last and marked differently on purpose: it is NOT a
    per-segment model input. It's a single citywide NCRB multiplier applied
    after prediction, so it is identical everywhere in Jaipur and explains
    nothing about why one street differs from another. Labelling it as a
    per-street factor would be a lie.
    """
    def f(v, default=None):
        try:
            out = float(v)
            return None if pd.isna(out) else out
        except (TypeError, ValueError):
            return default

    police_km = f(row.get("police_dist_km"))
    footfall = f(row.get("footfall_count"))
    lighting = f(row.get("lighting_score"))
    road_type = row.get("highway")
    if isinstance(road_type, str):
        road_type = road_type.replace("_", " ").title()

    factors = [
        {
            "key": "police_proximity",
            "label": "Police station proximity",
            "risk": round(f(row.get("police_risk"), 0.0), 3),
            "detail": (f"Nearest station ~{police_km:.1f} km away"
                       if police_km is not None else "No station distance available"),
        },
        {
            "key": "crowd",
            "label": "Shops & activity nearby",
            "risk": round(f(row.get("footfall_risk"), 0.0), 3),
            "detail": (f"{int(footfall)} shops/venues mapped nearby"
                       if footfall is not None else "No footfall data available"),
        },
        {
            "key": "road_condition",
            "label": "Road type",
            "risk": round(f(row.get("road_type_risk"), 0.0), 3),
            "detail": road_type if road_type else "Unknown road type",
        },
        {
            "key": "lighting",
            "label": "Street lighting",
            "risk": round(f(row.get("lighting_risk_for_danger"), 0.0), 3),
            "detail": (f"Lighting score {lighting:.2f} (inferred from road type, "
                       f"not surveyed lamp data)"
                       if lighting is not None else "Inferred from road type"),
        },
        {
            "key": "crime",
            "label": "Crime level (citywide)",
            "risk": None,
            "citywide": True,
            "detail": (f"NCRB citywide factor ×{CRIME_SEVERITY_MULTIPLIER:.4f} — "
                       f"applied equally across all of Jaipur, so it does not "
                       f"differentiate this street from any other"),
        },
    ]
    return factors


class ScoreRouteRequest(BaseModel):
    # [[lon, lat], ...] — same ordering as GeoJSON and as /safe-routes geometry.
    coordinates: list[list[float]]
    mode: str = "walking"


@app.post("/score-route")
def score_route_endpoint(req: ScoreRouteRequest):
    """
    Scores a route the CLIENT already has (e.g. one MapKit produced for an
    active journey), rather than generating routes like /safe-routes does.

    This exists so the app's journey/navigation screens can show a real
    model-derived route score. They previously used an on-device heuristic
    (`JourneyService.routeSafetyScore`) that started from a hardcoded 78 and
    added/subtracted invented point values — a number that looked precise but
    measured nothing. Same model, same worst-case aggregation as /safe-routes,
    so a route score means the same thing everywhere in the app.
    """
    coords = [c for c in req.coordinates if isinstance(c, list) and len(c) >= 2]
    if len(coords) < 2:
        raise HTTPException(status_code=422,
                            detail="A route needs at least 2 coordinates.")

    # Coverage is checked on the endpoints only: a route may legitimately pass
    # through a gap in the segment data without being outside Jaipur.
    check_coverage(coords[0][1], coords[0][0])
    check_coverage(coords[-1][1], coords[-1][0])

    scored = score_route(coords, req.mode)
    safety = scored["adjusted_safety"]
    tier = classify_tier(safety)
    return {
        "safety_score": round(safety, 1),
        "worst_segment_score": round(scored["worst_safety"], 1),
        "average_score": round(scored["avg_safety"], 1),
        "tier": tier,
        "color": TIER_COLORS[tier],
        "tier_thresholds": {"green_min": GREEN_MIN, "yellow_min": YELLOW_MIN},
        "model_version": "v2",
        "disclosed_limitations": [
            "Score is the WORST segment on the route, not an average — one bad "
            "stretch legitimately drags the whole route down",
            "Score is a percentile rank vs ~357k Jaipur street segments, not an "
            "absolute safety rating",
            "Reflects mapped street attributes, not live conditions",
        ],
    }


class LocationSafetyRequest(BaseModel):
    lat: float
    lon: float


@app.post("/location-safety")
def location_safety(req: LocationSafetyRequest):
    """
    Scores the user's CURRENT position (not a route) using the exact same
    model/feature pipeline as /safe-routes — the nearest scored segment to
    (lat, lon), same live model.predict() call, same coverage guard. This
    backs the app's Safety Score screen showing "how safe is where you are
    right now" as a distinct, ML-sourced number alongside (not merged into)
    the on-device SafetyEngine's confidence score, which measures different
    things (route deviation, connectivity, time of day) and isn't itself
    location-safety data.
    """
    check_coverage(req.lat, req.lon)

    dist, idx = segment_tree.query([req.lat, req.lon])
    matched_row = segments.iloc[[idx]]

    danger = predict_danger_for_segments(matched_row)
    safety_score = float(danger_to_safety(danger)[0])
    tier = classify_tier(safety_score)

    return {
        "lat": req.lat,
        "lon": req.lon,
        "safety_score": round(safety_score, 1),
        "tier": tier,
        "color": TIER_COLORS[tier],
        "matched_segment_distance_m": round(dist * 111_000, 0),  # rough deg->m at this latitude
        "factors": build_factor_breakdown(matched_row.iloc[0]),
        "tier_thresholds": {"green_min": GREEN_MIN, "yellow_min": YELLOW_MIN},
        "model_version": "v2",
        "disclosed_limitations": [
            "Crime data: NCRB 2001-2005, citywide only, not neighborhood-level",
            "Only 16 police stations found in Jaipur OSM data (likely undercount)",
            "police_risk dominates scoring; lighting/road-type are modest contributors",
            "Score is a percentile rank vs ~357k Jaipur street segments, not an absolute safety rating",
            "Score reflects the nearest scored street segment, not a live sensor reading",
        ],
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "segments_loaded": len(segments),
        "model_features": MODEL_FEATURE_COLS,
        "crime_multiplier": CRIME_SEVERITY_MULTIPLIER,
    }
