#!/usr/bin/env bash
# Offline self-test for the vendored jankurai-installer.sh.
#
# The installer is byte-locked to the hub copy (scripts/check-vendored-installer.sh),
# so this lane proves its behaviour without editing it: argument rejection,
# --print-asset-name, and the signing/identity selection it derives from the
# requested repository and tag. The hub owns the exhaustive Node harness
# (scripts/installer.test.mjs); this is the same fixture technique in Bash so the
# deploy repo's required lane needs neither Node nor the network.
#
# Nothing here talks to the network. Release assets come from --assets-dir, the
# verifier downloads come from a stub `curl` that copies local fixture files, and
# `uname` is stubbed so the test runs the Linux x86-64 path on any host. A copy of
# the installer is patched the way the hub harness patches it: the pinned verifier
# hashes become the fixture hashes, and the unprovisioned release key pin becomes
# the fixture key's hash. The committed installer is never modified.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
repo_root="$PWD"

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT
failures=0
key_name=jankurai-release-2026.pub
key_bytes='fixture release public key'
target=x86_64-unknown-linux-gnu

note() { printf '... %s\n' "$1"; }
bad() { printf '!! %s\n' "$1" >&2; failures=$((failures + 1)); }

sha256() { sha256sum "$1" | cut -d ' ' -f 1; }

# --- stub tools on PATH -------------------------------------------------------
stubs="$work/stubs"
downloads="$work/downloads"
mkdir -p "$stubs" "$downloads"

cat > "$stubs/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'Linux\n' ;;
  -m) printf 'x86_64\n' ;;
  *) printf 'Linux fixture 0 x86_64\n' ;;
esac
EOF

# Fetches only ever reach the fixture directory; the requested URL is logged so a
# test can assert which downloads a signing path does (and does not) perform.
cat > "$stubs/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url= out=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s\n' "$url" >> "$FIXTURE_LOG"
cp "$FIXTURE_DOWNLOADS/${url##*/}" "$out"
EOF

# Stand-ins for the verifiers the installer downloads. They assert the arguments
# the installer must pass, so a wrong identity or signing path fails the test.
gh_stub='#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == attestation && "${2:-}" == verify ]] || { echo "gh: API access forbidden" >&2; exit 1; }
for name in GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
  [[ -z "${!name:-}" ]] || { echo "gh: credentials inherited" >&2; exit 1; }
