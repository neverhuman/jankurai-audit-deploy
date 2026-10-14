#!/usr/bin/env bash
# Full deployment-tooling gate. The forge runs it for every pull request head
# through ops/ci/pr-ci.sh (the `required` lane in .jeryu/ci.toml), and
# `just check` runs it locally. Assembled product proofs and releases run in
# the hub. GitHub is a publishing mirror only and runs nothing here.
#
#   1. required lane: lane contract, forge gate contract, bash -n, shellcheck,
#      action.yml lint (zizmor), vendored installer check and self-test;
#   2. secret scan of the full git history (gitleaks);
#   3. CycloneDX SBOM (syft) and a vulnerability scan of it (grype);
#   4. jankurai ratchet audit against protected main, scored by the same
#      auditor binary, so a head cannot score below main.
#
# The auditor comes from JANKURAI (an explicit path) or from PATH; the forge
# gate hosts provide the governed build. Its version and digest are recorded
# next to the score so the evidence names the exact scorer.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

mkdir -p target/jankurai/security .jankurai

jankurai_bin="${JANKURAI:-$(command -v jankurai || true)}"
if [[ -z "$jankurai_bin" || ! -x "$jankurai_bin" ]]; then
  echo "check: no jankurai auditor (set JANKURAI=/path/to/jankurai or put it on PATH)" >&2
  exit 1
fi
export JANKURAI="$jankurai_bin"
{
  printf 'path=%s\n' "$jankurai_bin"
  printf 'version=%s\n' "$("$jankurai_bin" --version)"
  printf 'sha256=%s\n' "$(sha256sum "$jankurai_bin" | cut -d' ' -f1)"
} > target/jankurai/auditor.txt

echo "[ci] check: required lane"
bash ops/ci/required.sh

echo "[ci] check: secret scan (gitleaks, full history)"
gitleaks detect --source . --no-banner --redact

echo "[ci] check: SBOM (syft) and vulnerability scan (grype)"
syft dir:. --exclude './target/**' --exclude './.git/**' --exclude './node_modules/**' \
  -o cyclonedx-json=target/jankurai/security/sbom.json
test -s target/jankurai/security/sbom.json
grype sbom:target/jankurai/security/sbom.json --fail-on high

echo "[ci] check: protected-main baseline and ratchet audit ($("$jankurai_bin" --version))"
bash ops/ci/prepare-baseline.sh
"$jankurai_bin" audit . --mode ratchet --baseline target/jankurai/accepted-baseline.json --full \
  --no-score-history --json .jankurai/repo-score.json --md .jankurai/repo-score.md
