#!/usr/bin/env bash
# Quality gate 2: run every headless smoke test in tests/smoke_*.gd, then play
# the real game through from the hangar to a crash report (tools/playtest.sh).
set -uo pipefail
source "$(dirname "$0")/_env.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
JOBS="${SMOKE_JOBS:-3}"

# One line per job: "<test file> <aircraft id or ->". The flight, crash and
# damage tests run once for every shipped aircraft.
: > "$TMP/jobs"
for t in "$PROJECT_DIR"/tests/smoke_*.gd; do
  name="$(basename "$t")"
  case "$name" in
    smoke_flight.gd|smoke_crash.gd|smoke_damage.gd)
      for def in "$PROJECT_DIR"/data/aircraft/*.tres; do
        echo "$name $(basename "$def" .tres)" >> "$TMP/jobs"
      done ;;
    *) echo "$name -" >> "$TMP/jobs" ;;
  esac
done

run_job() {  # run_job <test file> <id or ->
  local name="$1" id="$2" log="$TMP/$1.$2.log" code=0
  if [ "$id" = "-" ]; then
    "$GODOT" --headless --path "$PROJECT_DIR" --fixed-fps 60 -s "res://tests/$name" >"$log" 2>&1 || code=$?
  else
    "$GODOT" --headless --path "$PROJECT_DIR" --fixed-fps 60 -s "res://tests/$name" -- "$id" >"$log" 2>&1 || code=$?
  fi
  echo "$code" > "$log.code"
}
export -f run_job
export GODOT PROJECT_DIR TMP
xargs -P "$JOBS" -L 1 bash -c 'run_job "$0" "$1"' < "$TMP/jobs"

fail=0
while read -r name id; do
  log="$TMP/$name.$id.log"
  code="$(cat "$log.code" 2>/dev/null || echo 1)"
  grep -E "SMOKE (PASS|FAIL)|^(ERROR|SCRIPT ERROR)" "$log" | cut -c1-400
  if [ "$code" -ne 0 ] || ! grep -q "SMOKE PASS" "$log" \
      || grep -qE "^(ERROR|SCRIPT ERROR)" "$log"; then
    echo "FAIL $name $id (exit $code)"; fail=1
  fi
done < "$TMP/jobs"

"$(dirname "$0")/playtest.sh" || fail=1
[ "$fail" -eq 0 ] && echo "SMOKE PASS (all)" || { echo "SMOKE FAIL"; exit 1; }
