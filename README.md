# jankurai-deploy

<!-- jankurai-badge:start -->
[![Jankurai score: 92/100](agent/jankurai-badge.svg)](agent/jankurai-badge.json)
<!-- jankurai-badge:end -->

[![jankurai audit](https://img.shields.io/badge/jankurai-audit-passing-brightgreen)](docs/release.md)

Release, signing, installer-publishing, mirroring, and split-generator tooling
for the **jankurai** auditor. This repository is one member of the Jankurai
split family; read [`SPLIT.md`](SPLIT.md) for the family contract and
[`AGENTS.md`](AGENTS.md) for agent routing rules.

## Stack

Rust core + TypeScript/React/Vite product surface + PostgreSQL truth + generated
contracts + exception-only Python AI/data service. This member owns only the
release and mirroring surface; new automation is Rust-first. See
[`docs/architecture.md`](docs/architecture.md).

## Quick start

```bash
# One-command setup (CI doctor + pinned security toolchain).
just setup

# Deterministic fast lane (required local proof + no-write self-audit).
just fast

# Full gate the forge runs: required lane, gitleaks, SBOM, ratchet audit.
just check
```

The full command surface lives in the root [`Justfile`](Justfile). Continuous
integration runs on the forge: [`.jeryu/ci.toml`](.jeryu/ci.toml) declares one
`required` lane, [`ops/ci/pr-ci.sh`](ops/ci/pr-ci.sh), which runs
[`ops/ci/check.sh`](ops/ci/check.sh) and leaves a local, unsigned evidence
bundle in the workspace under `target/jankurai/evidence/<commit>/`. Run it locally with
`bash scripts/ci-local.sh pr-ci`. GitHub is a publishing mirror only and runs
no workflows. The local-CI contract is documented in
[`docs/ci-local.md`](docs/ci-local.md).

## Layout

| Path | Role |
| --- | --- |
| `.github/` | issue/PR templates, CODEOWNERS, and agent instructions (no workflows) |
| `.jeryu/` | local Jeryu repo and public-mirror metadata |
| `ops/` | CI, release, signing, deploy, and security entrypoints |
| `scripts/` | local CI runner, doctor, and split-metadata helpers |
| `agent/` | machine-readable owner, test, boundary, and generated-zone maps |
| `docs/` | architecture, testing, boundaries, release, and exception docs |
| `action.yml` | composite GitHub Action that installs the auditor |
| `jankurai-installer.sh` | standalone installer published with each release, vendored byte-for-byte from the hub |
| `agent/vendor/` | hub-installer lock and the vendored release-signing public key ([provenance](docs/release-signing.md)) |

## Documentation

- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
- [Boundaries](docs/boundaries.md)
- [Release process](docs/release.md)
- [Agent exceptions and overrides](docs/exceptions.md)
- [Running CI locally](docs/ci-local.md)
