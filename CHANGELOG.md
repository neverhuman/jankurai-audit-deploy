# Changelog

This file is written when a release is cut: its notes are generated from the commits since the previous release. Do not add entries by hand; write a commit subject that says what changed.

All notable changes to jankurai-deploy are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The authoritative version string lives in [`VERSION`](VERSION).

## [Unreleased]

### Changed

- Action and install-document defaults now select the published, key-signed
  `v1.7.5` artifacts (public release ID `413074879`, published 2026-10-14).
  The vendored installer and release key remain byte-identical; see
  `docs/published-1.7.5.md` for independent reproduction and rollback guidance.
- Auditor metadata prepares the next 1.7.6 hub composition. This source pin is
  distinct from the currently published/vendored installer identity and does
  not publish or install 1.7.6; the final hub validates their bounded transition.

### Removed

- GitHub Actions workflows (`.github/workflows/`) and the workflow-only
  `ops/ci/aggregate.sh`. GitHub is a publishing mirror only; CI runs on the
  forge (below).
- The GitHub-only scripts: `ops/ci/github-setup.sh`, `ops/ci/publish-ci-tag.sh`
  (and the `ci-<sha>` tags it published), and the GitHub-OIDC release scripts
  `ops/ci/release-build.sh`, `release-sign-blob.sh`, `release-macos-sign.sh` and
  `release-publish.sh`. The hub builds release binaries and signs them with the
  held release key, as it has since v1.7.2.
- The pinned-source auditor build and the upstream adversarial test run that
  `ops/ci/github-setup.sh` did: it cloned jankurai-core at
  `8505079e47597225e1f2bf65f57d41b0d050bfe7`, built the auditor from that
  source, and ran core's `language_bad_behavior` test. The scorer is now the
  host-governed binary verified against the host's authority stamp (the family
  keeps one auditor pin of record, on that install, rather than one per
  consumer repo), and `language_bad_behavior` runs in core's own gate
  (`ops/ci/tool-adoption.sh` there), where the code it tests lives.

### Added

- `docs/decisions/`, the decision records for this repository, starting with
  0001 (the gate's score floor).

### Changed

- The gate's score floor is 85 (`minimum_score` in `agent/audit-policy.toml`)
  instead of "no lower than protected main". `ops/ci/check.sh` runs
  `jankurai audit --mode standard`: a head fails below 85 or on any critical or
  high finding, and its comparison with main is recorded in the report
  (`decision.ratchet`) but no longer fails it. Owner decision, recorded in
  `docs/decisions/0001-score-floor-85.md` with how to change the floor;
  `scripts/forge-gate-test.sh` pins the audit line and refuses a
  `--fail-under` in `check.sh`.
- The forge `required` lane (`ops/ci/pr-ci.sh`, declared in `.jeryu/ci.toml`)
  runs the full gate, `ops/ci/check.sh` (renamed from `ops/ci/github-check.sh`):
  the required lane, gitleaks over the full history, a syft CycloneDX SBOM
  (with its component count recorded), and an enforcing audit of the head
  (see the score floor entry below). It used to run only the required lane plus an advisory audit
  that skipped itself when `jankurai` was missing; a missing tool now fails the
  run. `ops/ci/collect-evidence.sh` leaves a local, unsigned bundle of the
  run's output in the workspace (SBOM, audit reports, auditor identity,
  `MANIFEST.sha256`, `receipt.json`), pass or fail; it is review evidence, not
  provenance.
