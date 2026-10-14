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
#   - the verified binary is used only through a private copy that is
#     re-verified immediately before each audit, and prepare-baseline.sh has
#     no PATH fallback (both exercised and pinned);
#   - no script the lane executes masks a failure (pattern match);
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
# Every script the lane executes. A pattern match, not a proof: it catches
# `|| true`, `||true`, `|| true;`, `|| :`, `|| exit 0` and `set +e` outside
# comments.
lane_scripts=(ops/ci/pr-ci.sh ops/ci/check.sh ops/ci/auditor.sh ops/ci/required.sh
  ops/ci/prepare-baseline.sh ops/ci/collect-evidence.sh scripts/ci-local-lanes-test.sh
  scripts/lint-actions.sh scripts/check-vendored-installer.sh scripts/installer-selftest.sh)
masked() {
  grep -v -E '^[[:space:]]*#' "$@" |
    grep -qE '\|\|[[:space:]]*(true|:|exit[[:space:]]+0)([[:space:];)]|$)|(^|[[:space:];])set[[:space:]]+\+e'
}
not_masked() { ! masked "$1"; }
for script in "${lane_scripts[@]}"; do
  check "no step masked in $script (|| true, || :, || exit 0, set +e)" not_masked "$script"
done

auditor_users=(ops/ci/check.sh ops/ci/prepare-baseline.sh ops/ci/auditor.sh ops/ci/self-audit.sh)
no_path_auditor() {
  ! grep -v -E '^[[:space:]]*#' "${auditor_users[@]}" Justfile |
    grep -qE 'command -v jankurai|type -P jankurai|(^|[[:space:]])jankurai audit|JANKURAI:-[^}]'
}
check "no lane script or just recipe takes the auditor from PATH" no_path_auditor
# Every audit invocation runs the verified private copy and is immediately
# preceded by reverify_auditor (no line in between).
reverified() {
  awk '/"\$JANKURAI" audit/ { if (prev != "reverify_auditor") bad = 1; n++ }
       { if ($0 !~ /^[[:space:]]*$/) { p = $0; sub(/^[[:space:]]+/, "", p); prev = p } }
       END { exit (bad || n == 0) }' "$1"
}
check "check.sh re-verifies the auditor copy immediately before the head audit" reverified ops/ci/check.sh
check "prepare-baseline.sh re-verifies the auditor copy immediately before the baseline audit" \
  reverified ops/ci/prepare-baseline.sh
check "check.sh resolves the auditor through ops/ci/auditor.sh" has_line '^resolve_auditor$' ops/ci/check.sh
check "auditor.sh copies the verified binary into a private mode-700 dir under target/" \
  bash -c "grep -qF 'mktemp -d target/auditor.XXXXXX' ops/ci/auditor.sh && grep -qF 'chmod 700 \"\$auditor_dir\"' ops/ci/auditor.sh"
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
# shellcheck source=ops/ci/auditor.sh
source ops/ci/auditor.sh
fake_sha="$(file_sha256 "$fake_home/.jeryu/bin/jankurai")"
with_timeout() { if command -v timeout >/dev/null 2>&1; then timeout 30 "$@"; else "$@"; fi; }
stamp="$fake_home/.jeryu/authority/jankurai.json"
write_stamp() { printf '{"schema":"jeryu.jankurai-authority-stamp/v1","binary_sha256":"%s","version":"jankurai 0.0.0-fake"}\n' "$1" > "$stamp"; chmod 0600 "$stamp"; }
refuses() {
  local name="$1" want="$2"; shift 2
  local out status=0
  out="$(env -u JANKURAI HOME="$PWD/$fake_home" "$@" bash -c "$(declare -f with_timeout); with_timeout bash ops/ci/check.sh --identity-only" 2>&1)" || status=$?
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
accept_out="$(env -u JANKURAI HOME="$PWD/$fake_home" bash -c "$(declare -f with_timeout); with_timeout bash ops/ci/check.sh --identity-only" 2>&1)" &&
  grep -qF 'auditor identity ok: governed' <<<"$accept_out" &&
  ok "auditor check accepts a stamped, private governed install" ||
  bad "auditor check rejected a stamped, private governed install: $accept_out"

# Use-time re-verification: a copy that changed after verification is refused.
cp "$fake_home/.jeryu/bin/jankurai" "$fake_home/copy"
printf 'tampered\n' >> "$fake_home/copy"
tamper_out="$(JANKURAI="$PWD/$fake_home/copy" JANKURAI_SHA256="$fake_sha" \
  bash -c 'source ops/ci/auditor.sh; reverify_auditor' 2>&1)" &&
  bad "reverify_auditor accepted a copy that changed after verification" ||
  { grep -qF 'changed after verification' <<<"$tamper_out" &&
    ok "reverify_auditor refuses a copy that changed after verification" ||
    bad "reverify_auditor failed for the wrong reason: $tamper_out"; }
# prepare-baseline.sh has no PATH fallback: without the verified auditor it
# fails closed before scoring anything.
pb_status=0
pb_out="$(env -u JANKURAI -u JANKURAI_SHA256 bash ops/ci/prepare-baseline.sh 2>&1)" || pb_status=$?
if [[ "$pb_status" -ne 0 ]] && grep -qF 'JANKURAI/JANKURAI_SHA256 unset' <<<"$pb_out"; then
  ok "prepare-baseline.sh fails closed without the verified auditor"
else
  bad "prepare-baseline.sh did not fail closed without the verified auditor (exit $pb_status)"
fi

check "required lane lints action.yml" has_line '^bash scripts/lint-actions\.sh$' ops/ci/required.sh
check "no GitHub workflow is committed (GitHub is a publishing mirror)" \
  bash -c "! git ls-files --error-unmatch .github/workflows >/dev/null 2>&1 && [[ ! -d .github/workflows ]]"

if ((failures)); then
  printf '%s: %d check(s) failed\n' "$0" "$failures" >&2
  exit 1
fi
printf '%s: forge gate contract holds\n' "$0"
