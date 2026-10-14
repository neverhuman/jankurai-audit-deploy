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

A release of this repository is an immutable tag on a commit that passed the
forge gate. This repository builds and signs no binaries: release binaries are
built on our build hosts and signed with a release key we hold by the hub
(`root/jankurai`, `ops/release/`; v1.7.2 was the first key-signed release), and
the vendored installer here (`jankurai-installer.sh`, synced from the hub by
`scripts/sync-hub-installer.sh`) verifies them against a pinned public key.
That pin is not provisioned in this repository yet: the installer's
`release_keys` entry is all zeros, so it refuses every key-signed tag (v1.7.2
and later, including `action.yml`'s default) until the 1.7.3 release change
(#7) vendors the hub's key and pin. The refusal is deliberate and tested by
`scripts/installer-selftest.sh`.

1. Bump [`VERSION`](../VERSION) and promote the `Unreleased` section of
   [`CHANGELOG.md`](../CHANGELOG.md).
2. Run the full gate locally: `bash scripts/ci-local.sh pr-ci` (the exact
   command the forge runs) or `just check`.
3. Open a pull request with the version commit. The forge gate runs the
   `required` lane declared in [`.jeryu/ci.toml`](../.jeryu/ci.toml),
   [`ops/ci/pr-ci.sh`](../ops/ci/pr-ci.sh) (see [ci-local.md](ci-local.md)).
4. After the merge, tag the release commit with
   `jankurai-deploy-v<version>-split.<N>`. The tag mirror in
   [`.jeryu/repo.toml`](../.jeryu/repo.toml) publishes the immutable tag to the
   public GitHub mirror.

The GitHub-OIDC release scripts (`ops/ci/release-build.sh`,
`release-sign-blob.sh`, `release-macos-sign.sh`, `release-publish.sh`) and the
`ci-<sha>` tag publisher were deleted with the workflows, as they were in the
hub. Release builds depend on immutable tags, never branches.

## Integrity, provenance, and SBOM

- **Gate**: the forge `required` lane runs `ops/ci/check.sh`, whose ratchet
  audit fails a head that scores below protected main under the same auditor.
- **Signing**: done by the hub with the held release key; see the hub's
  `docs/release.md`. Nothing in this repository signs.
- **SBOM**: `ops/ci/check.sh` writes a CycloneDX SBOM with `syft` to
  `target/jankurai/security/sbom.json` and records its component count. The
  repository has no package manifests, so the SBOM is empty and no
  vulnerability scan runs on it.
- **Auditor identity**: the gate scores only with the governed jankurai
  install whose SHA-256 matches the host's authority stamp, through a private
  copy re-verified before each audit (see [ci-local.md](ci-local.md)). This
  narrows, but cannot close, tampering by code running as the gate's own user.
- **Run evidence (not provenance)**: `gitleaks` scans the full history for
  secrets on every gate run. Each run leaves a local bundle in the gate
  workspace under `target/jankurai/evidence/<commit>/` (SBOM, audit reports,
  auditor identity, `MANIFEST.sha256`, `receipt.json`). It is unsigned and lives
  only as long as the workspace, so it supports review of a run; it does not
  prove anything against whoever ran the gate and is not release provenance.
- **Actions surface**: no workflow is committed (GitHub is a publishing
  mirror). `action.yml`, the composite action downstream workflows run, is
  linted by `zizmor` on every required run, and its third-party `uses:` is
  pinned to a commit SHA.

## Launch gates

A release is only allowed to ship when every launch gate below is backed by a
real artifact or command:

- **Security**: the forge gate runs gitleaks and the syft SBOM, and the
  required lane lints `action.yml`; `just security` runs the secret scan and
  action lint locally.
- **Backups**: the Jeryu forge keeps an authoritative copy of every mirrored
  commit and tag, so a lost GitHub mirror is restored from the forge.
- **Monitoring**: a score regression shows up as a failed ratchet on the
  forge's `required` check; the local evidence bundle helps review that run
  while its workspace lasts.
- **Rollback**: documented below; tags are immutable, so any prior release is
  re-fetchable.
- **Abuse controls**: no CI credential lives on GitHub; the mirror only
  receives pushes from the forge, and the shadow lane refuses to run from a
  checkout whose `origin` is not the forge.

## Rollback

If a release regresses:

1. Identify the last known-good tag (`jankurai-deploy-v<version>-split.<N>`).
2. Re-point consumers and the installer at that immutable tag; tags are never
   moved or deleted.
3. Open a revert commit that restores the previous `VERSION` and `CHANGELOG.md`
   state, and add a `### Fixed` entry describing the rollback.
4. Re-run `just check` to confirm the rolled-back tree is green before
   re-publishing.

Because tags are immutable, any prior release can be re-fetched from its tag,
and the hub's signed release assets verify bit-for-bit against the pinned key.
