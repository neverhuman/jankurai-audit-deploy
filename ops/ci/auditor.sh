# Auditor identity for the gate, sourced by ops/ci/check.sh,
# ops/ci/prepare-baseline.sh and ops/ci/self-audit.sh.
# shellcheck shell=bash
#
# There is no in-repo version pin: the family keeps one pin of record on the
# governed host install. With JANKURAI unset, the auditor is
# $HOME/.jeryu/bin/jankurai, accepted only when its SHA-256 equals
# binary_sha256 in the host's authority stamp $HOME/.jeryu/authority/jankurai.json
# (jeryu.jankurai-authority-stamp/v1) and both files are owned by the running
# user and not group- or world-writable. JANKURAI=/path is an explicit local
# override, recorded as unverified; JANKURAI_REQUIRE_GOVERNED=1 refuses it.
#
# resolve_auditor copies the verified binary into a fresh private directory
# (mode 700) under target/ and exports JANKURAI (the copy) and JANKURAI_SHA256.
# reverify_auditor re-hashes the copy and must run immediately before every
# audit invocation. Residual risk, stated plainly: code running as the same
# user (including the pull request's own shell) can still tamper with the copy
# between the re-check and the exec, or with the stamp itself. A shell lane in
# the repository it gates cannot enforce a boundary against its own user; the
# check narrows the window and records what scored, it does not prove it.

auditor_die() { echo "auditor: $*" >&2; exit 1; }

# file_sha256 <path>: GNU sha256sum or BSD/macOS shasum.
file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | cut -d' ' -f1
  else
    auditor_die "unsupported platform: neither sha256sum nor shasum is available"
  fi
}

# file_uid_mode <path>: "<uid> <octal mode>" with GNU stat or BSD stat.
file_uid_mode() {
  local out
  if out="$(stat -c '%u %a' -- "$1" 2>/dev/null)"; then
    printf '%s\n' "$out"
  elif out="$(stat -f '%u %Lp' -- "$1" 2>/dev/null)"; then
    printf '%s\n' "$out"
  else
    return 2
  fi
}

# Fail with an explicit message, not a misleading ownership error, on a host
# where neither GNU nor BSD stat or a SHA-256 tool works.
auditor_platform_check() {
  file_uid_mode / >/dev/null ||
    auditor_die "unsupported platform: cannot read file owner and mode with GNU (stat -c) or BSD (stat -f) stat"
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
    auditor_die "unsupported platform: neither sha256sum nor shasum is available"
}

# owned_and_private <path>: regular file, not a symlink, owned by us, and not
# writable by group or others.
owned_and_private() {
  local path="$1" owner mode uid_mode
  [[ -f "$path" && ! -L "$path" ]] || return 1
  uid_mode="$(file_uid_mode "$path")" || return 1
  read -r owner mode <<<"$uid_mode"
  [[ "$owner" == "$(id -u)" ]] || return 1
  (( (8#$mode & 8#022) == 0 ))
}

resolve_auditor() {
  local governed_bin="$HOME/.jeryu/bin/jankurai"
  local authority_stamp="$HOME/.jeryu/authority/jankurai.json"
  local source_bin verified_sha actual_sha auditor_dir
  auditor_platform_check
  if [[ -n "${JANKURAI:-}" ]]; then
    [[ "${JANKURAI_REQUIRE_GOVERNED:-0}" != "1" ]] ||
      auditor_die "JANKURAI override refused: this lane scores only with the governed install ($governed_bin)"
    source_bin="$JANKURAI"
    [[ -f "$source_bin" && -x "$source_bin" ]] || auditor_die "JANKURAI is not an executable file: $source_bin"
    verified_sha="$(file_sha256 "$source_bin")"
    AUDITOR_IDENTITY="unverified local override ($source_bin)"
  else
    owned_and_private "$authority_stamp" ||
      auditor_die "authority stamp missing, not owned by $(id -un), or group/world-writable: $authority_stamp"
    owned_and_private "$governed_bin" && [[ -x "$governed_bin" ]] ||
      auditor_die "governed jankurai missing, not an executable owned by $(id -un), or group/world-writable: $governed_bin"
    [[ "$(jq -r '.schema // empty' "$authority_stamp")" == "jeryu.jankurai-authority-stamp/v1" ]] ||
      auditor_die "authority stamp has an unknown schema: $authority_stamp"
    verified_sha="$(jq -r '.binary_sha256 // empty' "$authority_stamp")"
    [[ "$verified_sha" =~ ^[0-9a-f]{64}$ ]] || auditor_die "authority stamp has no binary_sha256: $authority_stamp"
    actual_sha="$(file_sha256 "$governed_bin")"
    [[ "$actual_sha" == "$verified_sha" ]] ||
      auditor_die "governed jankurai does not match its authority stamp (have $actual_sha, stamp $verified_sha)"
    source_bin="$governed_bin"
    AUDITOR_IDENTITY="governed (sha256 matches $authority_stamp)"
  fi
  mkdir -p target
  auditor_dir="$(mktemp -d target/auditor.XXXXXX)"
  chmod 700 "$auditor_dir"
  cp -- "$source_bin" "$auditor_dir/jankurai"
  chmod 500 "$auditor_dir/jankurai"
  export AUDITOR_DIR="$auditor_dir"
  export JANKURAI="$PWD/$auditor_dir/jankurai"
  export JANKURAI_SHA256="$verified_sha"
  export AUDITOR_IDENTITY
  reverify_auditor
}

# reverify_auditor: the private copy must still hash to the verified digest.
reverify_auditor() {
  [[ -n "${JANKURAI:-}" && -n "${JANKURAI_SHA256:-}" ]] ||
    auditor_die "no verified auditor (JANKURAI and JANKURAI_SHA256 must come from resolve_auditor)"
  [[ -f "$JANKURAI" && ! -L "$JANKURAI" ]] || auditor_die "verified auditor copy is gone: $JANKURAI"
  [[ "$(file_sha256 "$JANKURAI")" == "$JANKURAI_SHA256" ]] ||
    auditor_die "verified auditor copy changed after verification: $JANKURAI"
}
