# Boundaries

This repository is a single-purpose release and mirroring workspace for the
Jankurai split family. The machine-readable boundary manifest is
[`agent/boundaries.toml`](../agent/boundaries.toml); this document is its prose
companion.

## Owned surface

`jankurai-deploy` owns CI, release, signing, deploy, observability, and security
routing under `ops/`, the local-CI helpers under `scripts/`, the GitHub templates
under `.github/`, and the public-mirror metadata under `.jeryu/`. There is no web
surface, no PostgreSQL database, and no Python AI/data service committed in this
repo, so those stack arms of the family standard are not applicable here.

## Forbidden in this repo

The ops boundary forbids product feature code, domain policy, and direct
database writes. Those belong to the product members of the family, not to the
deploy member. The forbidden prefixes are declared in
[`agent/boundaries.toml`](../agent/boundaries.toml). Release and mirror automation
must use the Jeryu APIs/CLI for local Jeryu and merge-request work; it must not
scrape credentials or call raw local APIs.

## Generated zones

Generated output is never hand-edited. The only generated zone in this repo is
`target/` (Rust and CI build output), declared in
[`agent/generated-zones.toml`](../agent/generated-zones.toml). It is regenerated
by the build, not committed.

## Ownership and proof

- [`agent/owner-map.json`](../agent/owner-map.json) assigns an owner to every
  top-level path that exists.
- [`agent/test-map.json`](../agent/test-map.json) routes each owned path to a
  deterministic proof command.
- [`agent/proof-lanes.toml`](../agent/proof-lanes.toml) defines the runnable
  lanes; every lane command executes in this repo alone.

## Reclassification

If a future change adds a web, database, or Python surface to this repo, update
`agent/boundaries.toml` first to declare the new boundary block, then add the
matching owner, test, and proof entries before landing the code. Reclassification
follows the dated-exception process in [`docs/exceptions.md`](exceptions.md).
