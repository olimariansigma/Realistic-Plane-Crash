#!/usr/bin/env bash
# Quality gate 1: import the project and parse every GDScript; any error fails.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
fail=0

echo "== import"
run_godot --import >"$LOG" 2>&1 || fail=1
if grep -E "^(ERROR|SCRIPT ERROR)|Parse Error|Failed to load" "$LOG"; then fail=1; fi

echo "== check-only"
count=0
while IFS= read -r -d '' f; do
  count=$((count + 1))
  rel="res://${f#"$PROJECT_DIR"/}"
  if ! run_godot --check-only --script "$rel" >"$LOG" 2>&1 \
      || grep -qE "^(ERROR|SCRIPT ERROR)|Parse Error" "$LOG"; then
    echo "FAIL $rel"; grep -vE "^(Godot Engine|$)" "$LOG" | head -20
    fail=1
  fi
done < <(find "$PROJECT_DIR" -name '*.gd' -not -path '*/.godot/*' -not -path '*/android/*' -print0)

if [ "$fail" -ne 0 ]; then echo "CHECK FAIL"; exit 1; fi
echo "CHECK PASS ($count scripts, 0 errors)"
