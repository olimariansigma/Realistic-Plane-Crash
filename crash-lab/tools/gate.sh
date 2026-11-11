#!/usr/bin/env bash
# Runs all three milestone quality gates in order; stops at the first failure.
set -euo pipefail
D="$(dirname "$0")"
"$D/check.sh" && "$D/smoke.sh" && "$D/export_apk.sh" debug
echo "ALL GATES PASS"
