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
identity; `bash scripts/ci-local.sh required` fails if it drifts. Pass
`JANKURAI_RELEASE_TAG` only to install something other than the default:

```bash
curl -fsSL https://github.com/neverhuman/jankurai-audit/releases/download/v1.7.2/jankurai-installer.sh \
  | bash
```

Use the hub fusion workspace for source builds:

```bash
cd ../jankurai
./scripts/fuse.sh --source local --all
.fusion/dev.sh build
```