- The gate's auditor is the governed install only: `$HOME/.jeryu/bin/jankurai`
  whose SHA-256 matches `binary_sha256` in the host's authority stamp, with
  both files owned by the running user and not group/world-writable. It is
  never taken from PATH and there is no in-repo version pin. `JANKURAI=` is a
  local override recorded as unverified, and `pr-ci.sh` refuses it. The check
  lives in `ops/ci/auditor.sh`: the verified binary is copied into a private
  mode-700 directory under `target/`, only the copy runs, and its digest is
  re-checked immediately before each audit (baseline and head).
  `prepare-baseline.sh` has no PATH fallback, and `just fast` / `just audit`
  use `ops/ci/self-audit.sh` instead of a bare `jankurai`. Same-user code can
  still tamper; a shell lane cannot enforce that boundary, and the stamp is
  self-attesting (known limit, recorded in decision 0001 with a follow-up). The check works with
  GNU or BSD `stat` and fails with "unsupported platform" otherwise.
- `scripts/forge-gate-test.sh`, run by the required lane, is a tripwire: it
  pins the lane declaration and the steps of `pr-ci.sh` and `check.sh`,
  exercises the auditor identity check, use-time re-verification and the
  baseline fail-closed path against a fake host install, checks every script
  the lane executes for `|| true`, `|| :`, `|| exit 0` and `set +e`, rejects a
  `just required` recipe that would shadow `pr-ci.sh` on the forge, and rejects
  any committed `.github/workflows`.
- `scripts/lint-actions.sh`, run by the required lane and `just security`, lints
  the published composite action `action.yml` with `zizmor --offline` (and any
  workflow directory with actionlint + zizmor). zizmor is pinned at 1.25.2
  everywhere (was 1.12.0 here, 1.25.2 in the deleted workflow).
- `action.yml` passes its inputs to `run:` steps through `env:` instead of
  `${{ inputs.* }}` interpolation, fixing six high zizmor template-injection
  findings, and rejects an unknown `mode`.
- `ops/ci/install-security-tools.sh` also installs syft and takes its gitleaks
  version from `ops/ci/lib.sh` (8.30.0; it installed 8.21.2 before);
  `scripts/ci-doctor.sh` checks zizmor and actionlint.

## [1.7.5] - 2026-10-14

`VERSION` is `1.7.5-split.0`, the member version shipped in the 1.7.5 family
release.

### Changed

- `jankurai-installer.sh` is re-synced from the hub's 1.7.5 installer (hub
  `b4ce1a3`), whose only change is the default tag `v1.7.5`;
  `agent/vendor/hub-installer.lock` records its SHA-256, source commit and
  `family_release = "1.7.5"`. The release key and the `release_keys` table are
  unchanged.
- `v1.7.4` is published, so `published_release` is `1.7.4`, and the
  `action.yml` `release-tag` default and the `docs/install.md` command move from
  `v1.7.3` to `v1.7.4`. They move to `v1.7.5` once it is published; until then
  the hub's auditor pin names `v1.7.4` as the previous published release.
- `agent/standard-version.toml` declares `auditor_version = "1.7.5"`, the
  family auditor pin.

## [1.7.4] - 2026-10-14

`VERSION` is `1.7.4-split.0`, the member version shipped in the 1.7.4 family
release.

### Changed

- `jankurai-installer.sh` is re-synced from the hub's 1.7.4 installer (hub
  `1d4f2c7`), whose only change is the default tag `v1.7.4`;
  `agent/vendor/hub-installer.lock` records its SHA-256, source commit and
  `family_release = "1.7.4"`. The release key and the `release_keys` table are
  unchanged.
- `v1.7.3` is published, so `published_release` is `1.7.3`, and the
  `action.yml` `release-tag` default and the `docs/install.md` command move from
  `v1.7.2` to `v1.7.3`. They move to `v1.7.4` once it is published; until then
  the hub's auditor pin names `v1.7.3` as the previous published release.
- `agent/standard-version.toml` declares `auditor_version = "1.7.4"`, the
  family auditor pin.

## [1.7.3] - 2026-10-14

`VERSION` is `1.7.3-split.0`, the member version shipped in the 1.7.3 family
release. This section covers everything on `main` since `1.7.0-split.0`.

### Security

