#!/usr/bin/env bash
# Quality gate 2: run every headless smoke test in tests/smoke_*.gd.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
fail=0
run_test() {  # run_test <res path> [user args...]
  local rel="$1"; shift
  run_godot --fixed-fps 60 -s "$rel" -- "$@" >"$LOG" 2>&1; local code=$?
  grep -E "SMOKE (PASS|FAIL)|^(ERROR|SCRIPT ERROR)" "$LOG"
  if [ "$code" -ne 0 ] || ! grep -q "SMOKE PASS" "$LOG" \
      || grep -qE "^(ERROR|SCRIPT ERROR)" "$LOG"; then
    echo "FAIL $rel $* (exit $code)"; fail=1
  fi
}
for t in "$PROJECT_DIR"/tests/smoke_*.gd; do
  rel="res://tests/$(basename "$t")"
  case "$(basename "$t")" in
    smoke_flight.gd|smoke_crash.gd)
      # Per-aircraft tests: every shipped plane must pass.
      for def in "$PROJECT_DIR"/data/aircraft/*.tres; do
        run_test "$rel" "$(basename "$def" .tres)"
      done ;;
    *) run_test "$rel" ;;
  esac
done
# The real boot -> hangar -> loading screen -> flight path, at real-time pacing
# (CRASHLAB_AUTOLAUNCH makes the hangar press LAUNCH by itself). Threaded
# resource loading misbehaves under --fixed-fps, so this one runs without it.
CRASHLAB_AUTOLAUNCH=1 run_godot --quit-after 480 >"$LOG" 2>&1
grep -E "Hangar ready|Flight ready|^(ERROR|SCRIPT ERROR)" "$LOG"
if ! grep -q "Hangar ready" "$LOG" || ! grep -q "Flight ready" "$LOG" \
    || grep -qE "^(ERROR|SCRIPT ERROR)" "$LOG"; then
  echo "FAIL boot flow"; fail=1
fi
[ "$fail" -eq 0 ] && echo "SMOKE PASS (all)" || { echo "SMOKE FAIL"; exit 1; }
