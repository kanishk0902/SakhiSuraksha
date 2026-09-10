"""
Rebuilds data/safety_reference_quantiles.npy — the reference curve used to
rescale raw model scores into citywide percentile ranks (see calibrate_to_city
in src/main.py).

Run this whenever danger_model_v2.pkl or the segments CSV changes. A stale
curve doesn't error; it silently mis-ranks every score, so don't skip it.

    python scripts/build_reference_quantiles.py
"""
import os
import warnings

import joblib
import numpy as np
import pandas as pd

warnings.filterwarnings("ignore")

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")
FEATURES = ["road_type_risk", "lighting_risk_for_danger", "police_risk", "footfall_risk"]
CRIME_MULTIPLIER = float(os.environ.get("CRIME_SEVERITY_MULTIPLIER", 1.0523))

segments = pd.read_csv(os.path.join(DATA_DIR, "jaipur_segments_safety_final.csv"),
                       low_memory=False)
model = joblib.load(os.path.join(DATA_DIR, "danger_model_v2.pkl"))

danger = np.clip(model.predict(segments[FEATURES]) * CRIME_MULTIPLIER, 0, 1)
segments["raw_safety"] = 100 * (1 - danger)

# Build the reference from every road type EXCEPT "unclassified".
#
# WHY exclude it: those 11k rows are degenerate — p25, p50 and p75 are all
# 17.2, i.e. the model returns a near-constant floor for them, which reads as
# missing/unusable road attributes rather than a real finding that they are
# uniformly the most dangerous roads in Jaipur. Leaving them in drags the low
# end of the reference down and inflates everything else's percentile.
#
# WHY NOT rank each road type against only its own kind: that was tested and
# forces every road type to average exactly 50, erasing the model's genuine
# finding that trunk/primary roads really are safer than back lanes. Ranking
# against one shared reference keeps that real variation visible
# (trunk ~80, primary ~73, residential ~47).
reference_pool = segments.loc[segments["highway"] != "unclassified", "raw_safety"]

# 1001 points = 0.1-percentile resolution; plenty for interpolation, and small
# enough to load instantly at server startup.
quantiles = np.percentile(reference_pool, np.linspace(0, 100, 1001))
np.save(os.path.join(DATA_DIR, "safety_reference_quantiles.npy"), quantiles)

print(f"Built reference curve from {len(reference_pool)} segments "
      f"({len(segments) - len(reference_pool)} 'unclassified' excluded)")
print(f"  raw min    {quantiles[0]:.2f}")
print(f"  raw median {quantiles[500]:.2f}")
print(f"  raw max    {quantiles[-1]:.2f}")
