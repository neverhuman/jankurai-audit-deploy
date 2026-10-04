# Changelog

All notable changes to jankurai-deploy are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The authoritative version string lives in [`VERSION`](VERSION).

## [Unreleased]

### Added

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
