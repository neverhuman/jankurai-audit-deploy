#!/usr/bin/env bash
# Explicit host-owner provisioning. Input is the independently verified,
# adopted signed release digest, never a gate user's home authority stamp.
set -euo pipefail
fail() { echo "auditor-anchor: $*" >&2; exit 1; }
[[ $# == 1 && "$1" =~ ^[0-9a-f]{64}$ ]] || fail 'usage: sudo bash ops/ci/install-auditor-anchor.sh <verified-binary-sha256>'
[[ "$(id -u)" == 0 ]] || fail 'host-owner provisioning requires root'
for path in / /etc; do
  [[ -d "$path" && ! -L "$path" ]] || fail "unsafe directory: $path"
  read -r owner mode < <(stat -c '%u %a' -- "$path")
  [[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $path"
done
anchor_dir=/etc/jankurai
anchor=/etc/jankurai/auditor.sha256
[[ ! -L "$anchor_dir" ]] || fail "symlink refused: $anchor_dir"
if [[ ! -e "$anchor_dir" ]]; then install -d -o root -g root -m 0755 "$anchor_dir"; fi
[[ -d "$anchor_dir" ]] || fail "not a directory: $anchor_dir"
read -r owner mode < <(stat -c '%u %a' -- "$anchor_dir")
[[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $anchor_dir"
[[ ! -L "$anchor" ]] || fail "symlink refused: $anchor"
if [[ -e "$anchor" ]]; then
  [[ -f "$anchor" ]] || fail "not a regular file: $anchor"
  read -r owner mode < <(stat -c '%u %a' -- "$anchor")
  [[ "$owner" == 0 ]] && (( (8#$mode & 8#022) == 0 )) || fail "unsafe ownership/mode: $anchor"
  [[ "$(cat -- "$anchor")" == "$1" ]] || fail 'anchor already adopts another digest; rotation requires a separate host-owner action'
else
  pending="$(mktemp "$anchor_dir/.auditor.XXXXXX")"
  trap 'rm -f -- "$pending"' EXIT
  printf '%s\n' "$1" > "$pending"
  chmod 0644 "$pending"
  # Do not clobber an anchor installed concurrently by another owner process.
  ln -- "$pending" "$anchor" || fail 'anchor appeared concurrently; inspect and rerun'
fi
printf 'auditor-anchor: adopted %s at %s\n' "$1" "$anchor"