- The release-signing key pin is now checked, not just carried. The hub's
  public key file (`release-keys/jankurai-release-2026.pub`, committed in hub
  PR #11 as `cf5e0c8`, SHA-256 `99f48af1...06fc`) is vendored byte-for-byte as
  `agent/vendor/release-keys/jankurai-release-2026.pub`.
  `agent/vendor/hub-installer.lock` records:
  - the key's source commit, SHA-256 and first tag;
  - the installer's whole `release_keys` table, as `release_signers_table`.
- `scripts/check-vendored-installer.sh` (required lane) refuses all of these:
  - an installer table that is not exactly the lock's (an added key, a closed
    or moved range, a swapped hash);
  - a pinned key that is not vendored with its pinned SHA-256;
  - a vendored key that no line pins;
  - a current key that is not open-ended.
- The check then compares the installer and every vendored key byte-for-byte
  with the hub at the commits the lock names, and requires those commits to be
  on hub `main`. This is mandatory in the required lane: with no reachable hub
  the check fails. `scripts/hub-source.sh` finds the hub from the sibling
  `../jankurai` or a clone of the hub next to this repository's origin; by hand, `JANKURAI_HUB` / `JANKURAI_HUB_URL` may name one, but
  `ops/ci/required.sh` unsets them, and the only opt-out,
  `JANKURAI_HUB_CHECK=local-dev-skip`, too. The lane now requires `git` and
  `openssl`, and `agent/proof-lanes.toml` declares the `fast` lane as needing
  network.
- The hub comparison also requires the installer and every vendored key to be
  the hub's current files at the tip of `main` (a revoked key cannot stay
  trusted through an older pin). The hub's identity is fixed in
  `scripts/hub-source.sh` (`root/jankurai`); the PR-editable lock's
  `source_repo` must equal it and never chooses it. A hub URL is derived only
  from an origin at `<base>/root/jankurai-deploy` (or the scp-like
  `<user@host>:root/jankurai-deploy`); the sibling counts only when its origin
  is that derived hub, and its `main` is its `origin/main` only. The clone never
  prompts and times out after 300 s.
- `scripts/installer-selftest.sh` checks offline that the committed pin is the
  SHA-256 of the vendored key file and not a placeholder.
- `scripts/check-vendored-installer-test.sh` proves each drift is refused, and
  so is a coherent swap of key file, lock and installer pin to a fresh key,
  the same swap on a hub side branch, an unavailable hub and a hub without the
  locked commits.
- `scripts/sync-hub-installer.sh` copies the keys and the table with the
  installer. It refuses a key name that is not a plain `.pub` file name before
  copying anything, and removes vendored keys the table no longer pins.
- [`docs/release-signing.md`](docs/release-signing.md) records the key's
  provenance, the intentionally open-ended range and the rotation policy.

### Changed

- `agent/generated-zones.toml` no longer declares `jankurai-installer.sh` a `generator_only` zone. It is a byte-identical, hash-pinned copy of the hub's installer and cannot carry a `Generated by:` header, so the zone made every head (main included) fail the ratchet audit with a hard HLT-002 finding. Its integrity stays enforced by `scripts/check-vendored-installer.sh` in the required lane. `target/` is declared `auditor_output` (optional build output, absent from a clean checkout) instead of `generated_output`.
- Raised the vendored installer's default tag to the family release `v1.7.3` (was `v1.7.2`). The `action.yml` `release-tag` default and the `docs/install.md` command stay on `v1.7.2`, the newest published release (`published_release` in the lock); they move to `v1.7.3` after the hub publishes it. The installer is re-synced from the hub, which also brings in the real 2026 release-key pin in place of the all-zero placeholder and the bounded `download()` retry helper (4 attempts, 15s connect timeout, 60s per attempt, `--disable`, HTTPS-only redirects).
- `agent/standard-version.toml` declares `auditor_version = "1.7.3"` (was `1.6.0`): the family auditor pin, enforced across members by the hub's `validate-family`. `agent/audit-policy.toml`, the badge and the accepted baseline still record `1.6.0`, the auditor that produced that baseline; they move together when the baseline is regenerated.
- `scripts/installer-selftest.sh` swaps whatever key the installer pins for the fixture key, as the hub harness does, and builds its unprovisioned case by writing the all-zero pin itself. It matches the key's pin line literally (not as a regex) and accepts any coverage range, so a rotation does not break it; the pin's value is checked by `scripts/check-vendored-installer.sh`.

