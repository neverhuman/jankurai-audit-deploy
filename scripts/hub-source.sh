#!/usr/bin/env bash
# Locate the hub repository so the vendored installer and release keys can be
# compared with the hub's own bytes at the commits agent/vendor/hub-installer.lock
# names. Sourced by scripts/check-vendored-installer.sh and its negative test.
#
# Which repository is the hub is fixed here, in code: HUB_REPO below. It is not
# read from agent/vendor/hub-installer.lock, which any pull request can edit; the
# lock's source_repo must equal HUB_REPO (scripts/check-vendored-installer.sh).
#
# Where the hub comes from, in order:
#   1. JANKURAI_HUB: a local hub checkout or bare clone (by hand only; the
#      required lane unsets it).
#   2. ../jankurai: the sibling checkout of the family layout, used only when its
#      origin is the hub URL derived in 3 (so a directory that merely has the
#      name, such as a clone of a mirror or a fork, is not the hub).
#   3. A fresh clone of JANKURAI_HUB_URL (by hand only) or, without it, of the hub
#      at the same place as this repository's own origin: origin must be
#      <base>/root/jankurai-deploy[.git] or the scp-like
#      <user@host>:root/jankurai-deploy[.git], and the hub is <base>/root/jankurai
#      in the same form. Any other origin (a GitHub mirror under another owner, a
#      fork) derives nothing, so a renamed or claimable name is never cloned. No
#      host is written here.
# A candidate is used only when it holds every commit asked for, reachable from
# its main branch, so a commit that only exists on some other ref of the hub
# (an unmerged branch, a pull-request ref) never counts as the hub's. For the
# sibling, "main" is refs/remotes/origin/main only (the forge gate refreshes it
# from the forge before every run), never a local branch.
#
# Nothing here decides to skip the comparison; the caller fails closed when no
# candidate qualifies.

HUB_REPO=root/jankurai

# hub_main_ref <git dir> -> the ref naming the hub's main branch, or nothing.
hub_main_ref() {
  local ref refs=(refs/heads/main refs/remotes/origin/main)
  [[ "$1" != ../jankurai ]] || refs=(refs/remotes/origin/main)
  for ref in "${refs[@]}"; do
    if git -C "$1" rev-parse -q --verify "${ref}^{commit}" >/dev/null 2>&1; then
      printf '%s\n' "$ref"
      return 0
    fi
  done
  return 1
}

# hub_holds <git dir> <commit>... -> 0 when every commit is on the hub's main.
hub_holds() {
  local dir="$1" ref commit
  shift
  ref="$(hub_main_ref "$dir")" || return 1
  for commit in "$@"; do
    git -C "$dir" cat-file -e "${commit}^{commit}" 2>/dev/null || return 1
    git -C "$dir" merge-base --is-ancestor "$commit" "$ref" 2>/dev/null || return 1
  done
}

# derived_hub_url -> the hub URL derived from this checkout's origin, or nothing.
derived_hub_url() {
  local origin owner="${HUB_REPO%%/*}"
  origin="$(git config --get remote.origin.url 2>/dev/null)" || return 1
  [[ "$origin" =~ ^(.*[/:])([A-Za-z0-9_.-]+)/jankurai-deploy(\.git)?/?$ && "${BASH_REMATCH[2]}" == "$owner" ]] || return 1
  printf '%s%s%s\n' "${BASH_REMATCH[1]}" "$HUB_REPO" "${BASH_REMATCH[3]}"
}

# hub_url -> the URL to clone the hub from (JANKURAI_HUB_URL by hand), or nothing.
hub_url() {
  if [[ -n "${JANKURAI_HUB_URL:-}" ]]; then
    printf '%s\n' "$JANKURAI_HUB_URL"
    return 0
  fi
  derived_hub_url
}

# same_remote <url> -> the URL without a trailing / or .git, for comparison.
same_remote() { local url="${1%/}"; printf '%s\n' "${url%.git}"; }

# sibling_is_hub <dir> -> 0 when <dir>'s origin is the derived hub URL.
sibling_is_hub() {
  local expected origin
  expected="$(derived_hub_url)" || return 1
  origin="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1
  [[ "$(same_remote "$origin")" == "$(same_remote "$expected")" ]]
}

# hub_resolve <scratch dir> <commit>... -> prints the hub git dir.
# On failure prints the reasons to stderr and returns 1.
hub_resolve() {
  local scratch="$1" url
  shift
  if [[ -n "${JANKURAI_HUB:-}" ]]; then
    hub_holds "$JANKURAI_HUB" "$@" && { printf '%s\n' "$JANKURAI_HUB"; return 0; }
    echo "JANKURAI_HUB=${JANKURAI_HUB} does not hold $* on its main branch" >&2
    return 1
  fi
  if [[ -d ../jankurai/.git ]] && sibling_is_hub ../jankurai && hub_holds ../jankurai "$@"; then
    printf '%s\n' ../jankurai
    return 0
  fi
  url="$(hub_url)" || {
    echo "no hub source: no sibling ../jankurai cloned from the derived hub holds the commits on origin/main, and this checkout's origin is not <base>/${HUB_REPO%%/*}/jankurai-deploy, so no hub URL is derived (by hand: JANKURAI_HUB or JANKURAI_HUB_URL)" >&2
    return 1
  }
  rm -rf "${scratch:?}/hub.git"
  if ! GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=false SSH_ASKPASS=false GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}" \
    timeout 300 git clone --quiet --bare --single-branch --branch main --no-tags "$url" "$scratch/hub.git" 2>"$scratch/hub-clone.err"; then
    echo "could not clone the hub from ${url}:" >&2
    sed 's/^/  /' "$scratch/hub-clone.err" >&2
    return 1
  fi
  hub_holds "$scratch/hub.git" "$@" && { printf '%s\n' "$scratch/hub.git"; return 0; }
  echo "the hub at ${url} does not hold $* on main" >&2
  return 1
}
