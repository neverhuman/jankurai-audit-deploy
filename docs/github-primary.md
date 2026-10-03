# GitHub deployment tooling

GitHub is a publishing mirror only: it runs no workflows. CI runs on the forge and
our own hosts, and releases are built and signed on our own servers (a separate
change introduces key-based release signing). This repository keeps the deployment
helpers and historical extraction tools independently editable.

`bash ops/ci/github-check.sh` runs deployment script validation, secret scanning,
a software bill of materials, and the default-branch
ratchet audit. Full Rust, proof, conformance, UX, and release-platform checks run
against the hub's locked family. The obsolete monolithic workflow definitions
are preserved in `docs/legacy-workflows/` for history; their missing product paths
and self-hosted runners are not public build dependencies.
