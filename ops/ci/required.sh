#!/usr/bin/env bash
# Required lane: the whole shell surface this repo releases from must parse,
# lint clean, and the vendored installer must still behave. Everything here is
# offline and deterministic.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

echo "[ci] required lane: ci-local lane contract"
bash scripts/ci-local-lanes-test.sh

shell_files=(scripts/*.sh ops/ci/*.sh jankurai-installer.sh)

for script in "${shell_files[@]}"; do bash -n "$script"; done

# The linter is a hard requirement, not a best effort: a lane that silently
# skips it is not a gate. `just setup` / scripts/ci-doctor.sh report it missing.
command -v shellcheck >/dev/null ||
  { echo "required: shellcheck is not installed (apt-get install shellcheck, brew install shellcheck)" >&2; exit 1; }
shellcheck -S warning "${shell_files[@]}"

bash scripts/check-vendored-installer.sh
bash scripts/installer-selftest.sh
