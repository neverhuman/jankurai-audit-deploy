# Deploy Install Notes

Status: split deploy install note
Owner: Jankurai maintainers
Last reviewed: 2026-10-29
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

The command below and the Action default install the published `v1.7.5` release.
They match `published_release` in the vendor lock. The vendored installer also
defaults to `v1.7.5`; its verified bytes and release-key pins are unchanged.
Publication and signed-asset verification are recorded in
[`published-1.7.5.md`](published-1.7.5.md).

For an explicit rollback, select a previous qualified release in the Action's
`release-tag` input, or run the reviewed vendored installer with
`bash jankurai-installer.sh --tag v1.7.4`. Preserve the original signed artifacts;
do not replace an existing tag or bypass signature verification.

The source metadata's `auditor_version = "1.7.6"` prepares this member for the
next hub composition; it neither selects an install default nor asserts that
1.7.6 is published. `family_release = "1.7.5"` identifies the currently vendored
hub installer, and `published_release = "1.7.5"` selects the publicly available
install default. The deploy component retains its own `1.7.5-split.0` version.
Before accepting the next hub composition, the hub's validate-family gate must
bind all member auditor metadata to 1.7.6 and validate the explicitly bounded
previous-published default. The installer bytes and family_release move together
only through a reviewed sync from the new accepted hub; until then consumers
continue installing the qualified 1.7.5 artifacts.

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
