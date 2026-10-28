# 0001: The forge gate's score floor is 85

- **Date:** 2026-10-28
- **Status:** Accepted
- **Decided by:** alton (repository owner)

## Context

The forge `required` lane (`ops/ci/pr-ci.sh` -> `ops/ci/check.sh`) used to run
`jankurai audit --mode ratchet` against protected `main`: a head failed if it
scored even one point below `main`. On 2026-10-14 `main` scored 94 under the
governed auditor, so the effective floor was 94.

Moving CI off GitHub Actions and onto the forge (removing
`.github/workflows/`) costs score that has nothing to do with the deploy
tooling itself: the auditor had credited build-speed text inside the deleted
workflow files. Every honest version of that change scores 92 under the
governed auditor, so under the ratchet it could never pass.

A ratchet pinned to `main`'s current score is a near-ceiling, not a
threshold: any change that removes credited text, however correct, is
refused, and the only remedy is an override of the required check.

## Decision

The gate enforces a fixed score floor of **85** instead of "no lower than
`main`".

- `agent/audit-policy.toml` `minimum_score = 85` is the floor, and the only
  place it is set.
- `ops/ci/check.sh` runs `jankurai audit --mode standard --full`. A head fails
  if it scores below `minimum_score`, has any critical or high finding
  (`fail_on`), or the audit's conformance decision is `block`.
- The head is still compared with protected `main` under the same auditor
  (`ops/ci/prepare-baseline.sh`, `--baseline`). The comparison is written to
  the report as `decision.ratchet` (score delta, new caps, new hard findings)
  for reviewers, but it no longer fails the head.
- `scripts/forge-gate-test.sh` pins the `--mode standard` audit line and
  refuses a `--fail-under` in `check.sh`, so the floor cannot silently move
  out of the policy file.

## Consequences

- The CI-move change (score 92) passes. A later change may lower the score
  toward 85 without an override; reviewers see the drop in the head's report
  (`.jankurai/repo-score.json`, `decision.ratchet.score_delta`).
- A critical or high finding still fails the head at any score, as it did
  under the ratchet. What no longer fails the head is a lower score than
  `main`, or a new score cap, while the score stays at or above 85.

## Known limit: the auditor identity check is self-attesting

`ops/ci/auditor.sh` accepts the governed `jankurai` when its SHA-256 equals
`binary_sha256` in the host's authority stamp. Both the binary and the stamp
live in the gate user's home and are writable by that user, which includes the
pull request's own shell. The check therefore proves that the binary is the one
the host's install recorded, not where that binary came from: anything able to
replace the binary can rewrite the stamp to match. This decision does not
change that. The follow-up is the jankurai todo "jankurai-deploy gate: anchor
the auditor digest outside the gate user's home", which compares the binary
against a digest the gate user cannot write.

## How to change the floor

1. Edit `minimum_score` in `agent/audit-policy.toml`. Nothing else holds the
   number.
2. Add a decision record here (the next number), saying who decided, why and
   what the new floor is, and mark this one superseded.
3. Run `bash ops/ci/check.sh` (or `just check`) and open a pull request.

Raising the floor above `main`'s current score makes every head fail until the
score is raised. To go back to a ratchet against `main`, change the audit line
in `ops/ci/check.sh` to `--mode ratchet` and the matching check in
`scripts/forge-gate-test.sh`, in the same pull request as a new record.
