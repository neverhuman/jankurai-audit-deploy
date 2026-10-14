# jankurai-deploy root command surface.
# One-command setup and validation lanes for agents and CI.
# Every lane below is deterministic and runnable from the repo root, and each
# one delegates to the same ops/ci/*.sh and scripts/*.sh entrypoints forge CI
# runs, so local runs and CI execute identical commands (see docs/ci-local.md).
# There is deliberately no `required` recipe: the forge gate would run it in
# place of ops/ci/pr-ci.sh, the lane .jeryu/ci.toml declares.

# Default: list available lanes.
default:
    @just --list

# One-command bootstrap: install the toolchain components this repo needs and
# sanity-check the local CI helpers. Resolves install/bootstrap as aliases.
setup:
    bash scripts/ci-doctor.sh
    bash ops/ci/security-tools.sh

install: setup

bootstrap: setup

# Deterministic fast lane: the narrowest proof loop for agent iteration.
# Syntax-checks every shell entrypoint, runs a narrow per-package check against
# the locked dependency graph (the auditor crate this repo releases), and runs
# the required local proof so an agent can iterate without a full release build.
# Uses the cached, target-only build path so reruns stay fast.
fast:
    bash scripts/ci-local.sh required
    jankurai audit . --no-score-history --json target/jankurai/repo-score.json --md target/jankurai/repo-score.md

# Narrow per-package build of the released auditor crate against the locked
# dependency graph; the cached release pipeline reuses this target output.
build-jankurai:
    bash ../jankurai/scripts/family.sh build --release

# Run the full gate the forge runs (ops/ci/pr-ci.sh minus the evidence
# bundle): required lane, gitleaks, syft SBOM, grype, ratchet audit.
check:
    bash ops/ci/check.sh

# Verify is an alias of check for agents that look for a `verify` lane.
verify: check

# Lint the shell and GitHub Actions surface: the required lane (bash -n,
# shellcheck, zizmor action.yml, installer checks).
lint:
    bash ops/ci/required.sh

fmt:
    bash ops/ci/quality-gates.sh

# Run the deploy/mirror proof: the required local CI cascade.
test:
    bash scripts/ci-local.sh required

# Security lane: secret scanning (gitleaks), action lint, and script digests.
security:
    bash tools/security-lane.sh

# Jankurai self-audit lane: writes the repo-score artifacts the forge gate bundles.
# Mirrors the jankurai audit + repo-score control plane in ops/ci/audit.sh.
audit:
    mkdir -p .jankurai
    jankurai audit . --no-score-history --json .jankurai/repo-score.json --md .jankurai/repo-score.md

# Release audit gate: the artifact-backed launch gate run before tagging.
release:
    bash ops/ci/release-audit-gate.sh

# Print the declared version.
versions:
    cat VERSION
