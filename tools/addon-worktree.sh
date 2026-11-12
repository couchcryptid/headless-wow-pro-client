#!/bin/sh
# Add a detached worktree of the WoW-Pro addon at <ref> under this repo's
# local/addon/<slug>/ (git-ignored), for Red/Green anchor runs (design spec §9).
# Usage: tools/addon-worktree.sh <ref> [addon_path]
#   <slug> is <ref> with '/' replaced by '-' (fix/u-step-loot-result -> fix-u-step-loot-result).
#
# The user's main checkout is the game's AddOns folder and follows whatever
# branch is checked out there, so this script only ever runs
# `git worktree add --detach`: it never checks out, switches, resets or commits in
# the main checkout or any other worktree. `--detach` also means a branch already
# checked out elsewhere (the main checkout's own branch) can still be pinned here.
# An existing path is refused rather than reused or overwritten.
set -eu
REF="${1:?usage: addon-worktree.sh <ref> [addon_path]}"
ADDON="${2:-$HOME/Projects/WoW-Pro-Guides}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="$(printf '%s' "$REF" | tr '/' '-')"
DEST="$REPO/local/addon/$SLUG"

if [ ! -f "$ADDON/WoWPro/WoWPro.toc" ]; then
  echo "addon-worktree: not a WoW-Pro checkout: $ADDON" >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  echo "addon-worktree: refusing existing path: $DEST" >&2
  exit 1
fi
COMMIT="$(git -C "$ADDON" rev-parse --verify --quiet "$REF^{commit}")" || {
  echo "addon-worktree: unknown ref in $ADDON: $REF" >&2
  exit 1
}
mkdir -p "$REPO/local/addon"
git -C "$ADDON" worktree add --detach --quiet "$DEST" "$COMMIT"
echo "$DEST $COMMIT"
