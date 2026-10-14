#!/usr/bin/env bash
# Proves the forge gate cannot be weakened silently. It replaces the GitHub
# workflow's required-job aggregate, which went with the workflow:
#
#   - .jeryu/ci.toml is a schema 2 jeryu declaration whose only lane is
#     `required`, running exactly `bash ops/ci/pr-ci.sh`;
#   - the Justfile has no `required` recipe, which the forge gate would run
#     in place of ops/ci/pr-ci.sh;
#   - ops/ci/pr-ci.sh runs ops/ci/check.sh and always collects evidence;
#   - ops/ci/check.sh runs the required lane, gitleaks, the syft SBOM, grype
#     and the ratchet audit, none of them masked;
#   - the required lane lints action.yml, and no GitHub workflow is committed
#     (GitHub is a publishing mirror).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

failures=0
ok()  { printf 'ok: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
has_line() { grep -v -E '^[[:space:]]*#' "$2" | grep -qE "$1"; }

decl=.jeryu/ci.toml
body="$(grep -v -E '^[[:space:]]*(#|$)' "$decl")"
want='schema_version = "2"
provider = "jeryu"
[[lane]]
name = "required"
command = "bash ops/ci/pr-ci.sh"'
check "$decl declares exactly one lane: required -> bash ops/ci/pr-ci.sh" \
  test "$body" = "$want"

check "Justfile has no required recipe that would replace ops/ci/pr-ci.sh on the forge" \
  bash -c "! grep -qE '^required([[:space:]]|:)' Justfile"

check "pr-ci.sh runs ops/ci/check.sh" has_line '^bash ops/ci/check\.sh$' ops/ci/pr-ci.sh
check "pr-ci.sh collects evidence on every exit" has_line '^trap collect EXIT$' ops/ci/pr-ci.sh
check "pr-ci.sh evidence collection uses the gate's exit code" \
  has_line 'bash ops/ci/collect-evidence\.sh "\$gate_exit"' ops/ci/pr-ci.sh

check "check.sh keeps errexit and pipefail" has_line '^set -euo pipefail$' ops/ci/check.sh
check "check.sh runs the required lane" has_line '^bash ops/ci/required\.sh$' ops/ci/check.sh
check "check.sh runs gitleaks over the repository" has_line '^gitleaks detect --source \. ' ops/ci/check.sh
check "check.sh writes a CycloneDX SBOM with syft" has_line '^syft dir:\. .*' ops/ci/check.sh
check "check.sh writes the SBOM to the evidence path" \
  has_line 'cyclonedx-json=target/jankurai/security/sbom\.json' ops/ci/check.sh
check "check.sh scans the SBOM with grype --fail-on high" \
  has_line '^grype sbom:target/jankurai/security/sbom\.json --fail-on high$' ops/ci/check.sh
check "check.sh scores protected main as the baseline" has_line '^bash ops/ci/prepare-baseline\.sh$' ops/ci/check.sh
check "check.sh runs the ratchet audit against it" \
  has_line 'audit \. --mode ratchet --baseline target/jankurai/accepted-baseline\.json' ops/ci/check.sh
check "no gate step is masked with || true or || :" \
  bash -c "! grep -nE '\|\|[[:space:]]*(true|:)([[:space:]]|$)' ops/ci/check.sh ops/ci/required.sh ops/ci/pr-ci.sh"

check "required lane lints action.yml" has_line '^bash scripts/lint-actions\.sh$' ops/ci/required.sh
check "no GitHub workflow is committed (GitHub is a publishing mirror)" \
  bash -c "! git ls-files --error-unmatch .github/workflows >/dev/null 2>&1 && [[ ! -d .github/workflows ]]"

if ((failures)); then
  printf '%s: %d check(s) failed\n' "$0" "$failures" >&2
  exit 1
fi
printf '%s: forge gate contract holds\n' "$0"
