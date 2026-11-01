# 0002: The release-tag bound parses tags exactly, under one pre-release policy

- **Date:** 2026-11-01
- **Status:** Accepted

## Context

`scripts/release-tag-bound.sh` closes the hub installer's open-ended
release-key pin: the Action refuses a key-signed tag outside
`[release_signer_first_tag, release_signer_last_tag]` from
`agent/vendor/hub-installer.lock` before anything is downloaded
(`docs/release-signing.md`).

Its first version compared tags the way `jankurai-installer.sh` does:

```sh
patch="${patch%%[!0-9]*}"
printf '%d' $(( major * 1000000 + minor * 1000 + patch ))
```

Two properties of that comparison are wrong for a gate.

1. **Arbitrary suffixes were truncated.** The tag pattern allowed any
   `[.-]`-introduced suffix and the parser then dropped everything after the
   patch digits, so `v1.7.5abc`, `v1.7.5.99` and `v1.7.5+anything` all compared
   equal to `v1.7.5` and passed the bound, while naming a release the key has
   not signed and nobody reviewed. What makes a pre-release acceptable was never
   written down; it was whatever the truncation happened to drop.
2. **The packed number collided.** Each field had 1000 values of room, so
   `v1.6.1001` equalled `v1.7.1` and `v1.7.1001` equalled `v1.8.1`. A range
   ending at `v1.7.1001` therefore accepted `v1.8.1`, three minor releases past
   the key's work, and a tag could be waved past the keyless cut-off by picking
   a patch number above 999.

A gate whose comparison is approximate is not a bound. This record also fixes
the ordering question the old code left to accident: where a pre-release sits
relative to its release.

## Decision

`scripts/release-tag-bound.sh` parses and orders tags exactly, under an
explicit pre-release policy.

- **Grammar.** `vMAJOR.MINOR.PATCH`, optionally followed by one pre-release of
  `-alpha.N`, `-beta.N` or `-rc.N`. Every number is 1–9 digits with no leading
  zeros (9 digits also keeps the comparison inside shell integer arithmetic).
  Everything else — other suffix words, build metadata, a second pre-release
  part, dot-introduced suffixes, surrounding whitespace, a missing `v` — is
  refused as an invalid version tag, not truncated.
- **Ordering.** Tags compare as the tuple
  `(major, minor, patch, pre-release rank, pre-release number)`, field by field,
  with `alpha < beta < rc < the release itself`. No two distinct tags compare
  equal, and no field can overflow into another.
- **Pre-releases sort below their release.** `v1.7.5-rc.1` is inside a range
  that ends at `v1.7.5`; `v1.7.2-rc.1` is *outside* a range that starts at
  `v1.7.2`, because what the key signed is the release, not its candidates.
- **Narrower than the installer, never wider.** `jankurai-installer.sh` is the
  hub's bytes and cannot be edited here, so its wider pattern stays as it is.
  This bound is a subset of it: every tag this script accepts the installer also
  parses, and every tag the installer would read loosely this script refuses
  first. The failure direction is always "not installed".
- **One keyless cut-off, shared with the installer authority.** The last keyless
  release lives in one place in this script (`keyless_last=v1.7.1`) and
  `scripts/release-tag-bound-test.sh` reads it and the vendored installer's own
  cut-off and fails if they drift apart, so a key-signed tag can never be waved
  through as keyless.

`scripts/forge-gate-test.sh` proves `action.yml` runs the bound **and** the
installer, in that order. The previous check compared line numbers in a single
`awk` rule and exited successfully when `action.yml` had no installer line at
all, so an action that dropped the install step — or moved it somewhere the
bound does not guard — passed. The check now requires both `run:` lines to
exist with the bound first, and the test exercises the checker against fixtures
missing either step and against a reversed pair.

Nothing here relaxes signature verification or widens which releases are
eligible: the key pin, the cosign verification in the installer, and the
reviewed range in the lock are unchanged.

## Consequences

- Tags outside the policy now fail with `invalid version tag` instead of being
  silently read as a neighbouring release. A release process that wants another
  pre-release form (`-pre.1`, build metadata) must extend the grammar here, in
  a reviewed change, and say so in a new record.
- `v1.7.2-rc.1` and other candidates of the range's first release are refused.
  If a candidate of the first release ever has to be installable, the lock's
  `release_signer_first_tag` is the place to say so.
- `scripts/release-tag-bound-test.sh` carries the negative cases (malformed
  tags, both collision pairs, a lock whose range ends outside the policy) and is
  run by the required lane through `ops/ci/required.sh`.
