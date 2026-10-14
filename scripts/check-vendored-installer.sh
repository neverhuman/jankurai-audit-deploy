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

# The release-key pin: the vendored public key, the lock and the installer's
# release_keys table must all name the same SHA-256. The key file itself is the
# hub's committed release-keys/ file (see the lock); the mandatory hub comparison
# below proves that, byte for byte, at release_signer_source_commit.
key_name="$(lock_field release_signer_name)"
key_path="$(lock_field release_signer_path)"
key_sha="$(lock_field release_signer_sha256)"
key_first="$(lock_field release_signer_first_tag)"
key_source_path="$(lock_field release_signer_source_path)"
key_source_commit="$(lock_field release_signer_source_commit)"
for field in key_name key_path key_sha key_first key_source_path key_source_commit; do
  [[ -n "${!field}" ]] || { echo "${lock}: missing release_${field}" >&2; exit 1; }
done
[[ "$key_sha" =~ ^[0-9a-f]{64}$ && "$key_sha" != "$(printf '0%.0s' {1..64})" ]] ||
  { echo "${lock}: release_signer_sha256 must be a real 64-hex SHA-256" >&2; exit 1; }
[[ -f "$key_path" && ! -L "$key_path" ]] || { echo "vendored release key ${key_path} is missing" >&2; exit 1; }
head -n 1 "$key_path" | grep -qx -- '-----BEGIN PUBLIC KEY-----' ||
  { echo "${key_path} is not a PEM public key" >&2; exit 1; }
actual_key_sha="$(sha256sum "$key_path" | cut -d ' ' -f 1)"
[[ "$actual_key_sha" == "$key_sha" ]] ||
  { echo "${key_path} sha256 ${actual_key_sha} != lock release_signer_sha256 ${key_sha}" >&2; exit 1; }
# The installer's whole release_keys table must equal the lock's
# release_signers_table, line for line, so no key can be added and no range closed
# or moved without a reviewable lock change. Every key in it must be vendored
# with the SHA-256 its line pins, and the lock's current key must be in it with
# its first tag and an open range.
installer_table="$(sed -n "/^release_keys='\$/,/^'\$/{/^release_keys='\$/d;/^'\$/d;/^\$/d;p}" jankurai-installer.sh)"
lock_table="$(sed -n '/^release_signers_table = \[/,/^\]/s/^ *"\(.*\)",\{0,1\}$/\1/p' "$lock")"
[[ -n "$lock_table" ]] || { echo "${lock}: missing release_signers_table" >&2; exit 1; }
[[ "$installer_table" == "$lock_table" ]] || {
  echo "jankurai-installer.sh release_keys table differs from ${lock} release_signers_table:" >&2
  diff <(printf '%s\n' "$lock_table") <(printf '%s\n' "$installer_table") >&2 || true
  exit 1
}
while IFS='|' read -r name sha _; do
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.pub$ && "$sha" =~ ^[0-9a-f]{64}$ ]] ||
    { echo "release_signers_table: malformed line for ${name:-?}" >&2; exit 1; }
  vendored="agent/vendor/release-keys/${name}"
  [[ -f "$vendored" && ! -L "$vendored" ]] || { echo "release key ${name} is pinned but ${vendored} is missing" >&2; exit 1; }
  [[ "$(sha256sum "$vendored" | cut -d ' ' -f 1)" == "$sha" ]] ||
    { echo "${vendored} sha256 != its release_signers_table pin ${sha}" >&2; exit 1; }
