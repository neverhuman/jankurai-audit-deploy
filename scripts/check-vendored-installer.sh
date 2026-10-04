#!/usr/bin/env bash
# Prove jankurai-installer.sh is still the vendored hub installer and that the
# composite action installs the family release recorded in the vendor lock.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

lock="agent/vendor/hub-installer.lock"
lock_field() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$lock"; }

expected_sha="$(lock_field sha256)"
release="$(lock_field family_release)"
[[ -n "$expected_sha" && -n "$release" ]] || { echo "${lock}: missing sha256 or family_release" >&2; exit 1; }

actual_sha="$(sha256sum jankurai-installer.sh | cut -d ' ' -f 1)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "jankurai-installer.sh was hand-edited or drifted from the hub copy:" >&2
  echo "  expected ${expected_sha}" >&2
  echo "  actual   ${actual_sha}" >&2
  echo "re-copy it with scripts/sync-hub-installer.sh <hub checkout>" >&2
  exit 1
fi

default_tag="$(sed -n 's/^tag="${JANKURAI_RELEASE_TAG:-\(v[^}]*\)}"$/\1/p' jankurai-installer.sh)"
[[ "$default_tag" == "v${release}" ]] ||
  { echo "installer default tag (${default_tag:-none}) is not the family release v${release}" >&2; exit 1; }

action_tag="$(sed -n '/^  release-tag:/,/^  [a-z]/s/^    default: "\(.*\)"$/\1/p' action.yml)"
[[ "$action_tag" == "v${release}" ]] ||
  { echo "action.yml release-tag default (${action_tag:-none}) is not the family release v${release}" >&2; exit 1; }

asset="$(JANKURAI_RELEASE_TAG="v${release}" bash jankurai-installer.sh --print-asset-name)"
case "$asset" in
  "jankurai-${release}-"*) ;;
  *) echo "installer printed an unexpected asset name for v${release}: ${asset}" >&2; exit 1 ;;
esac
echo "vendored installer matches the hub copy and targets v${release} (${asset})"
