#!/usr/bin/env bash
# Runs all three milestone quality gates in order; stops at the first failure.
# Each gate is checked explicitly: `set -e` does not act on a failing command
# inside an `&&` chain, which once let this script print PASS after a failure.
set -uo pipefail
D="$(dirname "$0")"
"$D/check.sh" || { echo "GATES FAIL (check)"; exit 1; }
"$D/smoke.sh" || { echo "GATES FAIL (smoke)"; exit 1; }
"$D/export_apk.sh" debug || { echo "GATES FAIL (export)"; exit 1; }
echo "ALL GATES PASS"
