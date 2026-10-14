#!/usr/bin/env bash
# Full deployment-tooling gate. The forge runs it for every pull request head
# through ops/ci/pr-ci.sh (the `required` lane in .jeryu/ci.toml), and
# `just check` runs it locally. Assembled product proofs and releases run in
# the hub. GitHub is a publishing mirror only and runs nothing here.
#
#   1. required lane: lane contract, forge gate contract, bash -n, shellcheck,
#      action.yml lint (zizmor), vendored installer check and self-test;
#   2. secret scan of the full git history (gitleaks);
#   3. CycloneDX SBOM (syft), with its component count recorded. This repo has
#      no package manifests, so the SBOM is expected to be empty and there is
#      nothing for a vulnerability scanner to match;
#   4. jankurai ratchet audit against protected main, scored by the same
#      auditor binary, so a head cannot score below main.
#
# Auditor identity: there is no in-repo version pin (the family pin of record
# lives with the governed host install). The auditor is the governed install,
# $HOME/.jeryu/bin/jankurai, accepted only when its SHA-256 equals
# binary_sha256 in the host's authority stamp $HOME/.jeryu/authority/jankurai.json
# and both files are owned by the running user and not group- or
# world-writable. Anything else fails closed. JANKURAI=/path is an explicit
# local override, recorded as unverified; ops/ci/pr-ci.sh refuses it
# (JANKURAI_REQUIRE_GOVERNED=1).
#
# `check.sh --identity-only` runs only the auditor check and exits; the
# forge-gate test uses it so a weakened check can never recurse into the gate.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

die() { echo "check: $*" >&2; exit 1; }

# owned_and_private <path>: regular file, not a symlink, owned by us, and not
# writable by group or others.
owned_and_private() {
  local path="$1" owner mode
  [[ -f "$path" && ! -L "$path" ]] || return 1
  owner="$(stat -c '%u' -- "$path")"
  mode="$(stat -c '%a' -- "$path")"
  [[ "$owner" == "$(id -u)" ]] || return 1
  (( (8#$mode & 8#022) == 0 ))
}

governed_bin="$HOME/.jeryu/bin/jankurai"
authority_stamp="$HOME/.jeryu/authority/jankurai.json"

if [[ -n "${JANKURAI:-}" ]]; then
  [[ "${JANKURAI_REQUIRE_GOVERNED:-0}" != "1" ]] ||
    die "JANKURAI override refused: this lane scores only with the governed install ($governed_bin)"
  jankurai_bin="$JANKURAI"
  [[ -f "$jankurai_bin" && -x "$jankurai_bin" ]] || die "JANKURAI is not an executable file: $jankurai_bin"
  auditor_identity="unverified local override"
else
  owned_and_private "$authority_stamp" ||
    die "authority stamp missing, not owned by $(id -un), or group/world-writable: $authority_stamp"
  owned_and_private "$governed_bin" && [[ -x "$governed_bin" ]] ||
    die "governed jankurai missing, not an executable owned by $(id -un), or group/world-writable: $governed_bin"
  [[ "$(jq -r '.schema // empty' "$authority_stamp")" == "jeryu.jankurai-authority-stamp/v1" ]] ||
    die "authority stamp has an unknown schema: $authority_stamp"
  expected_sha="$(jq -r '.binary_sha256 // empty' "$authority_stamp")"
  [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die "authority stamp has no binary_sha256: $authority_stamp"
  actual_sha="$(sha256sum "$governed_bin" | cut -d' ' -f1)"
  [[ "$actual_sha" == "$expected_sha" ]] ||
    die "governed jankurai does not match its authority stamp (have $actual_sha, stamp $expected_sha)"
  jankurai_bin="$governed_bin"
  auditor_identity="governed (sha256 matches $authority_stamp)"
fi
if [[ "${1:-}" == "--identity-only" ]]; then
  echo "[ci] check: auditor identity ok: $auditor_identity"
  exit 0
fi
export JANKURAI="$jankurai_bin"
mkdir -p target/jankurai/security .jankurai
{
  printf 'path=%s\n' "$jankurai_bin"
  printf 'identity=%s\n' "$auditor_identity"
  printf 'version=%s\n' "$("$jankurai_bin" --version)"
  printf 'sha256=%s\n' "$(sha256sum "$jankurai_bin" | cut -d' ' -f1)"
} > target/jankurai/auditor.txt
echo "[ci] check: auditor $("$jankurai_bin" --version), $auditor_identity"

echo "[ci] check: required lane"
bash ops/ci/required.sh

echo "[ci] check: secret scan (gitleaks, full history)"
gitleaks detect --source . --no-banner --redact

echo "[ci] check: SBOM (syft)"
syft dir:. --exclude './target/**' --exclude './.git/**' --exclude './node_modules/**' \
  -o cyclonedx-json=target/jankurai/security/sbom.json
jq -e '.bomFormat == "CycloneDX"' target/jankurai/security/sbom.json >/dev/null
jq '.components // [] | length' target/jankurai/security/sbom.json \
  > target/jankurai/security/sbom-components.txt
echo "[ci] SBOM components: $(cat target/jankurai/security/sbom-components.txt)"

echo "[ci] check: protected-main baseline and ratchet audit"
bash ops/ci/prepare-baseline.sh
"$jankurai_bin" audit . --mode ratchet --baseline target/jankurai/accepted-baseline.json --full \
  --no-score-history --json .jankurai/repo-score.json --md .jankurai/repo-score.md
