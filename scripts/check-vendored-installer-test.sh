#!/usr/bin/env bash
# Negative proof for scripts/check-vendored-installer.sh. Two kinds of change
# must fail it:
#   - drift: the installer pin, the lock and the vendored key files disagreeing
#     with each other in any way;
#   - a coherent swap: all three replaced together with a fresh key, which is
#     self-consistent, so only the mandatory comparison with the hub's bytes on
#     hub main can catch it.
# It also proves that comparison fails closed (no hub, a hub without the locked
# commits, a commit off hub main) and that scripts/sync-hub-installer.sh refuses
# unsafe key names and prunes retired keys.
# Each case runs on a scratch copy; the repository is never modified. The hub is
# resolved once, exactly as the check resolves it (scripts/hub-source.sh), and
# this test fails if it cannot be.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo_root="$PWD"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
lock_value() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$repo_root/agent/vendor/hub-installer.lock"; }
other_sha="$(printf '%s' other | sha256sum | cut -d ' ' -f 1)"
pin_sha="$(lock_value release_signer_sha256)"
installer_commit="$(lock_value source_commit)"
key_commit="$(lock_value release_signer_source_commit)"

# shellcheck source=scripts/hub-source.sh
source scripts/hub-source.sh
hub="$(hub_resolve "$work" "$installer_commit" "$key_commit")" ||
  { echo "FAIL: the hub could not be resolved, so the hub comparison cannot be proven" >&2; exit 1; }
hub="$(cd "$hub" && pwd)"
export JANKURAI_HUB="$hub"
unset JANKURAI_HUB_CHECK JANKURAI_HUB_URL

stage() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/scripts" "$work/repo/agent/vendor/release-keys"
  mkdir -p "$work/repo/docs"
  cp "$repo_root/scripts/check-vendored-installer.sh" "$repo_root/scripts/hub-source.sh" \
    "$repo_root/scripts/sync-hub-installer.sh" "$work/repo/scripts/"
  cp "$repo_root/jankurai-installer.sh" "$repo_root/action.yml" "$work/repo/"
  cp "$repo_root/docs/install.md" "$work/repo/docs/"
  cp "$repo_root/agent/vendor/hub-installer.lock" "$work/repo/agent/vendor/"
  cp "$repo_root"/agent/vendor/release-keys/*.pub "$work/repo/agent/vendor/release-keys/"
}
relock() { # keep the installer sha256 in the lock current after a tamper
  local sha
  sha="$(sha256sum "$work/repo/jankurai-installer.sh" | cut -d ' ' -f 1)"
  sed -i "s|^sha256 = .*|sha256 = \"${sha}\"|" "$work/repo/agent/vendor/hub-installer.lock"
}
expect_fail() {
  local label="$1" message="$2" output
  if output="$(bash "$work/repo/scripts/check-vendored-installer.sh" 2>&1 < /dev/null)"; then
    echo "FAIL: ${label}: the check passed" >&2; exit 1
  fi
  grep -qF -- "$message" <<< "$output" ||
    { echo "FAIL: ${label}: expected '${message}', got: ${output}" >&2; exit 1; }
  echo "... ${label}"
}

stage
bash "$work/repo/scripts/check-vendored-installer.sh" >/dev/null || { echo "FAIL: the unmodified copy does not pass" >&2; exit 1; }
echo "... the unmodified copy passes"

stage; sed -i "s/|${pin_sha}|/|${other_sha}|/" "$work/repo/jankurai-installer.sh"; relock
expect_fail 'a swapped installer pin with a refreshed lock sha256 is refused' 'release_keys table differs'

stage; sed -i "s/^release_signer_sha256 = .*/release_signer_sha256 = \"${other_sha}\"/" "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'a lock hash that is not the vendored key is refused' '!= lock release_signer_sha256'

stage; sed -i "s/|${pin_sha}|/|${other_sha}|/" "$work/repo/jankurai-installer.sh"; relock
sed -i "s/^release_signer_sha256 = .*/release_signer_sha256 = \"${other_sha}\"/" "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'a pin and lock moved together without the key file are refused' '!= lock release_signer_sha256'

stage; printf 'tampered\n' >> "$work/repo/agent/vendor/release-keys/jankurai-release-2026.pub"
expect_fail 'an edited vendored key is refused' '!= lock release_signer_sha256'

