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

# Full local check: fast lane, security scan, release gate, and self-audit.
just check
```

The full command surface lives in the root [`Justfile`](Justfile). Continuous
integration runs the same lanes under
[`.github/workflows/`](.github/workflows); the local-CI contract is documented in
[`docs/ci-local.md`](docs/ci-local.md).

## Layout

| Path | Role |
| --- | --- |
| `.github/` | thin GitHub Actions workflows delegating to `ops/ci/*.sh` |
| `.jeryu/` | local Jeryu repo and public-mirror metadata |
| `ops/` | CI, release, signing, deploy, and security entrypoints |
| `scripts/` | local CI runner, doctor, and split-metadata helpers |
| `agent/` | machine-readable owner, test, boundary, and generated-zone maps |
| `docs/` | architecture, testing, boundaries, release, and exception docs |
| `action.yml` | composite GitHub Action that installs the auditor |
| `jankurai-installer.sh` | standalone installer published with each release, vendored byte-for-byte from the hub |

## Documentation

- [Architecture](docs/architecture.md)
- [Testing](docs/testing.md)
- [Boundaries](docs/boundaries.md)
- [Release process](docs/release.md)
- [Agent exceptions and overrides](docs/exceptions.md)
- [Running CI locally](docs/ci-local.md)
