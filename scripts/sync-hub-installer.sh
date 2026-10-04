#!/usr/bin/env bash
# Re-copy jankurai-installer.sh from a hub checkout and refresh the vendor lock,
# so the published installer stays byte-identical to the hub's verified one.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

hub="${1:-${JANKURAI_HUB:-}}"
if [[ -z "$hub" ]]; then
  echo "usage: $0 <path to jankurai hub checkout>" >&2
  exit 2
fi
src="${hub}/jankurai-installer.sh"
lock="agent/vendor/hub-installer.lock"
[[ -f "$src" ]] || { echo "no installer at ${src}" >&2; exit 1; }

cp "$src" jankurai-installer.sh
chmod 0755 jankurai-installer.sh
sha="$(sha256sum jankurai-installer.sh | cut -d ' ' -f 1)"
commit="$(git -C "$hub" log -1 --format=%H -- jankurai-installer.sh)"
release="$(sed -n 's/^release = "\(.*\)"$/\1/p' "${hub}/family.lock")"

sed -i \
  -e "s|^sha256 = .*|sha256 = \"${sha}\"|" \
  -e "s|^source_commit = .*|source_commit = \"${commit}\"|" \
  -e "s|^family_release = .*|family_release = \"${release}\"|" \
  "$lock"
echo "synced installer from ${hub} (sha256 ${sha}, release ${release})"