stage; sed -i "s/|${pin_sha}|v1\.7\.2|/|${pin_sha}|v1.7.3|/" "$work/repo/jankurai-installer.sh"; relock
expect_fail 'a moved first tag is refused' 'release_keys table differs'

stage; sed -i "s/|${pin_sha}|/|$(printf '0%.0s' {1..64})|/" "$work/repo/jankurai-installer.sh"; relock
sed -i "s/^release_signer_sha256 = .*/release_signer_sha256 = \"$(printf '0%.0s' {1..64})\"/" "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'an all-zero placeholder pin is refused' 'real 64-hex'

stage; sed -i "s/^jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\$/&\nattacker.pub|${other_sha}|v1.7.4|/" "$work/repo/jankurai-installer.sh"; relock
expect_fail 'an extra key line appended to the installer table is refused' 'release_keys table differs'

stage; sed -i "s/^\(jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\)\$/\1v1.7.3/" "$work/repo/jankurai-installer.sh"; relock
expect_fail 'closing the current key range in the installer is refused' 'release_keys table differs'

stage; sed -i "s/^\(jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\)\$/\1v1.7.3/" "$work/repo/jankurai-installer.sh"; relock
sed -i "s/^\(  \"jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\)\",\$/\1v1.7.3\",/" "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'closing the range in both the installer and the lock table is refused' 'open-ended'

stage; sed -i "s/^jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\$/&\nattacker.pub|${other_sha}|v1.7.4|/" "$work/repo/jankurai-installer.sh"; relock
sed -i "s/^  \"jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\",\$/&\n  \"attacker.pub|${other_sha}|v1.7.4|\",/" "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'an extra key added to both tables without its key file is refused' 'attacker.pub is pinned but'

stage; cp "$work/repo/agent/vendor/release-keys/jankurai-release-2026.pub" "$work/repo/agent/vendor/release-keys/attacker.pub"
expect_fail 'a vendored key that no table line pins is refused' 'is vendored but not pinned'

stage; rm -f "$work/repo/agent/vendor/release-keys/"*
expect_fail 'an empty release-keys directory is refused' 'is missing'

# --- coherent swap -------------------------------------------------------------
# A fresh key replaces the vendored key file, and the installer pin, the lock's
# release_signer_sha256 and its release_signers_table all name it. Every
# self-consistency check passes; only the hub comparison can refuse it.
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$work/swap.key" 2>/dev/null
openssl pkey -in "$work/swap.key" -pubout -out "$work/swap.pub"
swap_sha="$(sha256sum "$work/swap.pub" | cut -d ' ' -f 1)"
coherent_swap() {
  cp "$work/swap.pub" "$work/repo/agent/vendor/release-keys/jankurai-release-2026.pub"
  sed -i "s/|${pin_sha}|/|${swap_sha}|/" "$work/repo/jankurai-installer.sh"; relock
  sed -i -e "s/^release_signer_sha256 = .*/release_signer_sha256 = \"${swap_sha}\"/" \
    -e "s/|${pin_sha}|/|${swap_sha}|/" "$work/repo/agent/vendor/hub-installer.lock"
}
stage; coherent_swap
JANKURAI_HUB_CHECK=local-dev-skip bash "$work/repo/scripts/check-vendored-installer.sh" >/dev/null 2>&1 ||
  { echo "FAIL: the coherent swap should pass every self-consistency check (else this case proves nothing)" >&2; exit 1; }
echo "... the coherent swap passes every self-consistency check"
expect_fail 'a coherent swap of installer pin, lock and key file to a fresh key is refused by the hub' "differs from the hub's"

# The same swap committed to the hub on a side branch, with the lock pointing at
# that commit: a commit the hub holds but has not merged to main does not count.
git clone --quiet "$hub" "$work/fakehub"
git -C "$work/fakehub" checkout --quiet -b attacker
stage; coherent_swap
cp "$work/repo/jankurai-installer.sh" "$work/fakehub/jankurai-installer.sh"
cp "$work/swap.pub" "$work/fakehub/release-keys/jankurai-release-2026.pub"
git -C "$work/fakehub" -c user.name=test -c user.email=test@example.invalid commit --quiet -am 'swap the release key'
side="$(git -C "$work/fakehub" rev-parse HEAD)"
sed -i -e "s/^source_commit = .*/source_commit = \"${side}\"/" \
  -e "s/^release_signer_source_commit = .*/release_signer_source_commit = \"${side}\"/" "$work/repo/agent/vendor/hub-installer.lock"
