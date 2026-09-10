Jaipur Safe Route — local dev setup
=====================================

This runs the ML-backed safe-routing backend locally on your Mac and wires
it to the Guardian iOS app's new "Safe Route" screen (Home → Safe Route).

What's here (v2)
-----------------
- data/jaipur_segments_safety_final.csv — 368,094 Jaipur street segments,
  with real per-segment features (road_type_risk, lighting_risk_for_danger,
  police_risk, footfall_risk) plus a precomputed safety_score fallback column.
- data/danger_model_v2.pkl — trained RandomForestRegressor, and it IS called
  live now (model.predict() runs per request in src/main.py — see that
  file's docstring for the v1→v2 change list). Loading it logs a
  scikit-learn version-mismatch warning (pickled with 1.6.1, this venv has
  1.9.0) — verified to still load correctly and expose the expected 4
  features in order; re-pickle with a matching version if results ever look
  suspicious.
- src/main.py — v2: a self-contained FastAPI app (defines `app` directly).
  Core logic: CSV/model load, k-d tree nearest-segment lookup, live
  model.predict() + citywide crime multiplier, OSRM multi-mode routing,
  worst-segment (lowest-safety) scoring, fixed-threshold tier classification,
  top-3-safest route ranking.
- src/local_server.py has been REMOVED — v2's main.py is itself the FastAPI
  app (no separate Appwrite-entrypoint/local-wrapper split anymore).

1. One-time setup
------------------
    cd ml
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt

2. Run the server
------------------
    cd ml
    .venv/bin/uvicorn src.main:app --host 0.0.0.0 --port 8000 --reload

First request after startup loads the 368k-row CSV and builds the k-d tree
(a couple seconds) — subsequent requests are fast. Leave this running in a
terminal while you use the app.

Health check:
    curl http://localhost:8000/health
    → {"status":"ok","segments_loaded":368094,"model_features":[...],"crime_multiplier":1.0523}

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

Known model limitations (shown to the user, not hidden) — v2
----------------------------------------------------------------
- Crime data is real (NCRB 2001-2005) but city-wide only, applied as a flat
  multiplier on the model's output rather than a per-segment feature — every
  per-segment crime proxy tested during development correlated too strongly
  with police_risk/footfall_risk to count as independent signal, so this is
  an honest simplification, not an oversight.
- Only 16 police stations were found in OSM data for Jaipur (likely an
  undercount versus the real number).
- lighting_risk_for_danger and road_type_risk are real (no longer constants)
  but modest contributors — police_risk dominates the model's predictions,
  which is a genuine data finding.
- Tier thresholds are FIXED business rules now (safety_score >75 = green,
  25–75 = yellow, <25 = red), not derived from the data distribution like
  v1's percentile approach — this is intentional per product requirements.
- No ground-truth validation exists — don't present this as "accurate."
- Exposure multipliers (walking 1.5x, cycling 1.15x, driving 1.0x) and
  traffic-correction factors are estimates, not measured from real trips.
- OSRM won't always return 3 route alternatives, especially for short/direct
  trips — the API then returns however many real alternatives exist (1-3),
  not a padded or fabricated count.

These are all returned in the API response's `disclosed_limitations` array —
surface them wherever the app already shows its Beta badge/provenance
labeling, so the app's honesty about limitations carries forward.

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
