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
| `just check` / `just verify` | `ops/ci/check.sh`: required lane, gitleaks, syft SBOM, audit against the score floor (85) | none |
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
   auditor binary, and `jankurai audit --mode standard --baseline ...` scores
   the head. The head fails below `minimum_score` in
   `agent/audit-policy.toml` (85) or on any critical or high finding; the
   comparison with main is recorded in the report as `decision.ratchet` and
   does not fail it. The decision and how to change the floor:
   [decisions/0001-score-floor-85.md](decisions/0001-score-floor-85.md).

The governed binary and its home authority stamp must agree, and their digest
must also match `/etc/jankurai/auditor.sha256`. Governed lanes ignore
`JANKURAI_AUTHORITY_DIGEST` and always use that canonical path. This includes local check, fast, and audit without
`JANKURAI_REQUIRE_GOVERNED=1`. The anchor contains one lowercase SHA-256
digest, or two distinct digest lines during rotation, optionally followed by a
newline. The file and
every ancestor must be root-owned, have no group/world write bits, be unwritable
by the gate user (including ACL access), and contain no symlinks. Root gates and
missing or malformed anchors fail closed. The home stamp cannot authorize a
replacement binary.

A host owner must independently verify the adopted release/build and obtain its
digest from that trusted artifact, rather than copying the home stamp. Before
running the gate, the owner must create `/etc/jankurai` with root ownership and
mode 0755, then install the trusted digest as `auditor.sha256`, root-owned with
mode 0644. Repeat this owner-controlled procedure whenever the adopted auditor
changes. Never grant the gate user permission to update this anchor. This
repository includes `ops/ci/install-auditor-anchor.sh` for this explicit host step:

```bash
# Obtain DIGEST independently from the verified, adopted signed release.
sudo bash ops/ci/install-auditor-anchor.sh "$DIGEST"
env -u JANKURAI JANKURAI_REQUIRE_GOVERNED=1 bash ops/ci/check.sh --identity-only
```

Provision and verify every gate host **before** publishing an enforcing head.
The installer requires root, accepts only an explicit digest, refuses symlink
paths and unsafe ownership/modes, and never reads the user-writable home stamp.
It is idempotent for the adopted digest and refuses implicit replacement.
Provisioning supports GNU and BSD `stat` with an explicit platform diagnostic.

For rotation, independently verify both signed artifacts. Deploy readers with
two-digest support to every lane before staging: older readers reject the new
format. As root, run `bash ops/ci/install-auditor-anchor.sh --stage "$OLD_DIGEST"
"$NEW_DIGEST"` (one command). This atomically adopts both digests. Only then
allow automatic governed home updates. Run the identity-only check above as
each non-root gate user after updating its binary and stamp. Once every home
has migrated and rollback is no longer needed, as root run
`bash ops/ci/install-auditor-anchor.sh --retire "$OLD_DIGEST" "$NEW_DIGEST"`.
This atomically retains only the new digest. Both commands are safe to rerun
and refuse unexpected existing adoption. Never grant gate users anchor writes.

Stage on all hosts before updating any homes; retire only after all homes have
migrated. This avoids an anchor mismatch gap. A gate racing a non-atomic home
binary/stamp update still fails closed and may need a retry. Rollback while
staged needs no anchor change; after retirement, stage the new digest followed
by the old digest before rolling homes back.

Owner operations serialize with `/etc/jankurai/.auditor.lock`. A crash leaves a
complete old or new anchor and may leave the lock. Before removing that empty
directory with `rmdir`, the owner must confirm no owner process remains and
inspect the anchor and any `.auditor.*` pending files, then rerun the intended
command. Never remove a live lock. The required lane counts missing provisioning
or root-run acceptance as failure. Rotation fixtures simulate owner metadata;
the real acceptance tripwire uses the canonical host file.

Governed gates require a non-root Unix user. The optional local-CI Docker image
defaults to root and is therefore unsuitable for a governed gate as shipped.
A governed container must run as a non-root user, provide that user's governed
installation, and mount the host-adopted canonical anchor read-only. A root-run
lane fails explicitly before scoring; changing anchor permissions cannot fix it.

For local runs, `JANKURAI=/path just check` remains an explicitly unverified
override; `ops/ci/pr-ci.sh` refuses it. The verified binary is copied into a
private directory under `target/` and rehashed immediately before each audit.
Same-user code can still race execution or modify the shell gate itself; hostile
PR execution still requires host isolation.

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
