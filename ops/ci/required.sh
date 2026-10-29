#!/usr/bin/env bash
# Required lane: the whole shell surface this repo releases from must parse,
# lint clean, and the vendored installer must still behave. Everything here is
# deterministic; the one network step is the mandatory hub comparison, which
# fails closed when the hub cannot be reached.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "[ci] required lane: ci-local lane contract"
bash scripts/ci-local-lanes-test.sh

echo "[ci] required lane: forge gate contract"
bash scripts/forge-gate-test.sh

shell_files=(scripts/*.sh ops/ci/*.sh jankurai-installer.sh)

for script in "${shell_files[@]}"; do bash -n "$script"; done

# The linter is a hard requirement, not a best effort: a lane that silently
# skips it is not a gate. `just setup` / scripts/ci-doctor.sh report it missing.
command -v shellcheck >/dev/null ||
  { echo "required: shellcheck is not installed (apt-get install shellcheck, brew install shellcheck)" >&2; exit 1; }
shellcheck -S warning "${shell_files[@]}"

bash scripts/lint-actions.sh

# The vendored-trust check compares the installer and release keys with the hub's
# bytes (scripts/hub-source.sh finds the hub). That comparison is mandatory here:
# its local-development opt-out is unset for both runs, so this lane fails closed
# when the hub is unavailable instead of passing on self-consistency alone.
#
# The hub's location is not taken from the environment here either: JANKURAI_HUB
# and JANKURAI_HUB_URL are unset too, so the hub is the sibling ../jankurai (how
# the forge gate composes the owner's repositories) or this checkout's own origin
# with the name changed. Both are set by whoever runs the lane, never by a PR.
for tool in git openssl; do
  command -v "$tool" >/dev/null ||
    { echo "required: ${tool} is not installed (the vendored-trust check and its negative test need it)" >&2; exit 1; }
done
env -u JANKURAI_HUB_CHECK -u JANKURAI_HUB -u JANKURAI_HUB_URL bash scripts/check-vendored-installer.sh
env -u JANKURAI_HUB_CHECK -u JANKURAI_HUB -u JANKURAI_HUB_URL bash scripts/check-vendored-installer-test.sh
bash scripts/installer-selftest.sh
# The vendored installer's key pin is open-ended (it is the hub's bytes), so the
# closed range this repository enforces before installing is proven here.
bash scripts/release-tag-bound-test.sh
