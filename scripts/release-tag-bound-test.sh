#!/usr/bin/env bash
# Proves scripts/release-tag-bound.sh closes the release-key range: it accepts
# the releases the vendored key has signed, lets the keyless tags through, and
# refuses anything beyond the reviewed range or with no range at all. It also
# proves the parser is exact: every tag outside the pre-release policy is
# refused rather than truncated to a covered release, no two distinct tags
# compare equal, and the keyless cut-off still equals the installer's. Range
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

stage() { # stage <last tag or "none"> [first tag]
  rm -rf "$work/repo"
  mkdir -p "$work/repo/scripts" "$work/repo/agent/vendor"
  cp "$repo_root/scripts/release-tag-bound.sh" "$work/repo/scripts/"
  cp "$repo_root/agent/vendor/hub-installer.lock" "$work/repo/agent/vendor/"
  if [[ "$1" == none ]]; then
    sed -i '/^release_signer_last_tag = /d' "$work/repo/agent/vendor/hub-installer.lock"
  else
    sed -i "s/^release_signer_last_tag = .*/release_signer_last_tag = \"$1\"/" "$work/repo/agent/vendor/hub-installer.lock"
  fi
  if [[ -n "${2:-}" ]]; then
    sed -i "s/^release_signer_first_tag = .*/release_signer_first_tag = \"$2\"/" "$work/repo/agent/vendor/hub-installer.lock"
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

# The pre-release policy: only -alpha.N, -beta.N and -rc.N are version tags, and
# a pre-release sorts below its own release. One of a covered patch is inside
# the range; one past it is not, and one of the key's first release is not
# covered either, because the key signed that release and not its candidates.
accepts "$repo_root" v1.7.5-rc.1 'within the reviewed release-key range'
accepts "$repo_root" v1.7.4-beta.2 'within the reviewed release-key range'
accepts "$repo_root" v1.7.3-alpha.1 'within the reviewed release-key range'
refuses "$repo_root" v1.7.6-rc.1 'beyond the releases the pinned release key has signed'
refuses "$repo_root" v1.7.2-rc.1 "older than the pinned key's first release"
accepts "$repo_root" v1.7.1-rc.1 'predates key signing'

# Malformed tags are refused outright, never truncated down to a covered
# release. Each of these matches the installer's wider pattern (or looks close
# enough to pass a sloppy parser) and would have been read as a covered release
# by the old `patch="${patch%%[!0-9]*}"` parser.
for malformed in v1.7.5abc v1.7.5.1 v1.7.5.99 v1.7.5+build.1 v1.7.5- v1.7.5-rc \
  v1.7.5-rc1 v1.7.5-RC.1 v1.7.5-rc.01 v1.7.5-dev.1 v1.7.5-rc.1.evil v01.7.5 \
  v1.07.5 v1.7.05 v1.7 v1.7.5.0-rc.1 v1.7.9999999999 ' v1.7.5' 'v1.7.5 ' \
  'v1.7.5;rm -rf .' v1.7.5/../../etc --tag 1.7.5; do
  refuses "$repo_root" "$malformed" 'invalid version tag'
done

# No two distinct tags compare equal. The packed form major*1000000 +
# minor*1000 + patch gave v1.7.1001 and v1.8.1 the same number, so a lock that
# stops at v1.7.1001 accepted v1.8.1, three minor releases past the key's work.
repo="$(stage v1.7.1001)"
accepts "$repo" v1.7.1001 'v1.7.2 to v1.7.1001'
accepts "$repo" v1.7.1000 'v1.7.2 to v1.7.1001'
refuses "$repo" v1.8.1 'beyond the releases the pinned release key has signed'
refuses "$repo" v1.8.0 'beyond the releases the pinned release key has signed'
# The same collision at the other end of the range: v1.7.1001 packed to v1.8.1's
# number, so a key whose first release is v1.7.1001 appeared to cover v1.7.1000
# as well.
repo="$(stage v1.8.1 v1.7.1001)"
accepts "$repo" v1.8.1 'v1.7.1001 to v1.8.1'
accepts "$repo" v1.7.1001 'v1.7.1001 to v1.8.1'
refuses "$repo" v1.7.1000 "older than the pinned key's first release"

# The keyless cut-off is the installer's authority: the bound must switch at the
# same release the vendored installer switches at, or a key-signed tag could be
# waved through as keyless (or the reverse).
bound_keyless="$(sed -n 's/^keyless_last=\(v[0-9.]*\)$/\1/p' "$repo_root/scripts/release-tag-bound.sh")"
installer_keyless="$(sed -n 's/.*version_number "\$tag") > \$(version_number \(v[0-9.]*\)).*/\1/p' "$repo_root/jankurai-installer.sh")"
if [[ -n "$bound_keyless" && "$bound_keyless" == "$installer_keyless" ]]; then
  ok "the keyless cut-off matches the vendored installer ($bound_keyless)"
else
  bad "keyless cut-off drift: bound ${bound_keyless:-none}, installer ${installer_keyless:-none}"
fi

# A lock whose range ends outside the policy is a broken pin, not a licence.
repo="$(stage v1.7.5-rc)"
refuses "$repo" v1.7.5 'release_signer_last_tag is missing or not a version tag'
repo="$(stage v1.7.5abc)"
refuses "$repo" v1.7.5 'release_signer_last_tag is missing or not a version tag'

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