done <<< "$lock_table"
# Every vendored file must be pinned by name. Names are compared as fixed
# strings (field 1 of each table line), never as patterns, and an empty
# directory is an empty list rather than a literal glob.
pinned_names="$(cut -d '|' -f 1 <<< "$lock_table")"
shopt -s nullglob dotglob
vendored_keys=(agent/vendor/release-keys/*)
shopt -u nullglob dotglob
for vendored in "${vendored_keys[@]}"; do
  grep -qxF -- "$(basename "$vendored")" <<< "$pinned_names" ||
    { echo "${vendored} is vendored but not pinned in release_signers_table" >&2; exit 1; }
done
current="$(awk -F'|' -v name="$key_name" '$1 == name' <<< "$lock_table")"
[[ "$current" == "${key_name}|${key_sha}|${key_first}|" ]] ||
  { echo "release_signers_table must pin ${key_name} as ${key_sha} from ${key_first}, open-ended; it has: ${current:-nothing}" >&2; exit 1; }

# The cross-repository proof, mandatory: the installer and every vendored key
# must be the hub's bytes at the commits the lock names, and those commits must
# be on the hub's main branch (scripts/hub-source.sh says where the hub comes
# from). Without it the checks above only prove these files agree with each
# other, which a coherent swap of installer pin, lock and key file would pass.
# No hub means failure. The one opt-out, JANKURAI_HUB_CHECK=local-dev-skip, is
# for offline local development; the required lane (ops/ci/required.sh) unsets
# it, so it can never make a gate pass.
installer_commit="$(lock_field source_commit)"
installer_source="$(lock_field source_path)"
[[ "$installer_commit" =~ ^[0-9a-f]{40}$ && "$key_source_commit" =~ ^[0-9a-f]{40}$ && -n "$installer_source" ]] ||
  { echo "${lock}: source_commit and release_signer_source_commit must be full commit ids, source_path set" >&2; exit 1; }
if [[ "${JANKURAI_HUB_CHECK:-}" == local-dev-skip ]]; then
  echo "WARNING: hub comparison SKIPPED (JANKURAI_HUB_CHECK=local-dev-skip). The required lane never honours this." >&2
  hub_note="HUB COMPARISON SKIPPED for local development"
else
  [[ -z "${JANKURAI_HUB_CHECK:-}" ]] ||
    { echo "JANKURAI_HUB_CHECK=${JANKURAI_HUB_CHECK} is not recognised (only local-dev-skip, outside the required lane)" >&2; exit 1; }
  # shellcheck source=scripts/hub-source.sh
  source scripts/hub-source.sh
  hub_scratch="$(mktemp -d)"
  trap 'rm -rf "$hub_scratch"' EXIT
  # The hub is fixed in scripts/hub-source.sh (HUB_REPO), never taken from this
  # PR-editable lock; the lock must agree with it.
  [[ "$(lock_field source_repo)" == "$HUB_REPO" ]] ||
    { echo "${lock}: source_repo must be ${HUB_REPO}; the hub is fixed in scripts/hub-source.sh, not chosen by the lock" >&2; exit 1; }
  hub="$(hub_resolve "$hub_scratch" "$installer_commit" "$key_source_commit")" ||
    { echo "hub comparison could not run, so the vendored trust material is unverified: failing closed" >&2; exit 1; }
  hub_file() { git -C "$hub" show "$1:$2" 2>/dev/null; }
  cmp -s <(hub_file "$installer_commit" "$installer_source") jankurai-installer.sh ||
    { echo "jankurai-installer.sh differs from the hub's ${installer_source} at ${installer_commit}" >&2; exit 1; }
  cmp -s <(hub_file "$key_source_commit" "$key_source_path") "$key_path" ||
    { echo "${key_path} differs from the hub's ${key_source_path} at ${key_source_commit}" >&2; exit 1; }
  # Every key the installer pins was committed in the hub by the installer's
  # own commit, so each vendored key must equal the hub's file there.
  for vendored in "${vendored_keys[@]}"; do
    cmp -s <(hub_file "$installer_commit" "release-keys/$(basename "$vendored")") "$vendored" ||
      { echo "${vendored} differs from the hub's release-keys/$(basename "$vendored") at ${installer_commit}" >&2; exit 1; }
  done
  # Currency, not just ancestry: the installer and every vendored key must also
  # be the hub's current files at the tip of its main. A hub that has since
  # revoked a key or changed the installer makes this fail until the repository
  # re-syncs, so an old main commit can never keep a revoked key trusted here.
  hub_tip="$(hub_main_ref "$hub")"
  cmp -s <(hub_file "$hub_tip" "$installer_source") jankurai-installer.sh ||
    { echo "jankurai-installer.sh is not the hub's current ${installer_source} on main: re-sync with scripts/sync-hub-installer.sh" >&2; exit 1; }
  for vendored in "${vendored_keys[@]}"; do
    cmp -s <(hub_file "$hub_tip" "release-keys/$(basename "$vendored")") "$vendored" ||
      { echo "${vendored} is not the hub's current release-keys/$(basename "$vendored") on main: re-sync with scripts/sync-hub-installer.sh" >&2; exit 1; }
  done
  hub_note="installer and ${#vendored_keys[@]} release key(s) are byte-identical to the hub at the locked commits (${installer_commit:0:12}, ${key_source_commit:0:12}), which are on hub main, and to the hub's current files at the tip of main ($(git -C "$hub" rev-parse --short=12 "$hub_tip"))"
fi

default_tag="$(sed -n 's/^tag="${JANKURAI_RELEASE_TAG:-\(v[^}]*\)}"$/\1/p' jankurai-installer.sh)"
[[ "$default_tag" == "v${release}" ]] ||
  { echo "installer default tag (${default_tag:-none}) is not the family release v${release}" >&2; exit 1; }

# action.yml and the documented install command point at the newest release
# that is actually published (published_release), which trails family_release
# until the hub publishes the family release; then both move together.
published="$(lock_field published_release)"
[[ "$published" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "${lock}: missing published_release" >&2; exit 1; }
[[ "$(printf '%s\n%s\n' "$published" "$release" | sort -V | tail -n 1)" == "$release" ]] ||
  { echo "${lock}: published_release ${published} is newer than family_release ${release}" >&2; exit 1; }
action_tag="$(sed -n '/^  release-tag:/,/^  [a-z]/s/^    default: "\(.*\)"$/\1/p' action.yml)"
[[ "$action_tag" == "v${published}" ]] ||
  { echo "action.yml release-tag default (${action_tag:-none}) is not the published release v${published}" >&2; exit 1; }
grep -qF "/releases/download/v${published}/jankurai-installer.sh" docs/install.md ||
  { echo "docs/install.md does not install the published release v${published}" >&2; exit 1; }

asset="$(JANKURAI_RELEASE_TAG="v${release}" bash jankurai-installer.sh --print-asset-name)"
case "$asset" in
  "jankurai-${release}-"*) ;;
  *) echo "installer printed an unexpected asset name for v${release}: ${asset}" >&2; exit 1 ;;
esac
echo "vendored installer matches its lock, pins exactly the locked release_keys table (${key_name} ${key_sha} from ${key_first}), defaults to v${release} (${asset}); action.yml installs published v${published}; ${hub_note}"
