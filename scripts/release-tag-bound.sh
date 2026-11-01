#!/usr/bin/env bash
# Bound the release-key pin to exactly the releases the key has signed.
#
# jankurai-installer.sh is the hub's bytes, byte-locked by
# scripts/check-vendored-installer.sh, and the hub leaves its release_keys line
# open-ended (`...|v1.7.2|`), so the installer alone would accept any future
# key-signed tag on the strength of a key nobody has reviewed for it. This
# repository publishes that installer with its own Action, so it closes the
# range itself: a key-signed tag is installed only when it lies inside
# [release_signer_first_tag, release_signer_last_tag] from
# agent/vendor/hub-installer.lock, the reviewed record of what the vendored key
# has signed. A newer tag fails closed here, before anything is downloaded,
# until a reviewed lock change extends the range or rotates the key.
#
# Tags up to v1.7.1 are keyless; the installer verifies them against a Sigstore
# workflow identity and no key pin applies, so they pass through.
#
# Tag grammar and ordering are exact, and deliberately narrower than the
# installer's (docs/decisions/0002-exact-release-tag-bound.md):
#   * accepted: vMAJOR.MINOR.PATCH with an optional -alpha.N, -beta.N or -rc.N
#     pre-release; no leading zeros, at most 9 digits per number.
#   * refused: every other suffix (v1.7.5abc, v1.7.5.1, v1.7.5+build,
#     v1.7.5-rc1, v1.7.5-RC.1), which the installer's wider pattern would
#     otherwise let this script truncate down to a covered release.
#   * ordering compares (major, minor, patch, pre-release) field by field, so
#     no two distinct tags can compare equal (the packed-number form made
#     v1.6.1001 equal v1.7.1), and a pre-release sorts below its own release.
# Narrower is always fail-closed: a tag this script refuses is never installed,
# and a tag it accepts is one the installer would also parse.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

lock=agent/vendor/hub-installer.lock
fail() { printf 'release-tag bound: %s\n' "$*" >&2; exit 1; }
lock_field() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$lock"; }

# The last keyless release. Tags at or below it carry no key pin: the installer
# verifies them against a Sigstore workflow identity instead. It must stay the
# same release the installer switches on; scripts/release-tag-bound-test.sh
# reads both and fails if they drift apart.
keyless_last=v1.7.1

NUM='(0|[1-9][0-9]{0,8})'
TAG_RE="^v${NUM}\\.${NUM}\\.${NUM}(-(alpha|beta|rc)\\.${NUM})?\$"

tag="${1:-${JANKURAI_RELEASE_TAG:-}}"
[[ -n "$tag" ]] || fail 'usage: release-tag-bound.sh <tag> (or JANKURAI_RELEASE_TAG)'
[[ "$tag" =~ $TAG_RE ]] ||
  fail "invalid version tag: $tag (vMAJOR.MINOR.PATCH with an optional -alpha.N, -beta.N or -rc.N pre-release)"

first="$(lock_field release_signer_first_tag)"
last="$(lock_field release_signer_last_tag)"
[[ "$first" =~ $TAG_RE ]] || fail "${lock}: release_signer_first_tag is missing or not a version tag"
[[ "$last" =~ $TAG_RE ]] ||
  fail "${lock}: release_signer_last_tag is missing or not a version tag; the key pin must never be open-ended"

# Order key for a tag: major, minor, patch, pre-release rank, pre-release
# number. A release ranks above every pre-release of itself (rank 3).
tag_key() { # tag_key <tag>; sets TAG_KEY
  local core="${1#v}" pre='' rank=3 num=0 major minor patch
  if [[ "$core" == *-* ]]; then
    pre="${core#*-}"
    core="${core%%-*}"
    case "${pre%%.*}" in
      alpha) rank=0 ;;
      beta) rank=1 ;;
      rc) rank=2 ;;
      *) fail "unknown pre-release kind in $1" ;;
    esac
    num="${pre#*.}"
  fi
  IFS=. read -r major minor patch <<< "$core"
  TAG_KEY=("$((10#$major))" "$((10#$minor))" "$((10#$patch))" "$rank" "$((10#$num))")
}

tag_le() { # tag_le <a> <b>: true when a is not newer than b
  local -a a b
  tag_key "$1"; a=("${TAG_KEY[@]}")
  tag_key "$2"; b=("${TAG_KEY[@]}")
  local i
  for i in 0 1 2 3 4; do
    if (( a[i] < b[i] )); then return 0; fi
    if (( a[i] > b[i] )); then return 1; fi
  done
  return 0
}

tag_le "$first" "$last" ||
  fail "${lock}: release_signer_first_tag ${first} is newer than release_signer_last_tag ${last}"

# The keyless era: no key pin covers these tags, so the bound does not apply.
if tag_le "$tag" "$keyless_last"; then
  printf 'release-tag bound: %s predates key signing; the installer verifies it keyless\n' "$tag"
  exit 0
fi
tag_le "$first" "$tag" ||
  fail "$tag is key-signed but older than the pinned key's first release ${first}"
tag_le "$tag" "$last" ||
  fail "$tag is beyond the releases the pinned release key has signed (${first} to ${last}): extend ${lock} in a reviewed change before installing it"
printf 'release-tag bound: %s is within the reviewed release-key range %s to %s\n' "$tag" "$first" "$last"