JANKURAI_HUB="$work/fakehub" expect_fail 'a swap committed on a hub side branch, off main, is refused' 'does not hold'

# --- the comparison fails closed ------------------------------------------------
stage
JANKURAI_HUB='' JANKURAI_HUB_URL="file://$work/no-such-hub" expect_fail 'an unavailable hub fails closed' 'failing closed'
git init --quiet "$work/empty-hub"
stage; JANKURAI_HUB="$work/empty-hub" expect_fail 'a hub without the locked commits fails closed' 'does not hold'
stage; JANKURAI_HUB_CHECK=yes expect_fail 'an unrecognised opt-out value is refused' 'not recognised'
stage
output="$(JANKURAI_HUB='' JANKURAI_HUB_URL="file://$work/no-such-hub" JANKURAI_HUB_CHECK=local-dev-skip \
  bash "$work/repo/scripts/check-vendored-installer.sh" 2>&1)" ||
  { echo "FAIL: the local-dev opt-out should run the offline checks only: ${output}" >&2; exit 1; }
grep -qF 'SKIPPED' <<< "$output" || { echo "FAIL: the local-dev opt-out must say the hub comparison was skipped" >&2; exit 1; }
echo "... the local-dev opt-out runs the offline checks and says the hub comparison was skipped"
for run in 'env -u JANKURAI_HUB_CHECK -u JANKURAI_HUB -u JANKURAI_HUB_URL bash scripts/check-vendored-installer.sh' \
  'env -u JANKURAI_HUB_CHECK -u JANKURAI_HUB -u JANKURAI_HUB_URL bash scripts/check-vendored-installer-test.sh'; do
  grep -qxF -- "$run" "$repo_root/ops/ci/required.sh" ||
    { echo "FAIL: ops/ci/required.sh must run '${run}' so the opt-out cannot reach the gate" >&2; exit 1; }
done
[[ "$(grep -c 'check-vendored-installer' "$repo_root/ops/ci/required.sh")" == 2 ]] ||
  { echo "FAIL: ops/ci/required.sh must run the check and this test only through those env -u lines" >&2; exit 1; }
echo "... the required lane unsets the opt-out and the hub-location variables for the check and this test"

# A hub whose main has moved on, here by revoking the key (closing its range),
# refuses the repository's older pin even though the locked commits are still
# ancestors of main: currency, not just ancestry.
git -C "$work/fakehub" checkout --quiet main
git clone --quiet "$hub" "$work/movedhub"
sed -i "s/^\(jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\)\$/\1v1.7.2/" "$work/movedhub/jankurai-installer.sh"
git -C "$work/movedhub" -c user.name=test -c user.email=test@example.invalid commit --quiet -am 'revoke the key after v1.7.2'
stage; JANKURAI_HUB="$work/movedhub" expect_fail 'a hub main that has revoked the key since the locked commit is refused' "not the hub's current"

# The hub URL is derived only from an origin at <base>/<owner>/jankurai-deploy for
# the lock's source_repo owner; any other origin (a mirror under another owner,
# whose renamed hub name could be claimed) derives nothing.
stage; git -C "$work/repo" init --quiet
git -C "$work/repo" remote add origin "https://example.invalid/someone-else/jankurai-deploy.git"
JANKURAI_HUB='' expect_fail 'an origin under another owner derives no hub URL' 'no hub URL is derived'

# The hub is fixed in scripts/hub-source.sh: a lock naming another source_repo
# under the same owner is refused, never cloned.
stage; sed -i 's|^source_repo = "root/jankurai"$|source_repo = "root/jankurai-evil"|' "$work/repo/agent/vendor/hub-installer.lock"
expect_fail 'a lock source_repo other than the fixed hub is refused' 'source_repo must be root/jankurai'

