#!/usr/bin/env bash
# Pull-request CI entrypoint for the self-hosted "jankurai-ci" runner.
# This is the script .github/workflows/ci.yml runs first in its host-ci
# cascade, so local runs and CI execute the exact same commands. It is a thin
# wrapper over the required local-CI lane in scripts/ci-local.sh (which itself
# delegates to ops/ci/required.sh) plus a no-write jankurai self-audit so the
# repo-score artifacts are produced on every PR.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "${CI_ROOT}" || exit 1

ensure_dir "${ARTIFACT_ROOT}"

step "Required local CI cascade"
bash scripts/ci-local.sh required

step "Jankurai self-audit (repo-score)"
if command -v jankurai >/dev/null 2>&1; then
  jankurai audit . \
    --no-score-history \
    --json "${ARTIFACT_ROOT}/repo-score.json" \
    --md "${ARTIFACT_ROOT}/repo-score.md"
  assert_nonempty "${ARTIFACT_ROOT}/repo-score.json"
  assert_nonempty "${ARTIFACT_ROOT}/repo-score.md"
else
  note "jankurai not on PATH; skipping self-audit on this runner"
fi

step "pr-ci complete"
