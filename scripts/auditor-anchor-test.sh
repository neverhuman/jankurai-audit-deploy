#!/usr/bin/env bash
# Fixture owner metadata is simulated; canonical host coverage is in forge-gate-test.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source ops/ci/auditor.sh
mkdir -p target
fixture="$(mktemp -d target/anchor-test.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
fixture="$PWD/$fixture"
old="$(printf 'a%.0s' {1..64})"
new="$(printf 'b%.0s' {1..64})"
other="$(printf 'c%.0s' {1..64})"
# Redirect only a fixture copy; production has no owner or path override.
python3 - "$fixture" <<'PY'
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
src = pathlib.Path('ops/ci/install-auditor-anchor.sh').read_text()
src = src.replace('source "$(dirname "${BASH_SOURCE[0]}")/auditor.sh"',
                  'source ops/ci/auditor.sh\nid() { echo 0; }\n'
                  'file_uid_mode() { echo "0 755"; }')
src = src.replace('/etc/jankurai', str(root / 'anchor'))
src = src.replace('install -d -o root -g 0 -m 0755', 'mkdir -m 0755')
(root / 'owner.sh').write_text(src)
PY
owner() { bash "$fixture/owner.sh" "$@"; }
refuse() { if "$@"; then echo "unexpected acceptance: $*" >&2; exit 1; fi; }
anchor="$fixture/anchor/auditor.sha256"
owner "$old"
owner "$old"
refuse owner "$new"
refuse owner --stage "$other" "$new"
owner --stage "$old" "$new"
owner --stage "$old" "$new"
[[ "$(cat "$anchor")" == "$(printf '%s\n%s' "$old" "$new")" ]]
valid_anchor_digests "$(cat "$anchor")"
owner --retire "$old" "$new"
owner --retire "$old" "$new"
[[ "$(cat "$anchor")" == "$new" ]]
refuse owner --stage "$old" "$other"
refuse valid_anchor_digests "$(printf '%s\n%s\n%s' "$old" "$new" "$other")"
refuse valid_anchor_digests "$(printf '%s\n%s' "$old" "$old")"
refuse valid_anchor_digests 'invalid'
mkdir "$fixture/anchor/.auditor.lock"
refuse owner --stage "$new" "$other"
[[ "$(cat "$anchor")" == "$new" ]]
rmdir "$fixture/anchor/.auditor.lock"
[[ "$(id -u)" != 0 ]]
refuse bash ops/ci/install-auditor-anchor.sh --stage "$old" "$new"
refuse bash ops/ci/install-auditor-anchor.sh --retire "$old" "$new"
refuse bash ops/ci/install-auditor-anchor.sh "$old"
echo 'auditor anchor transition fixtures passed'
