#!/usr/bin/env bash
# Evidence bundle for one gate attempt.
#
# usage: collect-evidence.sh <gate-exit-code>
#
# Copies the evidence ops/ci/check.sh writes into
# target/jankurai/evidence/<commit>/ together with a SHA-256 manifest and a
# small JSON receipt naming the commit, the tree and the gate result. When the
# gate passed, every listed artifact must exist and a missing one fails the
# run; when the gate failed, whatever exists is kept so the failure can be
# reviewed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

gate_exit="${1:?usage: collect-evidence.sh <gate-exit-code>}"
if [[ ! "$gate_exit" =~ ^[0-9]+$ ]]; then
  echo "collect-evidence: gate exit code must be a number, got: $gate_exit" >&2
  exit 2
fi

commit="$(git rev-parse HEAD)"
tree="$(git rev-parse 'HEAD^{tree}')"
out="target/jankurai/evidence/$commit"
rm -rf "$out"
mkdir -p "$out/files"

evidence=(
  target/jankurai/auditor.txt
  target/jankurai/security/sbom.json
  target/jankurai/accepted-baseline.json
  target/jankurai/accepted-baseline.md
  .jankurai/repo-score.json
  .jankurai/repo-score.md
)

missing=()
for path in "${evidence[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    mkdir -p "$out/files/$(dirname "$path")"
    cp "$path" "$out/files/$path"
  else
    missing+=("$path")
  fi
done

(cd "$out/files" && find . -type f -print0 | sort -z | xargs -0 -r sha256sum) > "$out/MANIFEST.sha256"

jq -n \
  --arg commit "$commit" \
  --arg tree "$tree" \
  --argjson gate_exit "$gate_exit" \
  --argjson missing "$(printf '%s\n' "${missing[@]+"${missing[@]}"}" | jq -R 'select(length > 0)' | jq -s .)" \
  --arg manifest_sha256 "$(sha256sum "$out/MANIFEST.sha256" | cut -d' ' -f1)" \
  '{schema: "jankurai-deploy/gate-evidence/v1", commit: $commit, tree: $tree,
    gate_exit: $gate_exit, gate_passed: ($gate_exit == 0),
    missing: $missing, manifest_sha256: $manifest_sha256}' \
  > "$out/receipt.json"

echo "[ci] evidence bundle: $out ($(wc -l < "$out/MANIFEST.sha256") files)"

if [[ "$gate_exit" -eq 0 && "${#missing[@]}" -gt 0 ]]; then
  echo "[ci] gate passed but evidence is missing:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi
