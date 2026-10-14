#!/usr/bin/env bash
# Advisory jankurai self-audit with the verified auditor (ops/ci/auditor.sh):
# the governed install, or an explicit JANKURAI override recorded as
# unverified. Used by `just fast` and `just audit`; never a bare `jankurai`.
#
# usage: self-audit.sh <json-out> <md-out>
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
json_out="${1:?usage: self-audit.sh <json-out> <md-out>}"
md_out="${2:?usage: self-audit.sh <json-out> <md-out>}"
# shellcheck source=ops/ci/auditor.sh
source ops/ci/auditor.sh
resolve_auditor
trap 'rm -rf "$AUDITOR_DIR"' EXIT
echo "[ci] self-audit: $AUDITOR_IDENTITY"
mkdir -p "$(dirname "$json_out")" "$(dirname "$md_out")"
reverify_auditor
"$JANKURAI" audit . --no-score-history --json "$json_out" --md "$md_out"
