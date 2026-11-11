#!/bin/sh
# Fetch the pinned QuestieDB Forever data into local/questie/<commit>/ (git-ignored).
# Usage: tools/fetch-questie.sh <commit>
set -eu
COMMIT="${1:?usage: fetch-questie.sh <commit>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO/local/questie/$COMMIT"
BASE="https://raw.githubusercontent.com/Questie/QuestieDB/$COMMIT"
FILES="data/Forever/foreverQuestDB.lua data/Forever/foreverNpcDB.lua data/Forever/foreverItemDB.lua data/Forever/foreverObjectDB.lua support/Forever/QuestXP/xpDB-classic.lua support/Forever/QuestXP/xpDB-traces.lua"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for f in $FILES; do
  curl -fsSL "$BASE/$f" -o "$TMP/$(basename "$f")"
done
(cd "$TMP" && shasum -a 256 $(for f in $FILES; do basename "$f"; done) > SHA256SUMS)

if [ -d "$DEST" ]; then
  if (cd "$DEST" && diff -q SHA256SUMS "$TMP/SHA256SUMS" >/dev/null 2>&1); then
    echo "already present with identical hashes: $DEST"
    exit 0
  fi
  echo "refusing to overwrite $DEST: existing hashes differ" >&2
  exit 1
fi
mkdir -p "$DEST"
cp "$TMP"/*.lua "$TMP/SHA256SUMS" "$DEST/"
echo "fetched into $DEST"
