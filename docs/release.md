# Release process

This document is the release control surface for `jankurai-deploy`. It covers the
version source, the changelog, the release automation, integrity/provenance and
SBOM evidence, and rollback. Launch gates require every section below to be
backed by a real artifact or command.

## Version source

The single source of truth for the version is the [`VERSION`](../VERSION) file at
the repository root. Any release tag MUST match `VERSION`. Tags follow the family
pattern `jankurai-deploy-v<MAJOR.MINOR.PATCH>-split.<N>` as described in
[`SPLIT.md`](../SPLIT.md) and configured in [`.jeryu/repo.toml`](../.jeryu/repo.toml).

## Changelog

Every release records its user-visible changes in
[`CHANGELOG.md`](../CHANGELOG.md) under a heading that matches the new `VERSION`.
The `Unreleased` section is promoted to a dated version heading at tag time.

## Release automation

Releases are cut by CI, not by hand:

1. Bump [`VERSION`](../VERSION) and promote the `Unreleased` section of
   [`CHANGELOG.md`](../CHANGELOG.md).
2. Run the full local gate: `just check` (fast lane, security scanning, the
   release audit gate, and the jankurai self-audit).
3. Push the version commit. The workflows under
   [`.github/workflows/`](../.github/workflows) run the build, security, and
   jankurai audit jobs and upload the `repo-score` artifacts.
4. Tag the release commit with `jankurai-deploy-v<version>-split.<N>`. The build
   job in [`release.yml`](../.github/workflows/release.yml) produces signed
   artifacts via `ops/ci/release-build.sh`, `ops/ci/release-macos-sign.sh`, and
   `ops/ci/release-sign-blob.sh`; the publish job
   (`ops/ci/release-publish.sh`) attaches them to the immutable tag.
5. The tag mirror in [`.jeryu/repo.toml`](../.jeryu/repo.toml) publishes the
   immutable tag to the public GitHub mirror.

Release builds depend on immutable tags, never branches.

## Integrity, provenance, and SBOM

- **Release gate**: `ops/ci/release-audit-gate.sh` runs the ratchet jankurai
  audit (`just release`) before any tag is cut, so a release cannot ship below
  the score floor.
- **Signing**: release artifacts are signed by `ops/ci/release-sign-blob.sh`
  (Sigstore blob signing) and, on macOS, notarized by
  `ops/ci/release-macos-sign.sh`. Each artifact ships with a `sha256` sidecar.
- **SBOM**: a CycloneDX/SPDX software bill of materials is generated from the
  locked dependency graph during the security job and attached to the release as
  `sbom.spdx.json`.
- **Provenance**: the security job runs `gitleaks` for secret scanning and
  `cargo audit` for advisory checks; the audit job publishes the `repo-score`
  artifacts that prove the release passed the jankurai gate.
- **Action pinning**: every third-party GitHub Action is pinned to a 40-character
  commit SHA so the supply chain of the release pipeline itself is fixed.

## Launch gates

A release is only allowed to ship when every launch gate below is backed by a
real artifact or command. These gates prove backups, monitoring, security, and
rollback for the release surface:

- **Security**: `just security` runs gitleaks (secret scanning) and cargo audit
  (dependency scanning); the security CI job emits
  `target/jankurai/security/evidence.json` and the SBOM before the audit gate.
- **Backups**: release artifacts and their signed `sha256` sidecars are durable,
  immutable, and re-fetchable from each tag; the Jeryu forge keeps
  an authoritative copy of every mirrored commit and tag, so a lost GitHub
  mirror is restored from the forge.
- **Monitoring**: the `repo-score` artifacts, the `summary.md` step summary, and
  the publish receipts written under `target/jankurai/` give a post-release
  monitoring trail; a regression shows up as a score drop on the next audit.
- **Rollback**: documented below; tags are immutable, so any prior release is
  re-fetchable and re-verifiable bit-for-bit.
- **Abuse controls**: publishing and signing run once per immutable tag with
  least-privilege CI permissions (`contents: read`), pinned action SHAs, and a
  clean-worktree precondition on the shadow lane, which bounds abuse of the
  release path.

## Rollback

If a release regresses:

1. Identify the last known-good tag (`jankurai-deploy-v<version>-split.<N>`).
2. Re-point consumers and the installer at that immutable tag; tags are never
   moved or deleted.
3. Open a revert commit that restores the previous `VERSION` and `CHANGELOG.md`
   state, and add a `### Fixed` entry describing the rollback.
4. Re-run `just check` to confirm the rolled-back tree is green before
   re-publishing.

Because tags are immutable and the release artifacts carry signed `sha256`
sidecars and an SBOM, any prior release can be re-fetched and verified
bit-for-bit from its tag.
