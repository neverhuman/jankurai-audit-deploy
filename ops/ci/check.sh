#!/usr/bin/env bash
# Full deployment-tooling gate. The forge runs it for every pull request head
# through ops/ci/pr-ci.sh (the `required` lane in .jeryu/ci.toml), and
# `just check` runs it locally. Assembled product proofs and releases run in
# the hub. GitHub is a publishing mirror only and runs nothing here.
#
#   1. required lane: lane contract, forge gate contract, bash -n, shellcheck,
#      action.yml lint (zizmor), vendored installer check and self-test;
#   2. secret scan of the full git history (gitleaks);
#   3. CycloneDX SBOM (syft), with its component count recorded. This repo has
#      no package manifests, so the SBOM is expected to be empty and there is
#      nothing for a vulnerability scanner to match;
#   4. jankurai audit of the head against the score floor: `minimum_score` in
#      agent/audit-policy.toml (85), with no critical or high finding. The
#      same auditor binary also scores protected main, and the comparison
#      with main is recorded in the report (`decision.ratchet`) but does not
#      fail the head. See docs/decisions/0001-score-floor-85.md.
#
# Auditor identity: see ops/ci/auditor.sh. The governed install is verified
# against the host's authority stamp, copied into a private directory, and the
# copy is re-verified immediately before each audit (baseline and head).
# ops/ci/pr-ci.sh refuses a JANKURAI override (JANKURAI_REQUIRE_GOVERNED=1).
#
# `check.sh --identity-only` runs only the auditor check and exits; the
# forge-gate test uses it so a weakened check can never recurse into the gate.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# shellcheck source=ops/ci/auditor.sh
source ops/ci/auditor.sh
resolve_auditor
trap 'rm -rf "$AUDITOR_DIR"' EXIT
if [[ "${1:-}" == "--identity-only" ]]; then
  echo "[ci] check: auditor identity ok: $AUDITOR_IDENTITY"
  exit 0
fi
mkdir -p target/jankurai/security .jankurai
reverify_auditor
auditor_version="$("$JANKURAI" --version)"
{
  printf 'identity=%s\n' "$AUDITOR_IDENTITY"
  printf 'version=%s\n' "$auditor_version"
  printf 'sha256=%s\n' "$JANKURAI_SHA256"
  printf 'note=%s\n' "verified, copied privately and re-verified before each audit; same-user code can still tamper (see ops/ci/auditor.sh)"
} > target/jankurai/auditor.txt
echo "[ci] check: auditor $auditor_version, $AUDITOR_IDENTITY"

echo "[ci] check: required lane"
bash ops/ci/required.sh

echo "[ci] check: secret scan (gitleaks, full history)"
gitleaks detect --source . --no-banner --redact

echo "[ci] check: SBOM (syft)"
syft dir:. --exclude './target/**' --exclude './.git/**' --exclude './node_modules/**' \
  -o cyclonedx-json=target/jankurai/security/sbom.json
jq -e '.bomFormat == "CycloneDX"' target/jankurai/security/sbom.json >/dev/null
jq '.components // [] | length' target/jankurai/security/sbom.json \
  > target/jankurai/security/sbom-components.txt
echo "[ci] SBOM components: $(cat target/jankurai/security/sbom-components.txt)"

echo "[ci] check: protected-main baseline (recorded) and score-floor audit"
bash ops/ci/prepare-baseline.sh
# --no-badge: an enforcing audit otherwise rewrites the committed badge from
# agent/baselines/main.repo-score.json, and refuses to because that report is
# advisory. The gate scores the head; it never edits committed files.
reverify_auditor
"$JANKURAI" audit . --mode standard --baseline target/jankurai/accepted-baseline.json --full \
  --no-badge --no-score-history --json .jankurai/repo-score.json --md .jankurai/repo-score.md
