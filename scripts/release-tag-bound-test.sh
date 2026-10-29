#!/usr/bin/env bash
# Proves scripts/release-tag-bound.sh closes the release-key range: it accepts
# the releases the vendored key has signed, lets the keyless tags through, and
# refuses anything beyond the reviewed range or with no range at all. Range
# cases run against a scratch copy of the repository's trust material, so the
# committed lock is never modified.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo_root="$PWD"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0
ok()  { printf 'ok: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

bound() { bash "$1/scripts/release-tag-bound.sh" "$2" 2>&1; }

stage() { # stage <last tag or "none">
  rm -rf "$work/repo"
  mkdir -p "$work/repo/scripts" "$work/repo/agent/vendor"
  cp "$repo_root/scripts/release-tag-bound.sh" "$work/repo/scripts/"
  cp "$repo_root/agent/vendor/hub-installer.lock" "$work/repo/agent/vendor/"
  if [[ "$1" == none ]]; then
    sed -i '/^release_signer_last_tag = /d' "$work/repo/agent/vendor/hub-installer.lock"
  else
    sed -i "s/^release_signer_last_tag = .*/release_signer_last_tag = \"$1\"/" "$work/repo/agent/vendor/hub-installer.lock"
  fi
  printf '%s\n' "$work/repo"
}

accepts() { # accepts <repo> <tag> <message>
  local out
  if out="$(bound "$1" "$2")"; then
    grep -qF -- "$3" <<< "$out" && ok "accepts $2" ||
      bad "accepted $2 for the wrong reason: $out"
  else
    bad "refused $2, which the reviewed range covers: $out"
  fi
}
refuses() { # refuses <repo> <tag> <message>
  local out
  if out="$(bound "$1" "$2")"; then
    bad "accepted $2, which must be refused: $out"
  else
    grep -qF -- "$3" <<< "$out" && ok "refuses $2" ||
      bad "refused $2 for the wrong reason: $out"
  fi
}

# The committed lock: the real range this repository ships.
accepts "$repo_root" v1.7.2 'within the reviewed release-key range'
accepts "$repo_root" v1.7.5 'within the reviewed release-key range'
accepts "$repo_root" v1.7.1 'predates key signing'
accepts "$repo_root" v1.0.0 'predates key signing'
refuses "$repo_root" v1.7.6 'beyond the releases the pinned release key has signed'
refuses "$repo_root" v1.8.0 'beyond the releases the pinned release key has signed'
refuses "$repo_root" v2.0.0 'beyond the releases the pinned release key has signed'
refuses "$repo_root" 1.7.5 'invalid version tag'
refuses "$repo_root" 'v1.7.5/../../etc' 'invalid version tag'
refuses "$repo_root" '--tag' 'invalid version tag'

# A range the lock stops earlier: the releases past it fail closed.
repo="$(stage v1.7.3)"
accepts "$repo" v1.7.3 'v1.7.2 to v1.7.3'
refuses "$repo" v1.7.4 'v1.7.2 to v1.7.3'

# No range at all is the open-ended pin the hub installer alone would accept.
repo="$(stage none)"
refuses "$repo" v1.7.5 'never be open-ended'

# A range whose ends are the wrong way round is a broken pin, not a licence.
repo="$(stage v1.7.1)"
refuses "$repo" v1.7.5 'is newer than release_signer_last_tag'

# A pre-release of a covered patch is inside the range; one past it is not.
accepts "$repo_root" v1.7.5-rc.1 'within the reviewed release-key range'
refuses "$repo_root" v1.7.6-rc.1 'beyond the releases the pinned release key has signed'

status=0
out="$(cd "$repo_root" && JANKURAI_RELEASE_TAG=v1.7.5 bash scripts/release-tag-bound.sh 2>&1)" || status=$?
[[ "$status" -eq 0 ]] && ok "reads JANKURAI_RELEASE_TAG when no argument is given" ||
  bad "JANKURAI_RELEASE_TAG was not honoured: $out"
status=0
out="$(cd "$repo_root" && env -u JANKURAI_RELEASE_TAG bash scripts/release-tag-bound.sh 2>&1)" || status=$?
[[ "$status" -ne 0 ]] && ok "no tag at all is refused" || bad "an empty tag was accepted: $out"

if ((failures)); then
  printf '%s: %d check(s) failed\n' "$0" "$failures" >&2
  exit 1
fi
printf 'release-tag bound: range holds (%s)\n' "$(sed -n 's/^release_signer_last_tag = "\(.*\)"$/closed at \1/p' agent/vendor/hub-installer.lock)"
