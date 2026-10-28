#!/usr/bin/env bash
# Forge CI entrypoint. .jeryu/ci.toml declares this script as the `required`
# lane, and the forge gate runs it for every pull request head (there is no
# `just required` recipe, so the gate falls back to this file). Local runs
# execute the exact same command: `bash scripts/ci-local.sh pr-ci`.
#
# It runs the full gate in ops/ci/check.sh (required lane, gitleaks, syft
# SBOM, audit against the score floor in agent/audit-policy.toml) with the
# governed auditor only:
# a JANKURAI override is refused here. Whatever the outcome, it then writes a
# local evidence bundle in the workspace, so a failing head still leaves its
# partial output behind for review. Nothing is skipped: a missing tool fails
# the run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

collect() {
  local gate_exit=$?
  trap - EXIT
  local collect_exit=0
  bash ops/ci/collect-evidence.sh "$gate_exit" || collect_exit=$?
  if [[ "$gate_exit" -ne 0 ]]; then
    exit "$gate_exit"
  fi
  exit "$collect_exit"
}
trap collect EXIT

echo "[ci] pr-ci: full gate (ops/ci/check.sh)"
JANKURAI_REQUIRE_GOVERNED=1 bash ops/ci/check.sh
