#!/usr/bin/env bash
# Deployment tooling checks; assembled product proofs and releases run in the hub.
# CI runs this on the forge and our own hosts; GitHub is a publishing mirror only.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PATH="$PWD/target/ci-tools/bin:$PATH"
bash ops/ci/required.sh
bash ops/ci/prepare-baseline.sh
mkdir -p target/jankurai/security .jankurai
gitleaks detect --source . --no-banner --redact
syft dir:. -o cyclonedx-json=target/jankurai/security/sbom.json
jankurai audit . --mode ratchet --baseline target/jankurai/accepted-baseline.json --full \
  --no-score-history --json .jankurai/repo-score.json --md .jankurai/repo-score.md
