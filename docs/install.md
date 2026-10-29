# Deploy Install Notes

Status: split deploy install note
Owner: Jankurai maintainers
Last reviewed: 2026-06-12
Applies to: `jankurai-deploy`

The deploy repo does not install from local core source. It publishes and
verifies release artifacts produced from the hub `family.lock`.

Use the hub installer for users. `jankurai-installer.sh` here is a
byte-identical copy of the hub's installer (see `agent/vendor/hub-installer.lock`),
so it defaults to the family release and keeps the hub's rename-aware signer
identity; `bash scripts/ci-local.sh required` fails if it drifts from the hub's
bytes. From `v1.7.2` on, releases are verified against one pinned
release-signing key; where that pin comes from, how this repo checks it and how
it rotates is in [`release-signing.md`](release-signing.md).

The command below and the `action.yml` `release-tag` default name `v1.7.5`, the
newest published release (`published_release` in the lock). It now equals the
family release `v1.7.5`, which the hub has published with signed assets; the
required lane checks both agree with the lock.

Running this repository's own `jankurai-installer.sh` without `--tag` (or
`JANKURAI_RELEASE_TAG`) uses the installer's default, `v1.7.5`, because it is the
hub's file byte for byte, so no `--tag` is needed to install the published release.

```bash
curl -fsSL https://github.com/neverhuman/jankurai-audit/releases/download/v1.7.5/jankurai-installer.sh \
  | bash
```

Use the hub fusion workspace for source builds:

```bash
cd ../jankurai
./scripts/fuse.sh --source local --all
.fusion/dev.sh build
```
