#!/usr/bin/env bash
# Flies every aircraft through tests/smoke_flight.gd, records the trim and
# throttle that held level flight at cruise speed in
# data/aircraft/calibration.json, and regenerates the definitions so in-flight
# starts begin trimmed. Run after changing aerodynamics or the fleet.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
OUT="$PROJECT_DIR/data/aircraft/calibration.json"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ls "$PROJECT_DIR"/data/aircraft/*.tres | xargs -n1 basename | sed 's/\.tres$//' > "$TMP/ids"
# Three at a time: each run is single-threaded script plus a small physics pool.
xargs -P 3 -I{} sh -c "\"$GODOT\" --headless --path \"$PROJECT_DIR\" --fixed-fps 60 -s res://tests/smoke_flight.gd -- {} > \"$TMP/{}.log\" 2>&1" < "$TMP/ids"
fail=0
echo "{" > "$OUT.new"
first=1
while read -r id; do
  line="$(grep -E "SMOKE (PASS|FAIL)" "$TMP/$id.log" | head -1)"
  echo "$id: ${line:-no result}"
  if echo "$line" | grep -q "SMOKE PASS"; then
    trim="$(echo "$line" | sed -E 's/.*\(trim (-?[0-9.]+), throttle ([0-9.]+).*/\1/')"
    thr="$(echo "$line" | sed -E 's/.*\(trim (-?[0-9.]+), throttle ([0-9.]+).*/\2/')"
    [ "$first" -eq 1 ] || echo "," >> "$OUT.new"
    first=0
    printf '  "%s": {"trim": %s, "throttle": %s}' "$id" "$trim" "$thr" >> "$OUT.new"
  else
    fail=1
  fi
done < "$TMP/ids"
printf '\n}\n' >> "$OUT.new"
mv "$OUT.new" "$OUT"
run_godot -s res://tools/gen_aircraft.gd 2>&1 | grep -E "GEN (PASS|FAIL)"
[ "$fail" -eq 0 ] && echo "CALIBRATE PASS" || { echo "CALIBRATE: some aircraft failed the flight test"; exit 1; }
