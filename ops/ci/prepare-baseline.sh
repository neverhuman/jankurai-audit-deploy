#!/usr/bin/env bash
# Score the protected default-branch source using the same auditor as the
# candidate: the verified private copy ops/ci/check.sh exports as JANKURAI with
# its digest in JANKURAI_SHA256. There is no PATH fallback; without both
# variables this fails closed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
# shellcheck source=ops/ci/auditor.sh
source ops/ci/auditor.sh
[[ -n "${JANKURAI:-}" && -n "${JANKURAI_SHA256:-}" ]] ||
  auditor_die "prepare-baseline: JANKURAI/JANKURAI_SHA256 unset; run it through ops/ci/check.sh"
repo_root="$PWD"
mkdir -p target/jankurai
baseline_root="$(mktemp -d "$repo_root/target/ci-baseline.XXXXXX")"
trap 'rm -rf "$baseline_root"' EXIT
base="$(git rev-parse refs/remotes/origin/main)"
git clone --no-hardlinks --no-checkout "$repo_root" "$baseline_root/repo"
git -C "$baseline_root/repo" checkout --detach "$base"
reverify_auditor
"$JANKURAI" audit "$baseline_root/repo" --mode advisory --no-score-history \
  --json "$repo_root/target/jankurai/accepted-baseline.json" \
  --md "$repo_root/target/jankurai/accepted-baseline.md"
