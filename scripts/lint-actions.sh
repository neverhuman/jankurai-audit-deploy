#!/usr/bin/env bash
# Static analysis of the GitHub Actions surface this repository still ships.
#
# GitHub is a publishing mirror and no workflow is committed here
# (scripts/forge-gate-test.sh rejects .github/workflows), but action.yml is a
# published composite action that downstream workflows run, so it is linted
# on every required run. zizmor runs offline: template injection, unpinned
# `uses:`, excessive permissions and the rest of its offline audits. If a
# workflow directory ever appears, actionlint and zizmor lint it as well.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v zizmor >/dev/null ||
  { echo "lint-actions: zizmor is not installed (bash ops/ci/security-tools.sh)" >&2; exit 1; }

echo "[ci] action lint: zizmor action.yml"
zizmor --offline --no-progress action.yml

if [[ -d .github/workflows ]]; then
  command -v actionlint >/dev/null ||
    { echo "lint-actions: actionlint is not installed (bash ops/ci/install-security-tools.sh)" >&2; exit 1; }
  echo "[ci] workflow lint: actionlint + zizmor .github/workflows"
  actionlint .github/workflows/*.yml
  zizmor --offline --no-progress .github/workflows
fi
