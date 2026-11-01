#!/usr/bin/env bash
# Explicit host-owner provisioning. Input is the independently verified,
# adopted signed release digest, never a gate user's home authority stamp.
set -euo pipefail
fail() { echo "auditor-anchor: $*" >&2; exit 1; }
# shellcheck source=ops/ci/auditor.sh
source "$(dirname "${BASH_SOURCE[0]}")/auditor.sh"
action=install
if [[ "${1:-}" == --stage || "${1:-}" == --retire ]]; then
  action="${1#--}"; shift
  [[ $# == 2 && "$1" =~ ^[0-9a-f]{64}$ && "$2" =~ ^[0-9a-f]{64}$ && "$1" != "$2" ]] ||
    fail 'usage: --stage|--retire <old-sha256> <new-sha256> (distinct verified digests)'
else
  [[ $# == 1 && "$1" =~ ^[0-9a-f]{64}$ ]] || fail 'usage: <verified-binary-sha256> or --stage|--retire <old-sha256> <new-sha256>'
fi
[[ "$(id -u)" == 0 ]] || fail 'host-owner provisioning requires root'
file_uid_mode / >/dev/null || fail 'unsupported platform: GNU or BSD stat is required'
for path in / /etc; do
  [[ -d "$path" && ! -L "$path" ]] || fail "unsafe directory: $path"
  read -r owner mode < <(file_uid_mode "$path")
  [[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $path"
done
anchor_dir=/etc/jankurai
anchor=/etc/jankurai/auditor.sha256
[[ ! -L "$anchor_dir" ]] || fail "symlink refused: $anchor_dir"
if [[ ! -e "$anchor_dir" ]]; then install -d -o root -g 0 -m 0755 "$anchor_dir"; fi
[[ -d "$anchor_dir" ]] || fail "not a directory: $anchor_dir"
read -r owner mode < <(file_uid_mode "$anchor_dir")
[[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $anchor_dir"
# Serialize owner actions. A crash leaves the lock for explicit owner inspection.
lock="$anchor_dir/.auditor.lock"
mkdir -m 0700 "$lock" || fail "owner operation active or interrupted; inspect $lock"
pending=
trap '[[ -z "$pending" ]] || rm -f -- "$pending"; rmdir -- "$lock"' EXIT
[[ ! -L "$anchor" ]] || fail "symlink refused: $anchor"
current=
if [[ -e "$anchor" ]]; then
  [[ -f "$anchor" ]] || fail "not a regular file: $anchor"
  read -r owner mode < <(file_uid_mode "$anchor")
  [[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $anchor"
  current="$(cat -- "$anchor")"
  valid_anchor_digests "$current" || fail 'malformed existing anchor'
fi
case "$action" in
  install)
    desired="$1"
    [[ -z "$current" || "$current" == "$desired" ]] || fail 'existing adoption differs; use --stage then --retire'
    ;;
  stage)
    desired="$(printf '%s\n%s' "$1" "$2")"
    [[ "$current" == "$1" || "$current" == "$desired" ]] || fail 'stage requires the expected old adoption'
    ;;
  retire)
    desired="$2"
    pair="$(printf '%s\n%s' "$1" "$2")"
    [[ "$current" == "$pair" || "$current" == "$desired" ]] || fail 'retire requires the expected staged adoption'
    ;;
esac
if [[ "$current" != "$desired" ]]; then
  pending="$(mktemp "$anchor_dir/.auditor.XXXXXX")"
  printf '%s\n' "$desired" > "$pending"
  chmod 0644 "$pending"
  # Same-filesystem rename: readers see the complete old or new adoption.
  mv -f -- "$pending" "$anchor"
fi
printf 'auditor-anchor: %s at %s\n' "$action" "$anchor"
