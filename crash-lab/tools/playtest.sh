#!/usr/bin/env bash
# Plays the real game from start to finish with synthetic touches
# (scripts/core/autoplay.gd): boot, hangar, pick an aircraft, launch, take off,
# crash, crash report, replay, restart, back to the hangar. Runs at real-time
# pacing, without --fixed-fps, exactly as the exported game does.
#
#   tools/playtest.sh [next-taps] [screenshot dir]
#
# With a screenshot directory it runs under xvfb at a phone aspect ratio
# (PLAYTEST_RES, default 1600x720) and
# saves a picture of every stage (needs xvfb and a Vulkan software driver).
set -uo pipefail
source "$(dirname "$0")/_env.sh"
TAPS="${1:-0}"
SHOTS="${2:-}"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
if [ -n "$SHOTS" ]; then
  mkdir -p "$SHOTS"
  RES="${PLAYTEST_RES:-1600x720}"
  CRASHLAB_AUTOPLAY="$TAPS" CRASHLAB_AUTOPLAY_SHOTS="$(cd "$SHOTS" && pwd)" timeout 3000 \
    xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --audio-driver Dummy --path "$PROJECT_DIR" --resolution "$RES" >"$LOG" 2>&1
else
  CRASHLAB_AUTOPLAY="$TAPS" timeout 900 "$GODOT" --headless --path "$PROJECT_DIR" >"$LOG" 2>&1
fi
code=$?
grep -E "AUTOPLAY (PASS|FAIL)|^(ERROR|SCRIPT ERROR)" "$LOG" | cut -c1-400 | awk '!seen[$0]++'
if [ "$code" -ne 0 ] || ! grep -q "AUTOPLAY PASS" "$LOG" || grep -qE "^(ERROR|SCRIPT ERROR)" "$LOG"; then
  echo "FAIL playtest (exit $code, last stage: $(grep "AUTOPLAY stage" "$LOG" | tail -1))"
  exit 1
fi