### Added

- `scripts/installer-selftest.sh`: an offline, Node-free self-test of
  `jankurai-installer.sh` (argument rejection, `--print-asset-name`, and the
  signing-path and certificate-identity selection it derives from the requested
  repository and tag), driven by fixture release assets and stub verifiers.
- `shellcheck -S warning` over `scripts/*.sh`, `ops/ci/*.sh`, and
  `jankurai-installer.sh` in `ops/ci/required.sh`, alongside the existing
  `bash -n` pass; the lane fails if shellcheck is not installed, and
  `scripts/ci-doctor.sh` now reports it.
- Root `Justfile` command surface with `setup`, `fast`, `check`, `verify`,
  `security`, `audit`, and `release` lanes for one-command setup and validation.
- `ops/ci/pr-ci.sh`, the pull-request CI entrypoint the self-hosted
  `.github/workflows/ci.yml` runner calls, so local runs and CI execute identical
  commands.
- Agent-readable documentation: `README.md`, `docs/architecture.md`,
  `docs/boundaries.md`, `docs/testing.md`, `docs/release.md`, and
  `docs/exceptions.md`.
- `agent/audit-policy.toml` with `[scan]` exclusions for transient build trees,
  and `agent/boundaries.toml` plus `agent/proof-lanes.toml` scoped to this
  member.

### Changed

- Replaced the forked `jankurai-installer.sh` with a byte-identical copy of the
  hub's verified installer, recorded in `agent/vendor/hub-installer.lock` and
  `agent/generated-zones.toml`, so the installer published with a release has
  the hub's rename-aware Sigstore signer and release-key pinning instead of a
  default that fails verification for tags after v1.7.1.
- Raised the `action.yml` `release-tag` default to the family release `v1.7.2`
  (was `v1.7.0-split.0`) and pointed its description at
  `neverhuman/jankurai-audit`.

### Added

- `scripts/check-vendored-installer.sh`, run by `bash scripts/ci-local.sh
  required`, which fails if the vendored installer drifts from its pinned
  SHA-256 or if the installer and `action.yml` defaults stop matching the
  family release in the vendor lock, plus `scripts/sync-hub-installer.sh` to
  re-copy the installer from a hub checkout.

- Moved the remaining site specifics out of ops: the shadow lane reads the forge
  origin it requires from `JERYU_FORGE_ORIGIN` instead of a hardcoded retired
  remote, `ops/ci/artifact_support.sh` finds a local Jeryu checkout through
  `JERYU_SOURCE_DIR` instead of a fixed home path, and `ops/ci/node-tools.sh`,
  `ops/AGENTS.md` and the audit-masking issue template no longer name the
  retired remote URL.
- Re-scoped `agent/generated-zones.toml` to the only generated tree that exists
  here (`target/`), and removed the dangling `dist/`, `.fusion/`, and
  `package-lock.json` zone entries.
- Re-scoped `agent/owner-map.json` and `agent/test-map.json` to assign an owner
  and a proof route to every top-level path that exists in this repo.
- Rewrote the legacy "internal GitLab" remote/origin/MR references in
  `ops/ci/node-tools.sh`, `ops/ci/post-main-shadow.sh`, `ops/AGENTS.md`,
  `docs/ci-local.md`, and the audit-masking issue template to the Jeryu remote.

## [1.6.10] - 2026-06-12

### Added

- Initial split-family extraction of the jankurai release and mirroring tooling.
