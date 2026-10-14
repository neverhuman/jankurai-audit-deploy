# GitHub deployment tooling

GitHub is a publishing mirror only: it runs no workflows for this repository.
CI runs on the forge (see [ci-local.md](ci-local.md)). Release binaries are
built on our build hosts and signed with a release key we hold by the hub
(`root/jankurai`, `ops/release/`); v1.7.2 was the first key-signed release. This
repository keeps the deployment helpers, the installer and composite action,
and the historical extraction tools independently editable.

`bash ops/ci/check.sh` (the body of the forge `required` lane) runs deployment
script validation, `action.yml` lint, secret scanning, a CycloneDX software bill
of materials with a vulnerability scan, and the ratchet audit against protected
main. Full Rust, proof, conformance, UX, and release-platform checks run against
the hub's locked family. The obsolete monolithic workflow definitions are
preserved in `docs/legacy-workflows/` for history; nothing runs them.
