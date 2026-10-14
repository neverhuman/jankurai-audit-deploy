#!/usr/bin/env bash
# Tripwire for the forge gate. It replaces the GitHub workflow's required-job
# aggregate, which went with the workflow. It only runs while the chain
# ci.toml -> pr-ci.sh -> check.sh -> required.sh is intact (it pins each link,
# so breaking one fails it on the change that breaks it), and its anti-masking
# check is a pattern match, not a proof. It checks:
#
#   - .jeryu/ci.toml is a schema 2 jeryu declaration whose only lane is
#     `required`, running exactly `bash ops/ci/pr-ci.sh`;
#   - the Justfile has no `required` recipe, which the forge gate would run
#     in place of ops/ci/pr-ci.sh;
#   - ops/ci/pr-ci.sh runs ops/ci/check.sh and always collects evidence;
#   - ops/ci/check.sh runs the required lane, gitleaks, the syft SBOM and the
#     ratchet audit, none of them masked;
#   - the auditor is the governed install verified against the host's
#     authority stamp: check.sh fails closed on a missing stamp, a digest
#     mismatch or a group/world-writable stamp, and pr-ci.sh refuses a
#     JANKURAI override (exercised below, not only grepped);
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

check "pr-ci.sh collects evidence on every exit" has_line '^trap collect EXIT$' ops/ci/pr-ci.sh
check "pr-ci.sh evidence collection uses the gate's exit code" \
  has_line 'bash ops/ci/collect-evidence\.sh "\$gate_exit"' ops/ci/pr-ci.sh

check "check.sh keeps errexit and pipefail" has_line '^set -euo pipefail$' ops/ci/check.sh
check "check.sh runs the required lane" has_line '^bash ops/ci/required\.sh$' ops/ci/check.sh
check "check.sh runs gitleaks over the repository" has_line '^gitleaks detect --source \. ' ops/ci/check.sh
check "check.sh writes a CycloneDX SBOM with syft" has_line '^syft dir:\. .*' ops/ci/check.sh
check "check.sh writes the SBOM to the evidence path" \
  has_line 'cyclonedx-json=target/jankurai/security/sbom\.json' ops/ci/check.sh
check "check.sh records the SBOM component count" \
  has_line 'target/jankurai/security/sbom-components\.txt' ops/ci/check.sh
check "check.sh scores protected main as the baseline" has_line '^bash ops/ci/prepare-baseline\.sh$' ops/ci/check.sh
check "check.sh runs the ratchet audit against it" \
  has_line 'audit \. --mode ratchet --baseline target/jankurai/accepted-baseline\.json' ops/ci/check.sh
check "no gate step is masked with || true or || :" \
  bash -c "! grep -nE '\|\|[[:space:]]*(true|:)([[:space:]]|$)' ops/ci/check.sh ops/ci/required.sh ops/ci/pr-ci.sh"

check "check.sh never takes the auditor from PATH" \
  bash -c "! grep -v -E '^[[:space:]]*#' ops/ci/check.sh | grep -qE 'command -v jankurai|type -P jankurai'"
check "pr-ci.sh runs check.sh with the governed auditor only" \
  has_line '^JANKURAI_REQUIRE_GOVERNED=1 bash ops/ci/check\.sh$' ops/ci/pr-ci.sh

# Exercise the auditor identity check through `check.sh --identity-only`, which
# stops after the check, so even a weakened check cannot recurse into the gate.
mkdir -p target
fake_home="$(mktemp -d target/forge-gate-test.XXXXXX)"
trap 'rm -rf "$fake_home"' EXIT
mkdir -p "$fake_home/.jeryu/bin" "$fake_home/.jeryu/authority"
printf '#!/bin/sh\necho "jankurai 0.0.0-fake"\n' > "$fake_home/.jeryu/bin/jankurai"
chmod 0700 "$fake_home/.jeryu/bin/jankurai"
fake_sha="$(sha256sum "$fake_home/.jeryu/bin/jankurai" | cut -d' ' -f1)"
stamp="$fake_home/.jeryu/authority/jankurai.json"
write_stamp() { printf '{"schema":"jeryu.jankurai-authority-stamp/v1","binary_sha256":"%s","version":"jankurai 0.0.0-fake"}\n' "$1" > "$stamp"; chmod 0600 "$stamp"; }
refuses() {
  local name="$1" want="$2"; shift 2
  local out status=0
  out="$(env -u JANKURAI HOME="$PWD/$fake_home" "$@" timeout 30 bash ops/ci/check.sh --identity-only 2>&1)" || status=$?
  if [[ "$status" -ne 0 ]] && grep -qF -- "$want" <<<"$out"; then
    ok "auditor check refuses: $name"
  else
    bad "auditor check did not refuse: $name (exit $status)"
  fi
}
refuses "missing authority stamp" "authority stamp missing"
write_stamp "$(printf '0%.0s' {1..64})"
refuses "binary digest differs from the stamp" "does not match its authority stamp"
write_stamp "$fake_sha"; chmod 0664 "$stamp"
refuses "group-writable authority stamp" "group/world-writable"
chmod 0600 "$stamp"; chmod 0777 "$fake_home/.jeryu/bin/jankurai"
refuses "world-writable governed binary" "group/world-writable"
chmod 0700 "$fake_home/.jeryu/bin/jankurai"
refuses "JANKURAI override under pr-ci" "override refused" \
  JANKURAI="$PWD/$fake_home/.jeryu/bin/jankurai" JANKURAI_REQUIRE_GOVERNED=1
accept_out="$(env -u JANKURAI HOME="$PWD/$fake_home" timeout 30 bash ops/ci/check.sh --identity-only 2>&1)" &&
  grep -qF 'auditor identity ok: governed' <<<"$accept_out" &&
  ok "auditor check accepts a stamped, private governed install" ||
  bad "auditor check rejected a stamped, private governed install: $accept_out"

check "required lane lints action.yml" has_line '^bash scripts/lint-actions\.sh$' ops/ci/required.sh
check "no GitHub workflow is committed (GitHub is a publishing mirror)" \
  bash -c "! git ls-files --error-unmatch .github/workflows >/dev/null 2>&1 && [[ ! -d .github/workflows ]]"

if ((failures)); then
  printf '%s: %d check(s) failed\n' "$0" "$failures" >&2
  exit 1
fi
printf '%s: forge gate contract holds\n' "$0"
