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

`ops/ci/pr-ci.sh` runs [`ops/ci/check.sh`](../ops/ci/check.sh) and then writes an
evidence bundle to `target/jankurai/evidence/<commit>/` (the SBOM, the audit
reports, the auditor's version and digest, a `MANIFEST.sha256` and a
`receipt.json` naming the commit, tree and gate result), pass or fail.

## Quick reference

| Command | Runs | Network |
| --- | --- | --- |
| `bash scripts/ci-local.sh pr-ci` | exactly what the forge runs: `ops/ci/check.sh` plus the evidence bundle | grype DB |
| `just check` / `just verify` | `ops/ci/check.sh`: required lane, gitleaks, syft SBOM, grype, ratchet audit against protected main | grype DB |
| `just fast` / `just test` | the required lane, then an advisory `jankurai audit` | none |
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
   `target/jankurai/security/sbom.json`; `grype` scans it with
   `--fail-on high`.
4. `ops/ci/prepare-baseline.sh` scores protected `origin/main` with the same
   auditor binary, and `jankurai audit --mode ratchet` fails the head if it
   scores below main.

The auditor is `JANKURAI` (an explicit path) or `jankurai` on PATH; the forge
gate hosts provide the governed build. Its version and SHA-256 are written to
`target/jankurai/auditor.txt`.

### Main shadow deploy (`ops/ci/post-main-shadow.sh`)

The Jeryu main-branch shadow deploy. It expects `JERYU_FORGE_ORIGIN` to name the
forge origin URL this checkout must already use for `origin`, and uses the local
`.jeryu/local/repos/jankurai.toml` sidecar to mirror `main` to GitHub after the
Jeryu pipeline has passed. The lane refuses to run, with a receipt, when
`JERYU_FORGE_ORIGIN` is unset or `origin` points somewhere else.

## First-time setup

```bash
just setup                                  # ci-doctor + pinned security tools
bash ops/ci/install-security-tools.sh       # gitleaks, actionlint, syft, grype (Linux x86_64)
```

## Editing the lane

`scripts/ci-local.sh` and the `ops/ci/*.sh` scripts are the source of truth.
Change the script, not a copy of its steps, and keep
`scripts/forge-gate-test.sh` in step with any change to what the forge gate
runs.