# scp-like origins derive the hub in the same form; other owners derive nothing.
for case in \
  'https://example.invalid/git/root/jankurai-deploy.git|https://example.invalid/git/root/jankurai.git' \
  'git@example.invalid:root/jankurai-deploy.git|git@example.invalid:root/jankurai.git' \
  'ssh://git@example.invalid/root/jankurai-deploy|ssh://git@example.invalid/root/jankurai' \
  'git@example.invalid:someone-else/jankurai-deploy.git|' \
  'git@example.invalid:xroot/jankurai-deploy.git|'; do
  origin="${case%%|*}" want="${case#*|}"
  rm -rf "$work/derive"; git init --quiet "$work/derive"
  git -C "$work/derive" remote add origin "$origin"
  got="$(cd "$work/derive" && source "$repo_root/scripts/hub-source.sh" && derived_hub_url || true)"
  [[ "$got" == "$want" ]] || { echo "FAIL: origin ${origin} derived '${got}', expected '${want}'" >&2; exit 1; }
done
echo "... https, ssh and scp-like origins under root derive the hub; other owners derive nothing"

# The sibling ../jankurai counts only when its origin is the derived hub URL.
stage; git -C "$work/repo" init --quiet
git -C "$work/repo" remote add origin "https://example.invalid/git/root/jankurai-deploy.git"
rm -rf "$work/jankurai"; git clone --quiet "$hub" "$work/jankurai"
git -C "$work/jankurai" remote set-url origin "https://mirror.invalid/git/root/jankurai.git"
JANKURAI_HUB='' expect_fail 'a sibling ../jankurai cloned from elsewhere is not the hub' 'could not clone the hub'
git -C "$work/jankurai" remote set-url origin "https://example.invalid/git/root/jankurai.git/"
JANKURAI_HUB='' bash "$work/repo/scripts/check-vendored-installer.sh" >/dev/null ||
  { echo "FAIL: a sibling cloned from the derived hub should be used" >&2; exit 1; }
echo "... the sibling is used only when it is a clone of the derived hub"
rm -rf "$work/jankurai"

# --- sync-hub-installer.sh ------------------------------------------------------
git -C "$work/fakehub" checkout --quiet main
stage; cp "$repo_root/agent/vendor/release-keys/jankurai-release-2026.pub" "$work/repo/agent/vendor/release-keys/retired-2025.pub"
bash "$work/repo/scripts/sync-hub-installer.sh" "$work/fakehub" >/dev/null ||
  { echo "FAIL: a sync from the hub should succeed and pass the check" >&2; exit 1; }
[[ ! -e "$work/repo/agent/vendor/release-keys/retired-2025.pub" ]] ||
  { echo "FAIL: sync kept a vendored key the hub installer no longer pins" >&2; exit 1; }
echo "... sync removes a vendored key the hub installer no longer pins"
mkdir -p "$work/evilhub/release-keys"
cp "$repo_root/jankurai-installer.sh" "$work/evilhub/"
sed -i "s/^jankurai-release-2026[.]pub|${pin_sha}|v1[.]7[.]2|\$/&\n..\/..\/..\/escape.pub|${other_sha}|v1.7.4|/" "$work/evilhub/jankurai-installer.sh"
cp "$repo_root/agent/vendor/release-keys/jankurai-release-2026.pub" "$work/evilhub/release-keys/"
printf 'release = "1.7.3"\n' > "$work/evilhub/family.lock"
git -C "$work/evilhub" init --quiet
git -C "$work/evilhub" add -A
git -C "$work/evilhub" -c user.name=test -c user.email=test@example.invalid commit --quiet -m evil
stage
if output="$(bash "$work/repo/scripts/sync-hub-installer.sh" "$work/evilhub" 2>&1)"; then
  echo "FAIL: sync accepted a key name with a directory part" >&2; exit 1
fi
grep -qF 'nothing was synced' <<< "$output" || { echo "FAIL: sync traversal: got ${output}" >&2; exit 1; }
[[ ! -e "$work/escape.pub" && ! -e "$work/repo/escape.pub" ]] || { echo "FAIL: sync wrote outside release-keys/" >&2; exit 1; }
cmp -s "$work/repo/jankurai-installer.sh" "$repo_root/jankurai-installer.sh" || { echo "FAIL: sync copied the installer before refusing" >&2; exit 1; }
echo "... sync refuses a release_keys name with a directory part before copying anything"

echo "check-vendored-installer negative proof: all cases refused"
