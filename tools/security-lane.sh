#!/usr/bin/env bash
# Canonical security lane wrapper for jankurai-deploy.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p target

echo "[security] secret scan: gitleaks detect"
gitleaks detect --source . --no-banner --redact

echo "[security] GitHub Actions surface lint: scripts/lint-actions.sh"
bash scripts/lint-actions.sh

if [ -f Cargo.toml ]; then
  echo "[security] cargo audit"
  cargo audit
fi

if [ -f package.json ]; then
  echo "[security] npm audit"
  npm audit --audit-level=high
fi

echo "[security] SBOM / provenance: hash deploy scripts"
find ops scripts jankurai-installer.sh README.md AGENTS.md -type f 2>/dev/null | sort | xargs sha256sum > target/sbom.txt
echo "[security] sbom written to target/sbom.txt"
