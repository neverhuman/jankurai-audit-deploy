# Running CI locally

CI runs on the forge. GitHub is a publishing mirror only and runs no
workflows. Every lane the forge runs has a local command that executes the same
script, so a failure shows up on the developer's machine first. Use this as the
contract between local work and the forge merge gate.

## The forge gate

[`.jeryu/ci.toml`](../.jeryu/ci.toml) declares one lane, `required`, which runs
[`ops/ci/pr-ci.sh`](../ops/ci/pr-ci.sh). The forge gate runs `just required`
when the Justfile has that recipe and `ops/ci/pr-ci.sh` otherwise; this
repository deliberately has no `just required`, and
[`scripts/forge-gate-test.sh`](../scripts/forge-gate-test.sh) fails the required
lane if one appears or if the declaration and scripts drift apart.

`ops/ci/pr-ci.sh` runs [`ops/ci/check.sh`](../ops/ci/check.sh) with the governed
auditor only, and then writes a local bundle to
`target/jankurai/evidence/<commit>/` (the SBOM and its component count, the
audit reports, the auditor's identity, version and digest, a `MANIFEST.sha256`
and a `receipt.json` naming the commit, tree and gate result), pass or fail.
The bundle is unsigned and stays in the gate workspace: it helps review a run
and is not release provenance.

## Quick reference

| Command | Runs | Network |
| --- | --- | --- |
| `bash scripts/ci-local.sh pr-ci` | exactly what the forge runs: `ops/ci/check.sh` (governed auditor only) plus the evidence bundle | none |
| `just check` / `just verify` | `ops/ci/check.sh`: required lane, gitleaks, syft SBOM, ratchet audit against protected main | none |
| `just fast` / `just test` | the required lane, then an advisory audit with the verified auditor (`ops/ci/self-audit.sh`) | none |
| `bash scripts/ci-local.sh required` | the required lane only | none |
| `just security` | `tools/security-lane.sh`: gitleaks, action lint, script digests | none |
| `just setup` | `scripts/ci-doctor.sh` and the pinned security tools | downloads |

## What each lane runs

### Required lane (`ops/ci/required.sh`)

1. `scripts/ci-local-lanes-test.sh`: the family lane contract of
   `scripts/ci-local.sh`.
2. `scripts/forge-gate-test.sh`: the forge gate contract above, and no
   committed `.github/workflows`.
3. `bash -n` and `shellcheck -S warning` over `scripts/*.sh`, `ops/ci/*.sh` and
   `jankurai-installer.sh`.
4. `scripts/lint-actions.sh`: `zizmor --offline action.yml`, the composite
   action downstream workflows run (and actionlint + zizmor over
   `.github/workflows` if that directory ever exists).
5. The vendored-installer check with its mandatory hub comparison and its
   negative test, and the offline installer self-test. The hub comparison
   reads the hub `root/jankurai`: the sibling `../jankurai` when it holds the
   locked commits on `origin/main`, otherwise a fresh clone next to this
   checkout's origin. It fails when the hub cannot be read.

Needs `shellcheck`, `zizmor`, `git` and `openssl` on PATH and read access to
the hub (network unless the sibling is present); a few seconds.

### Full gate (`ops/ci/check.sh`)

1. The required lane.
2. `gitleaks detect --source .` over the full history.
3. `syft dir:.` writes a CycloneDX SBOM to
   `target/jankurai/security/sbom.json` and its component count to
   `sbom-components.txt`. This repository has no package manifests, so the
   count is expected to be 0; a vulnerability scan of it would match nothing
   and would only add a network fetch of a vulnerability database to the merge
   gate, so none runs.
4. `ops/ci/prepare-baseline.sh` scores protected `origin/main` with the same
   auditor binary, and `jankurai audit --mode ratchet` fails the head if it
   scores below main.

The auditor is never taken from PATH and has no in-repo version pin (the family
keeps one pin of record, on the governed host install). `check.sh` uses
`$HOME/.jeryu/bin/jankurai` only if its SHA-256 equals `binary_sha256` in the
host's authority stamp `$HOME/.jeryu/authority/jankurai.json`
(`jeryu.jankurai-authority-stamp/v1`), and both files are owned by the running
user and not group- or world-writable; otherwise it fails closed. For a local
run, `JANKURAI=/path just check` uses another binary and records it in
`target/jankurai/auditor.txt` as an "unverified local override";
`ops/ci/pr-ci.sh` refuses the override.

The verified binary is copied into a fresh private directory (mode 700) under
`target/`, and only the copy runs; its SHA-256 is re-checked immediately before
each audit (protected-main baseline and head). `ops/ci/prepare-baseline.sh`
fails closed when the verified auditor is not exported (no PATH fallback), and
`just fast` / `just audit` go through `ops/ci/self-audit.sh`, which uses the same
check. The residual risk is stated in `ops/ci/auditor.sh`: code running as the
same user, including the pull request's own shell, can still tamper with the
copy or the stamp. A shell lane inside the repository it gates cannot enforce a
boundary against its own user (nor could the lane before this change); the
check narrows the window and records what scored, it does not prove it.
The identity check needs GNU or BSD `stat` and `sha256sum` or `shasum`, and
fails with an explicit "unsupported platform" message otherwise.

### Main shadow deploy (`ops/ci/post-main-shadow.sh`)

The Jeryu main-branch shadow deploy. It expects `JERYU_FORGE_ORIGIN` to name the
forge origin URL this checkout must already use for `origin`, and uses the local
`.jeryu/local/repos/jankurai.toml` sidecar to mirror `main` to GitHub after the
Jeryu pipeline has passed. The lane refuses to run, with a receipt, when
`JERYU_FORGE_ORIGIN` is unset or `origin` points somewhere else.

## First-time setup

```bash
just setup                                  # ci-doctor + pinned security tools
bash ops/ci/install-security-tools.sh       # gitleaks, actionlint, syft (Linux x86_64)
```

## Editing the lane

`scripts/ci-local.sh` and the `ops/ci/*.sh` scripts are the source of truth.
Change the script, not a copy of its steps, and keep
`scripts/forge-gate-test.sh` in step with any change to what the forge gate
runs.
