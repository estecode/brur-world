#!/usr/bin/env bash
set -euo pipefail

# Benchmarks the production native Sweden GPS search path over BSI2.
# Dependencies: Python 3, bin/brur-gps-search-server, and world_data/search_index.bsi.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${BRUR_SEARCH_BENCH_PORT:-47743}"
SERVER="$ROOT/bin/brur-gps-search-server"
INDEX="$ROOT/world_data/search_index.bsi"
JSONL="$ROOT/world_data/search_index.jsonl"
LOG="$(mktemp -t brur-search-bench.XXXXXX)"

cd "$ROOT"

if [[ ! -f "$INDEX" ]]; then
  if [[ ! -f "$JSONL" ]]; then
    echo "Missing world_data/search_index.jsonl" >&2
    echo "Build it first with:" >&2
    echo "  python tools/build_search_index.py /Users/stefanlind/Dropbox/Code/syndicate/data/sweden-260824.osm.pbf --output world_data" >&2
    exit 2
  fi
  python tools/build_search_binary.py "$JSONL" --output "$INDEX"
fi

if [[ ! -x "$SERVER" ]]; then
  bash tools/build_native_gps.sh
fi

"$SERVER" "$INDEX" "$PORT" 2>"$LOG" &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  rm -f "$LOG"
}
trap cleanup EXIT

python - "$PORT" <<'PY'
from __future__ import annotations

import json
import socket
import statistics
import sys
import time

sys.path.insert(0, "tools")
from gps_search import normalize_search_text

port = int(sys.argv[1])
deadline = time.monotonic() + 5.0
sock = None
while time.monotonic() < deadline:
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=0.5)
        break
    except OSError:
        time.sleep(0.05)
if sock is None:
    raise SystemExit("native GPS search server did not become ready")

queries = [
    "stockholm",
    "södersjukhuset",
    "kungsljusgatan 22",
    "kungsljusgatan 22 24756 dalby",
    "dalby",
    "centralstation",
]

def receive_line() -> str:
    chunks = bytearray()
    while True:
        value = sock.recv(65536)
        if not value:
            raise RuntimeError("search server disconnected")
        chunks.extend(value)
        newline = chunks.find(b"\n")
        if newline >= 0:
            return chunks[:newline].decode("utf-8")

times = []
for query in queries:
    normalized = normalize_search_text(query)
    payload = f"search 8 {normalized}\n".encode("utf-8")
    wall_started = time.perf_counter()
    sock.sendall(payload)
    response = json.loads(receive_line())
    wall_ms = (time.perf_counter() - wall_started) * 1000.0
    if not response.get("success"):
        raise RuntimeError(response)
    query_ms = float(response.get("query_ms", 0.0))
    times.append(query_ms)
    results = response.get("results", [])
    first = results[0].get("display", "") if results else "-"
    print(f"{query:34s} native={query_ms:9.3f} ms | wall={wall_ms:9.3f} ms | {len(results)} result(s) | first={first}")

ordered = sorted(times)
p50 = statistics.median(ordered)
p95_index = max(0, min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1)))))
p95 = ordered[p95_index]
print(f"native search summary | p50={p50:.3f} ms | p95={p95:.3f} ms | max={max(ordered):.3f} ms")
sock.close()
PY

cat "$LOG"
