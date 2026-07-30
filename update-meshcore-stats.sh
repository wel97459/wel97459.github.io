#!/bin/bash
# update-meshcore-stats.sh
# Fetches live network stats from the CoreScope API (map.nvme.sh) and writes
# a normalized data/meshcore-stats.json that the static site consumes.
#
# Why this approach: GitHub Pages is static and CoreScope sends no CORS header,
# so the browser cannot fetch the API directly. Instead we pull it on a schedule
# (cron / GitHub Action) and commit the result; the page loads data/meshcore-stats.json.
#
# Usage:  ./update-meshcore-stats.sh [instance]
#   instance defaults to "live3" (the Nevada Mesh live map instance)

SITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SITE_DIR/data"
INSTANCE="${1:-live3}"

# CoreScope public API (no auth, no CORS -> fetched server-side here)
API_BASE="https://map.nvme.sh/api"

echo "Fetching CoreScope stats (instance=$INSTANCE) ..."

mkdir -p "$DATA_DIR"

# Pull both endpoints; python does the normalization (no jq dependency).
python3 - "$API_BASE" "$INSTANCE" "$DATA_DIR/meshcore-stats.json" <<'PY'
import sys, json, time, urllib.request

api_base, instance, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
stats_url  = f"{api_base}/stats?instance={instance}"
nodes_url  = f"{api_base}/nodes?instance={instance}"

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "nvme-sh-stats/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())

try:
    stats = get(stats_url)
except Exception as e:
    print(f"ERROR fetching /api/stats: {e}")
    sys.exit(1)

# Nodes are optional (large); degrade gracefully if unavailable.
nodes = []
try:
    nodes = get(nodes_url).get("nodes", []) or []
except Exception as e:
    print(f"WARN fetching /api/nodes: {e} (continuing with stats only)")

now = time.time()
def age_seconds(iso):
    if not iso:
        return None
    try:
        from datetime import datetime
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return now - dt.timestamp()
    except Exception:
        return None

active_24h = 0
active_7d  = 0
top = []
for n in nodes:
    a = age_seconds(n.get("last_heard"))
    if a is None:
        continue
    if a < 86400:
        active_24h += 1
    if a < 604800:
        active_7d += 1
    rc = n.get("relay_count_24h") or 0
    if rc > 0:
        top.append({"user": n.get("name") or n.get("public_key", "?")[:12], "count": rc})

top.sort(key=lambda x: x["count"], reverse=True)

# Coarse "cities" estimate: distinct non-zero coordinate cells (~0.1 deg).
cells = set()
for n in nodes:
    lat, lon = n.get("lat"), n.get("lon")
    if lat and lon and (lat != 0 or lon != 0):
        cells.add((round(lat, 1), round(lon, 1)))
cities = len(cells)

counts = stats.get("counts", {}) or {}

normalized = {
    "source": "corescope",
    "instance": instance,
    "timestamp": now,
    "nodes_all":      stats.get("totalNodes"),
    "nodes_24h":      active_24h,
    "nodes_7d":       active_7d,
    "packets_24h":    stats.get("packetsLast24h"),
    "observations_24h": stats.get("totalObservations"),
    "repeaters":      counts.get("repeaters"),
    "rooms":          counts.get("rooms"),
    "companions":     counts.get("companions"),
    "observers":      stats.get("totalObservers"),
    "cities":         cities,
    "top_users":      top[:8],
    "raw": {
        "totalPackets":     stats.get("totalPackets"),
        "totalTransmissions": stats.get("totalTransmissions"),
        "hashMigrationComplete": stats.get("hashMigrationComplete"),
    },
}

with open(out_path, "w") as f:
    json.dump(normalized, f, indent=2)

print(f"OK wrote {out_path}")
print(f"   totalNodes={normalized['nodes_all']} active24h={active_24h} active7d={active_7d} "
      f"packets24h={normalized['packets_24h']} observers={normalized['observers']}")
PY

echo ""
echo "Next step: git add data/ && git commit && git push"
