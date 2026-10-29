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
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

lock=agent/vendor/hub-installer.lock
fail() { printf 'release-tag bound: %s\n' "$*" >&2; exit 1; }
lock_field() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$lock"; }

tag="${1:-${JANKURAI_RELEASE_TAG:-}}"
[[ -n "$tag" ]] || fail 'usage: release-tag-bound.sh <tag> (or JANKURAI_RELEASE_TAG)'
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$'
[[ "$tag" =~ $TAG_RE ]] || fail "invalid version tag: $tag"

first="$(lock_field release_signer_first_tag)"
last="$(lock_field release_signer_last_tag)"
[[ "$first" =~ $TAG_RE ]] || fail "${lock}: release_signer_first_tag is missing or not a version tag"
[[ "$last" =~ $TAG_RE ]] ||
  fail "${lock}: release_signer_last_tag is missing or not a version tag; the key pin must never be open-ended"

version_number() {
  local major minor patch
  IFS=. read -r major minor patch <<< "${1#v}"
  patch="${patch%%[!0-9]*}"
  printf '%d' $(( 10#$major * 1000000 + 10#$minor * 1000 + 10#$patch ))
}

(( $(version_number "$first") <= $(version_number "$last") )) ||
  fail "${lock}: release_signer_first_tag ${first} is newer than release_signer_last_tag ${last}"

# The keyless era: no key pin covers these tags, so the bound does not apply.
if (( $(version_number "$tag") <= $(version_number v1.7.1) )); then
  printf 'release-tag bound: %s predates key signing; the installer verifies it keyless\n' "$tag"
  exit 0
fi
(( $(version_number "$tag") >= $(version_number "$first") )) ||
  fail "$tag is key-signed but older than the pinned key's first release ${first}"
(( $(version_number "$tag") <= $(version_number "$last") )) ||
  fail "$tag is beyond the releases the pinned release key has signed (${first} to ${last}): extend ${lock} in a reviewed change before installing it"
printf 'release-tag bound: %s is within the reviewed release-key range %s to %s\n' "$tag" "$first" "$last"
