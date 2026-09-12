#!/usr/bin/env bash
# Verifies playtest target allowlisting and preparation/launch orchestration with an isolated fake project.
# Dependencies: bash and standard POSIX utilities; no Godot or production world data is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/tools/playtest.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-playtest-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAKE_ROOT="$TMP/repo"
mkdir -p "$FAKE_ROOT/tools" "$FAKE_ROOT/native" "$FAKE_ROOT/bin" "$FAKE_ROOT/world_data" "$FAKE_ROOT/scenes" "$FAKE_ROOT/harness/gps" "$FAKE_ROOT/harness/driving" "$FAKE_ROOT/.venv/bin"
cp "$SOURCE" "$FAKE_ROOT/tools/playtest.sh"
chmod +x "$FAKE_ROOT/tools/playtest.sh"
printf 'source\n' > "$FAKE_ROOT/native/dummy.cpp"
printf 'scene\n' > "$FAKE_ROOT/scenes/main.tscn"
printf 'scene\n' > "$FAKE_ROOT/harness/gps/gps_harness.tscn"
printf 'scene\n' > "$FAKE_ROOT/harness/driving/driving_harness.tscn"
printf 'requirements\n' > "$FAKE_ROOT/requirements.txt"
for name in manifest.json routing.brg routing_snap.brs routing_geometry.brh routing_stats.json search_index.bsi; do
  printf 'data\n' > "$FAKE_ROOT/world_data/$name"
done
for name in build_sweden.py build_roads.py build_routing.py build_routing_dataset.py build_background.py build_features.py build_search_index.py build_search_binary.py compressed_routing.py gps_snap_index.py route_geometry.py routing_graph.py routing_graph_view.py world_common.py; do
  printf 'builder\n' > "$FAKE_ROOT/tools/$name"
done
sleep 1
for name in brur-gps-server brur-gps-search-server; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_ROOT/bin/$name"
  chmod +x "$FAKE_ROOT/bin/$name"
done

GODOT_LOG="$TMP/godot.log"
cat > "$TMP/godot" <<EOF_GODOT
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$GODOT_LOG"
EOF_GODOT
chmod +x "$TMP/godot"

if BRUR_GODOT="$TMP/godot" bash "$FAKE_ROOT/tools/playtest.sh" 'game;touch /tmp/brur-playtest-injection' >"$TMP/out" 2>"$TMP/err"; then
  echo 'expected injected target to be rejected' >&2
  exit 1
fi
grep -q 'unsupported target' "$TMP/err"
[[ ! -e /tmp/brur-playtest-injection ]]
[[ ! -e "$GODOT_LOG" ]]

BRUR_GODOT="$TMP/godot" bash "$FAKE_ROOT/tools/playtest.sh" game >"$TMP/game.out"
grep -q 'PLAYTEST=READY world-data' "$TMP/game.out"
grep -q 'PLAYTEST=READY native-gps' "$TMP/game.out"
grep -q -- "--path $FAKE_ROOT $FAKE_ROOT/scenes/main.tscn" "$GODOT_LOG"

: > "$GODOT_LOG"
BRUR_GODOT="$TMP/godot" bash "$FAKE_ROOT/tools/playtest.sh" gps >"$TMP/gps.out"
grep -q 'PLAYTEST=READY routing-dataset' "$TMP/gps.out"
grep -q -- "--path $FAKE_ROOT $FAKE_ROOT/harness/gps/gps_harness.tscn" "$GODOT_LOG"

: > "$GODOT_LOG"
BRUR_GODOT="$TMP/godot" bash "$FAKE_ROOT/tools/playtest.sh" driving >"$TMP/driving.out"
grep -q 'PLAYTEST=RUN target=driving scene=harness/driving/driving_harness.tscn' "$TMP/driving.out"
grep -q -- "--path $FAKE_ROOT $FAKE_ROOT/harness/driving/driving_harness.tscn" "$GODOT_LOG"

rm "$FAKE_ROOT/world_data/routing_geometry.brh"
: > "$GODOT_LOG"
if BRUR_GODOT="$TMP/godot" bash "$FAKE_ROOT/tools/playtest.sh" gps >"$TMP/missing.out" 2>"$TMP/missing.err"; then
  echo 'expected missing route geometry without PBF to fail' >&2
  exit 1
fi
grep -q 'set BRUR_WORLD_PBF' "$TMP/missing.err"
[[ ! -s "$GODOT_LOG" ]]

printf 'PLAYTEST_LAUNCHER_TEST=PASS\n'
