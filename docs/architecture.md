# jankurai-deploy Architecture

`jankurai-deploy` is the release, signing, installer-publishing, mirroring, and
split-generator member of the Jankurai split family. It owns how the auditor is
built into signed artifacts, how those artifacts are published, and how the
local Jeryu repository is mirrored to its public GitHub counterpart. It does not
own product feature code, domain policy, or database truth; those live in the
sibling product members of the family.

The family standard it serves is:

```text
Rust core + TypeScript/React/Vite product surface + PostgreSQL truth
+ generated contracts + exception-only Python AI/data service
```

New automation in this repo is Rust-first and shell-glue second. Agents must not
add Python for repo tooling, proof lanes, product services, authorization, or
production database writes.

## Workspace ownership

| Path | Role |
| --- | --- |
| `.github/` | thin GitHub Actions workflows; every job delegates to `ops/ci/*.sh` |
| `.jeryu/` | local Jeryu repo + shadow/tag-mirror config for the public GitHub mirror |
| `ops/` | CI, release, signing, deploy, and security shell entrypoints |
| `scripts/` | local CI runner, doctor, split-metadata, and render helpers |
| `agent/` | machine-readable owner, test, boundary, generated-zone, and standard maps |
| `docs/` | architecture, boundaries, testing, release, exception, and CI-local doctrine |
| `action.yml` | the composite GitHub Action that installs the auditor |
| `jankurai-installer.sh` | the standalone installer published with each release, a byte-identical copy of the hub's |
| `VERSION` | the single source of truth for the deploy member version |

## Mirroring model

- The local Jeryu repository `root/jankurai-deploy` is authoritative.
- `neverhuman/jankurai-deploy` on GitHub is the public mirror.
- Release builds depend on immutable GitHub tags (`jankurai-deploy-v*`), never
  branches. The shadow and tag-mirror config lives in
  [`.jeryu/repo.toml`](../.jeryu/repo.toml).

## Routing

Agents should prefer [`agent/owner-map.json`](../agent/owner-map.json) and
[`agent/test-map.json`](../agent/test-map.json) for changes, then route to the
smallest proof lane in [`agent/proof-lanes.toml`](../agent/proof-lanes.toml).
The machine-readable boundary manifest is
[`agent/boundaries.toml`](../agent/boundaries.toml); its prose companion is
[`docs/boundaries.md`](boundaries.md).
