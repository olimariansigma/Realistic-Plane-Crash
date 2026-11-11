#!/usr/bin/env bash
# Quality gate 3: export a signed APK. Usage: tools/export_apk.sh [debug|release]
# Release signing needs GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD} in the env.
set -uo pipefail
source "$(dirname "$0")/_env.sh"
MODE="${1:-debug}"
OUT="$PROJECT_DIR/build/crash-lab-$MODE.apk"
SDK="${ANDROID_HOME:-$HOME/android-sdk}"
LOG="$(mktemp)"; trap 'rm -f "$LOG"' EXIT
mkdir -p "$PROJECT_DIR/build"; rm -f "$OUT"

run_godot "--export-$MODE" "Android" "$OUT" >"$LOG" 2>&1; code=$?
grep -E "^(ERROR|WARNING)|error" "$LOG" | grep -v "JAVA_TOOL_OPTIONS" | head -20
if [ "$code" -ne 0 ] || [ ! -s "$OUT" ]; then echo "EXPORT FAIL (exit $code)"; cat "$LOG" | tail -20; exit 1; fi

APKSIGNER="$(ls "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
if [ -n "$APKSIGNER" ]; then
  "$APKSIGNER" verify "$OUT" 2>/dev/null || { echo "EXPORT FAIL: signature does not verify"; exit 1; }
fi
SIZE_MB=$(( $(stat -c %s "$OUT") / 1048576 ))
echo "EXPORT PASS: $OUT (${SIZE_MB} MB, budget 150 MB)"
[ "$SIZE_MB" -le 150 ] || { echo "EXPORT FAIL: over size budget"; exit 1; }
