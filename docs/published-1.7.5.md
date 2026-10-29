# Published 1.7.5 evidence

Verified 2026-10-29 against the public GitHub release API and downloaded assets.
This is public availability/integrity evidence, not a new publishing action.

- [Release page](https://github.com/neverhuman/jankurai-audit/releases/tag/v1.7.5)
- [Public API record](https://api.github.com/repos/neverhuman/jankurai-audit/releases/tags/v1.7.5)
- Release ID: `413074879`; tag: `v1.7.5`; draft: false; prerelease: false.
- Published: `2026-10-14T18:58:31Z`.
- Installer size: `11163` bytes; SHA-256:
  `828e513628080823a9afaa19eeaeee4ce2e54174483a11cdde00073dbafb895f`.
- The downloaded installer matches this repository's vendored installer exactly.
- Its cosign bundle verifies against the already reviewed, vendored release key
  with SHA-256 `99f48af11e4e6463544652ddfaefb0e9953de15fb0802b174123ac2907ff06fc`.
  The key was not taken on trust from the download. No private key was used.

Reproduce from this repository using the pinned cosign 3.1.3 executable:

```bash
set -euo pipefail
mkdir -p target/publication-v1.7.5
curl --fail --silent --show-error --location \
  https://api.github.com/repos/neverhuman/jankurai-audit/releases/tags/v1.7.5 \
  --output target/publication-v1.7.5/release.json
jq -e '.id == 413074879 and .tag_name == "v1.7.5" and .draft == false and .prerelease == false' \
  target/publication-v1.7.5/release.json
for asset in jankurai-installer.sh jankurai-installer.sh.sha256 jankurai-installer.sh.cosign.bundle; do
  curl --fail --silent --show-error --location \
    "https://github.com/neverhuman/jankurai-audit/releases/download/v1.7.5/$asset" \
    --output "target/publication-v1.7.5/$asset"
done
(cd target/publication-v1.7.5 && sha256sum --check jankurai-installer.sh.sha256)
cmp jankurai-installer.sh target/publication-v1.7.5/jankurai-installer.sh
"$HOME/.local/bin/cosign-3.1.3" verify-blob \
  target/publication-v1.7.5/jankurai-installer.sh \
  --bundle target/publication-v1.7.5/jankurai-installer.sh.cosign.bundle \
  --key agent/vendor/release-keys/jankurai-release-2026.pub \
  --insecure-ignore-tlog=true --offline=true
```

The last options match the existing pinned-key release scheme: verification is
against the trusted release key, without an external transparency log claim.
This procedure verifies the installer; that installer separately verifies the
selected product archive before installation. An offline consistency gate
cannot establish public release availability, which is why this online readback
is recorded separately. Keep signature checks enabled for explicit rollbacks
as described in [install.md](install.md).
