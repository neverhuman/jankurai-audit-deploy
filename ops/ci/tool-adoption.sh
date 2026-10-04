#!/usr/bin/env bash
# Tool-adoption evidence lane.
#
# jankurai replaces a fleet of ad-hoc tools (manual scoring, gitleaks-only
# security, hand-rolled copy-code/contract drift checks) with first-class
# subcommands. This lane runs each adopted command in CI and writes its
# evidence artifact under target/jankurai/ so the audit can prove the
# replacement actually executed. The matching artifacts are uploaded by the
# workflow's actions/upload-artifact step.
#
# Each command below is written as the catalog's canonical literal so the
# local runner and CI execute the exact replacement command.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "${CI_ROOT}" || exit 1

mkdir -p target/jankurai .jankurai target/jankurai/security \
         target/jankurai/proofbind target/jankurai/proofmark

# audit-ci / proof-routing / contract-drift / authz-matrix / agent-tool-supply
# / release-readiness / cost-budget all adopt the jankurai audit command.
step "tool-adoption: jankurai audit (ratchet)"
cp .jankurai/repo-score.json target/jankurai/accepted-baseline.json 2>/dev/null || \
  jankurai audit . --mode advisory --json target/jankurai/accepted-baseline.json --md /dev/null 2>/dev/null || true
jankurai audit . --mode ratchet --baseline target/jankurai/accepted-baseline.json --json target/jankurai/repo-score.json --md target/jankurai/repo-score.md

step "tool-adoption: jankurai audit (advisory)"
jankurai audit . --mode advisory --json .jankurai/repo-score.json --md .jankurai/repo-score.md

# proof-routing: changed-surface proof plan replacing ad hoc lane choice.
step "tool-adoption: jankurai proof"
jankurai proof . --changed-from origin/main --out target/jankurai/proof-plan.json --md target/jankurai/proof-plan.md

# proofbind: changed-surface proof obligation routing.
step "tool-adoption: jankurai proofbind verify"
jankurai proofbind verify . --changed-from origin/main

# copy-code: duplication triage replacing ad-hoc copy-code review.
step "tool-adoption: jankurai copy-code"
cargo run -p jankurai -- copy-code . --json target/jankurai/copy-code.json --md target/jankurai/copy-code.md

# security: secret + dependency + SBOM/provenance evidence in one lane.
step "tool-adoption: jankurai security run"
jankurai security run . --out target/jankurai/security/evidence.json

# ci/git/release bad-behavior: language-level workflow safety tests.
step "tool-adoption: language bad-behavior tests"
cargo test -p jankurai --test language_bad_behavior
