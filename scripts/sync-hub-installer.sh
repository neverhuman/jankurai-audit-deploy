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

# Release-key names come from the hub installer's release_keys table. Each one
# must be a plain file name (no "/", no leading dot: the same rule
# check-vendored-installer.sh applies) before it is
# used in any path, so a table line can never read or write outside
# release-keys/.
valid_key_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.pub$ ]]; }

while IFS='|' read -r name _; do
  valid_key_name "$name" || { echo "the hub installer's release_keys table names ${name:-?}, which is not a plain .pub file name; nothing was synced" >&2; exit 1; }
done < <(sed -n "/^release_keys='\$/,/^'\$/{/^release_keys='\$/d;/^'\$/d;/^\$/d;p}" "$src")

cp "$src" jankurai-installer.sh
chmod 0755 jankurai-installer.sh
sha="$(sha256sum jankurai-installer.sh | cut -d ' ' -f 1)"
commit="$(git -C "$hub" log -1 --format=%H -- jankurai-installer.sh)"
release="$(sed -n 's/^release = "\(.*\)"$/\1/p' "${hub}/family.lock")"

# The release key the installer pins comes from the hub's release-keys/ too.
key_name="$(sed -n 's/^release_signer_name = "\(.*\)"$/\1/p' "$lock")"
valid_key_name "$key_name" || { echo "${lock}: release_signer_name ${key_name:-?} is not a plain .pub file name" >&2; exit 1; }
key_src="${hub}/release-keys/${key_name}"
[[ -f "$key_src" && ! -L "$key_src" ]] || { echo "no release key ${key_name} in ${hub}/release-keys" >&2; exit 1; }
mkdir -p agent/vendor/release-keys
cp "$key_src" "agent/vendor/release-keys/${key_name}"
key_sha="$(sha256sum "agent/vendor/release-keys/${key_name}" | cut -d ' ' -f 1)"
key_commit="$(git -C "$hub" log -1 --format=%H -- "release-keys/${key_name}")"
key_first="$(awk -F'|' -v name="$key_name" '$1 == name { print $3 }' jankurai-installer.sh)"

sed -i \
  -e "s|^release_signer_sha256 = .*|release_signer_sha256 = \"${key_sha}\"|" \
  -e "s|^release_signer_source_commit = .*|release_signer_source_commit = \"${key_commit}\"|" \
  -e "s|^release_signer_first_tag = .*|release_signer_first_tag = \"${key_first}\"|" \
  -e "s|^sha256 = .*|sha256 = \"${sha}\"|" \
  -e "s|^source_commit = .*|source_commit = \"${commit}\"|" \
  -e "s|^family_release = .*|family_release = \"${release}\"|" \
  "$lock"
# Record the installer's whole release_keys table in the lock, line for line,
# vendor every key it pins (a rotation pins more than one), and remove vendored
# keys the table no longer pins, so the tree always passes its own check.
table="$(sed -n "/^release_keys='\$/,/^'\$/{/^release_keys='\$/d;/^'\$/d;/^\$/d;p}" jankurai-installer.sh)"
pinned=()
while IFS='|' read -r name _; do
  valid_key_name "$name" || { echo "the installer's release_keys table names ${name:-?}, which is not a plain .pub file name" >&2; exit 1; }
  [[ -f "${hub}/release-keys/${name}" && ! -L "${hub}/release-keys/${name}" ]] ||
    { echo "the installer pins ${name}, which is not in ${hub}/release-keys" >&2; exit 1; }
  cp "${hub}/release-keys/${name}" "agent/vendor/release-keys/${name}"
  pinned+=("$name")
done <<< "$table"
shopt -s nullglob dotglob
for vendored in agent/vendor/release-keys/*; do
  keep=false
  for name in "${pinned[@]}"; do [[ "$(basename "$vendored")" == "$name" ]] && keep=true; done
  "$keep" || { rm -f -- "$vendored"; echo "removed ${vendored}: no longer pinned by the hub installer"; }
done
shopt -u nullglob dotglob
awk -v table="$table" '
  /^release_signers_table = \[/ { print; n = split(table, rows, "\n"); for (i = 1; i <= n; i++) printf "  \"%s\",\n", rows[i]; skip = 1; next }
  skip && /^\]/ { skip = 0 }
  !skip { print }
' "$lock" > "$lock.tmp" && mv "$lock.tmp" "$lock"

echo "synced installer from ${hub} (sha256 ${sha}, release ${release}, ${key_name} ${key_sha})"
JANKURAI_HUB="$hub" bash scripts/check-vendored-installer.sh