done
value() { local flag="$1"; shift; while [[ $# -gt 0 ]]; do [[ "$1" == "$flag" ]] && { printf "%s" "${2:-}"; return; }; shift; done; }
[[ "$(value --cert-identity "$@")" == "$FIXTURE_IDENTITY" ]] || { echo "gh: attestation identity mismatch" >&2; exit 1; }
[[ "$(value --repo "$@")" == "$FIXTURE_SIGNER" ]] || { echo "gh: attestation repository mismatch" >&2; exit 1; }
[[ "$(value --cert-oidc-issuer "$@")" == https://token.actions.githubusercontent.com ]] || { echo "gh: wrong issuer" >&2; exit 1; }
printf "gh: attestation accepted\n"'

cosign_stub='#!/usr/bin/env bash
set -euo pipefail
value() { local flag="$1"; shift; while [[ $# -gt 0 ]]; do [[ "$1" == "$flag" ]] && { printf "%s" "${2:-}"; return; }; shift; done; }
if printf "%s\n" "$@" | grep -qx -- --key; then
  for argument in "$@"; do
    case "$argument" in --certificate*) echo "cosign: mixed key and keyless verification" >&2; exit 1 ;; esac
  done
  key="$(value --key "$@")"
  [[ "${key##*/}" == "$FIXTURE_KEY_NAME" ]] || { echo "cosign: wrong key file" >&2; exit 1; }
  [[ "$(cat "$key")" == "$FIXTURE_KEY_BYTES" ]] || { echo "cosign: wrong key bytes" >&2; exit 1; }
  [[ "$(value --bundle "$@")" == *.cosign.bundle ]] || { echo "cosign: wrong bundle" >&2; exit 1; }
else
  [[ "$(value --certificate-identity "$@")" == "$FIXTURE_IDENTITY" ]] || { echo "cosign: wrong signature identity" >&2; exit 1; }
  [[ "$(value --certificate-oidc-issuer "$@")" == https://token.actions.githubusercontent.com ]] || { echo "cosign: wrong issuer" >&2; exit 1; }
fi
printf "cosign: verified\n"'

# The installer only asks jq whether the provenance matches; identity selection
# happens before that, so the fixture answers yes and keeps the test focused.
jq_stub='#!/usr/bin/env bash
exit 0'

printf '%s\n' "$jq_stub" > "$downloads/jq-linux-amd64"
printf '%s\n' "$cosign_stub" > "$downloads/cosign-linux-amd64"
mkdir -p "$work/gh/gh_2.100.0_linux_amd64/bin"
printf '%s\n' "$gh_stub" > "$work/gh/gh_2.100.0_linux_amd64/bin/gh"
tar -czf "$downloads/gh_2.100.0_linux_amd64.tar.gz" -C "$work/gh" gh_2.100.0_linux_amd64
chmod 0755 "$stubs"/* "$downloads"/*

# --- patched installer copy ---------------------------------------------------
installer="$work/installer.sh"
cp jankurai-installer.sh "$installer"
patch_hash() {
  local pinned="$1" fixture_file="$2" replacement
  grep -q "$pinned" "$installer" || { bad "pinned hash $pinned is no longer in the installer"; return 0; }
  replacement="$(sha256 "$fixture_file")"
  sed -i "s/$pinned/$replacement/" "$installer"
}
patch_hash e4d4bb4498e8d007abe545b6568926793ace1b6447da598294a610018cb164be "$downloads/gh_2.100.0_linux_amd64.tar.gz"
patch_hash 4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71 "$downloads/cosign-linux-amd64"
patch_hash b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f "$downloads/jq-linux-amd64"

printf '%s\n' "$key_bytes" > "$work/$key_name"
key_hash="$(sha256 "$work/$key_name")"
unprovisioned="$work/installer-unprovisioned.sh"
cp "$installer" "$unprovisioned"
grep -qE "^$key_name\|0{64}\|v1\.7\.2\|\$" "$installer" ||
  bad "the release key pin line for $key_name is no longer an unprovisioned placeholder"
sed -i "s/^$key_name|0\{64\}|/$key_name|$key_hash|/" "$installer"

# --- fixture release assets ---------------------------------------------------
# Build the asset set a release of this version would publish, so the installer
# can be driven with --assets-dir and never reach a release URL. `signing` is the
# sidecar set to publish: key, keyless, or key-wrong-key for a key that does not
# match the installer's pin.
assets="$work/assets"
pack_assets() {
  local version="$1" signing="$2"
  local stem="jankurai-$version-$target"
  local asset="$stem.tar.gz"
  local stage="${assets:?}/${stem:?}"
  rm -rf "${assets:?}"
  mkdir -p "$stage"
  printf '#!/bin/sh\nprintf "jankurai %s\\n"\n' "$version" > "$stage/jankurai"
  chmod 0755 "$stage/jankurai"
  printf 'family fixture\n' > "$stage/family.lock"
  printf 'cargo fixture\n' > "$stage/Cargo.lock"
  printf 'MIT\n' > "$stage/LICENSE"
  printf '{"schema":"jankurai.release/fixture"}\n' > "$stage/provenance.json"
  tar -czf "$assets/$asset" -C "$assets" "$stem"
  rm -rf "${stage:?}"
  printf '%s  %s\n' "$(sha256 "$assets/$asset")" "$asset" > "$assets/$asset.sha256"
  case "$signing" in
    key) printf 'controlled verifier fixture\n' > "$assets/$asset.cosign.bundle"
         printf '%s\n' "$key_bytes" > "$assets/$key_name" ;;
    key-wrong-key) printf 'controlled verifier fixture\n' > "$assets/$asset.cosign.bundle"
         printf 'attacker key\n' > "$assets/$key_name" ;;
    keyless) printf 'controlled verifier fixture\n' > "$assets/$asset.sigstore.bundle"
         printf 'controlled verifier fixture\n' > "$assets/$asset.attestation.jsonl" ;;
    *) bad "unknown fixture signing mode: $signing"; return 1 ;;
  esac
}

# Run the patched installer in verify-only mode against a fixture asset set. The
# expected signer is the only identity the fixture verifiers accept, so the run
# succeeds only if the installer derives exactly that signer and signing path.
run_installer() {
  local version="$1" signing="$2" expected_signer="$3"; shift 3
  pack_assets "$version" "$signing"
  : > "$work/fetched.log"
  env -i PATH="$stubs:/usr/bin:/bin" HOME="$work/home" \
    GH_TOKEN=fixture-credential-must-not-be-used \
    GITHUB_TOKEN=fixture-credential-must-not-be-used \
    FIXTURE_DOWNLOADS="$downloads" FIXTURE_LOG="$work/fetched.log" \
    FIXTURE_KEY_NAME="$key_name" FIXTURE_KEY_BYTES="$key_bytes" \
    FIXTURE_SIGNER="$expected_signer" \
    FIXTURE_IDENTITY="https://github.com/$expected_signer/.github/workflows/release.yml@refs/tags/v$version" \
    bash "${INSTALLER_UNDER_TEST:-$installer}" --tag "v$version" --assets-dir "$assets" --verify-only "$@" \
    > "$work/stdout" 2> "$work/stderr"
}

# --- cases --------------------------------------------------------------------
# Argument rejection: the installer must refuse malformed input before it does
# any work, with the message the hub documents.
reject() {
  local expected="$1"; shift
  local status=0
  PATH="$stubs:$PATH" bash "$installer" "$@" > "$work/stdout" 2> "$work/stderr" || status=$?
  if (( status == 0 )); then
    bad "expected rejection for: $* (exited 0)"
  elif ! grep -q "$expected" "$work/stderr"; then
    bad "expected '$expected' for: $* (got: $(tr '\n' ' ' < "$work/stderr"))"
  else
    note "rejected $* — $expected"
  fi
}
reject 'invalid repository' --repo 'neverhuman'
reject 'invalid repository' --repo 'neverhuman/jankurai;rm -rf /'
reject 'invalid repository' --repo 'neverhuman/jankurai/extra'
reject 'invalid version tag' --tag '1.7.2'
reject 'invalid version tag' --tag 'v1.7'
reject 'invalid version tag' --tag 'v1.7.2/../../etc'
reject 'unsupported product' --product jankurai-audit
reject 'unknown argument' --not-a-flag

# --print-asset-name: the name the release lanes and the vendor check depend on,
# printed without touching the network or the filesystem.
for spec in "v1.7.2:jankurai:jankurai-1.7.2-$target.tar.gz" \
            "v1.7.1:jankurai:jankurai-1.7.1-$target.tar.gz" \
            "v2.0.0-rc.1:tuiwright:tuiwright-2.0.0-rc.1-$target.tar.gz"; do
  IFS=: read -r tag product expected <<< "$spec"
  actual="$(PATH="$stubs:$PATH" bash "$installer" --print-asset-name --tag "$tag" --product "$product")"
  if [[ "$actual" == "$expected" ]]; then
    note "--print-asset-name $tag $product — $actual"
  else
    bad "--print-asset-name $tag $product printed '$actual', expected '$expected'"
  fi
done
if [[ "$(JANKURAI_RELEASE_TAG=v1.7.2 PATH="$stubs:$PATH" bash "$installer" --print-asset-name)" \
      == "jankurai-1.7.2-$target.tar.gz" ]]; then
  note '--print-asset-name honours JANKURAI_RELEASE_TAG'
else
  bad '--print-asset-name ignored JANKURAI_RELEASE_TAG'
fi

# Identity and signing-path selection against the fixture asset sets.
accepts() {
  local description="$1"; shift
  if run_installer "$@"; then
    note "$description"
  else
    bad "$description (installer failed: $(tr '\n' ' ' < "$work/stderr"))"
  fi
}
refuses() {
  local description="$1" expected="$2"; shift 2
  if run_installer "$@"; then
    bad "$description (installer accepted it)"
  elif ! grep -q "$expected" "$work/stderr"; then
    bad "$description: expected '$expected', got: $(tr '\n' ' ' < "$work/stderr")"
  else
    note "$description"
  fi
}

# v1.7.1 and earlier keep the pre-rename keyless identity whichever hub name is
# asked for; other repositories verify as themselves.
accepts 'v1.7.1 verifies keyless as the pre-rename hub' 1.7.1 keyless neverhuman/jankurai
grep -q 'cli/cli/releases' "$work/fetched.log" ||
  bad 'the keyless path did not fetch the pinned GitHub CLI'
accepts 'v1.7.1 from the renamed hub still verifies as the pre-rename hub' \
  1.7.1 keyless neverhuman/jankurai --repo neverhuman/jankurai-audit
accepts 'a fork verifies as itself at a keyless version' \
  1.7.1 keyless example/fork --repo example/fork
refuses 'v1.7.1 is refused under the renamed identity' 'wrong signature identity' \
  1.7.1 keyless neverhuman/jankurai-audit

# v1.7.2 and later are key-signed: pinned key, no attestation, no GitHub CLI.
accepts 'v1.7.2 verifies with the pinned release key' 1.7.2 key neverhuman/jankurai-audit
if grep -qE 'cli/cli|attestation' "$work/fetched.log"; then
  bad 'the key-signed path fetched a keyless-only artifact'
else
  note 'the key-signed path fetched neither the GitHub CLI nor attestations'
fi
accepts 'v1.7.2 under the old hub name still uses the release key' \
  1.7.2 key neverhuman/jankurai-audit --repo neverhuman/jankurai
refuses 'a key that does not match its pin is refused' 'does not match its pin' \
  1.7.2 key-wrong-key neverhuman/jankurai-audit

# The committed installer pins an all-zero (unprovisioned) key, so every
# key-signed tag must be refused until a real key is pinned.
INSTALLER_UNDER_TEST="$unprovisioned" \
  refuses 'an unprovisioned key pin refuses key-signed tags' 'not provisioned' \
  1.7.2 key neverhuman/jankurai-audit

if (( failures > 0 )); then
  printf '\ninstaller self-test: %d failing case(s) against %s/jankurai-installer.sh\n' \
    "$failures" "$repo_root" >&2
  exit 1
fi
printf 'installer self-test: all cases pass (offline, fixture assets)\n'
