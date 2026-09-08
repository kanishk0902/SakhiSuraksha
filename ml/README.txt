Jaipur Safe Route — local dev setup
=====================================

This runs the ML-backed safe-routing backend locally on your Mac and wires
it to the Guardian iOS app's new "Safe Route" screen (Home → Safe Route).

What's here
-----------
- data/jaipur_segments_scored.csv — 368,094 scored Jaipur street segments
- data/danger_model.pkl — trained RandomForestRegressor (currently loaded
  but NOT used for live prediction — danger_score is precomputed in the CSV;
  the model is kept for future use). Loading it logs a scikit-learn version
  mismatch warning (pickled with 1.6.1, this venv has 1.9.0) — harmless
  since .predict() is never called, but re-pickle with a matching version
  before you ever do call it.
- src/main.py — the core scoring/routing logic (CSV load, k-d tree nearest-
  segment lookup, OSRM multi-mode routing, worst-segment scoring, tier
  classification). Originally written for Appwrite Cloud Functions.
- src/local_server.py — a thin FastAPI wrapper around main.py so it can run
  directly on this Mac instead of in the cloud. main.py itself is untouched.

1. One-time setup
------------------
    cd ml
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt

2. Run the server
------------------
    cd ml
    .venv/bin/uvicorn src.local_server:app --host 0.0.0.0 --port 8000 --reload

First request after startup loads the 368k-row CSV and builds the k-d tree
(a couple seconds) — subsequent requests are fast. Leave this running in a
terminal while you use the app.

Health check:
    curl http://localhost:8000/safe-routes
    → {"status":"ok","segments_loaded":368094,"tier_thresholds":{...}}

Example route request:
    curl -X POST http://localhost:8000/safe-routes \
      -H "Content-Type: application/json" \
      -d '{"start_lat":26.9124,"start_lon":75.7873,"end_lat":26.8851,"end_lon":75.8085,"modes":["walking","driving"]}'

3. Run the iOS app
--------------------
Open SakhiSuraksha.xcodeproj in Xcode, run the SakhiSuraksha scheme.

- iOS SIMULATOR: works immediately. SafeRoutingService.swift's baseURL
  defaults to http://localhost:8000, and the Simulator shares the Mac's
  network stack, so "localhost" reaches this server directly. No Info.plist
  changes were needed for this path — ATS automatically exempts
  localhost/127.0.0.1 connections.

- PHYSICAL iPHONE on the same Wi-Fi: "localhost" on the phone means the
  phone itself, not your Mac. You must:
    a) Find your Mac's LAN IP: `ipconfig getifaddr en0` (this Mac's IP was
       10.58.183.99 at time of writing — yours may differ, and it can
       change between networks/DHCP leases).
    b) Change SafeRoutingService.baseURL to
       http://<that-IP>:8000 (e.g. http://10.58.183.99:8000) — this isn't
       exposed as in-app UI yet, so edit it directly in
       Guardian/Services/SafeRoutingService.swift.
    c) Make sure the Mac's firewall allows incoming connections on port 8000
       (System Settings → Network → Firewall), and that the phone and Mac
       are on the same Wi-Fi network (not one on cellular/VPN).
  The app's Info.plist already has an NSAllowsLocalNetworking ATS exception
  (see SakhiSuraksha/InfoPlistAdditions.plist) covering this — no further
  Xcode changes needed for the physical-device path once baseURL points at
  the right IP.

4. In the app
--------------
Home → Safe Route → search a destination → pick walking/cycling/driving
(auto-preselected from your recent movement speed if available) → see
green/yellow/red route options with distance, duration, and a 0-100 safety
score. A persistent "Beta" badge is shown — see the honesty notes below.

Known model limitations (shown to the user, not hidden)
---------------------------------------------------------
- lighting_risk and crime_risk are constant placeholder values (no real
  data source integrated yet) — the model is really running on 3 signals:
  road type, police proximity, footfall density.
- Tier thresholds are calibrated from the real score DISTRIBUTION (33rd/
  66th percentile), not fixed points, but that calibration was only spot-
  checked against ~10 sampled routes — not statistically validated.
  Exact values from the current dataset: green_max ≈ 0.482,
  yellow_max ≈ 0.594 (danger_score scale, lower = safer).
- No ground-truth validation exists — don't present this as "accurate."
- Exposure multipliers (walking 1.5x, cycling 1.15x, driving 1.0x) and
  traffic-correction factors are estimates, not measured from real trips.

Not a shipping architecture
------------------------------
This backend runs on YOUR Mac only. It is reachable from:
  - the iOS Simulator (via localhost), always
  - a physical iPhone on the SAME Wi-Fi network as this Mac, if you point
    baseURL at the Mac's LAN IP and the Mac stays on and reachable
It is NOT reachable by:
  - anyone not on your local network
  - your phone once it leaves this Wi-Fi (cellular, another network, etc.)
  - anyone if your Mac is asleep, firewalled, or off

For real users on their own devices, this needs a real always-on backend
(a small cloud VM, a managed Python host, or finishing the Appwrite Cloud
Functions deployment src/main.py was originally written for) with a real
HTTPS domain — at that point the NSAllowsLocalNetworking/localhost ATS
exception in InfoPlistAdditions.plist should be removed or scoped down,
since it exists only to support this local-dev setup.
