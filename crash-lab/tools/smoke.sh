#!/usr/bin/env bash
# Quality gate 2: run every headless smoke test in tests/smoke_*.gd.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
fail=0
for t in "$PROJECT_DIR"/tests/smoke_*.gd; do
  rel="res://tests/$(basename "$t")"
  run_godot --fixed-fps 60 -s "$rel" >"$LOG" 2>&1; code=$?
  grep -E "SMOKE (PASS|FAIL)|^(ERROR|SCRIPT ERROR)" "$LOG"
  if [ "$code" -ne 0 ] || ! grep -q "SMOKE PASS" "$LOG" \
      || grep -qE "^(ERROR|SCRIPT ERROR)" "$LOG"; then
    echo "FAIL $rel (exit $code)"; fail=1
  fi
done
[ "$fail" -eq 0 ] && echo "SMOKE PASS (all)" || { echo "SMOKE FAIL"; exit 1; }
