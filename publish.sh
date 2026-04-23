#!/usr/bin/env bash
# Publish to main with private requires swapped for public shims.
# Run from the bazutils repo root on the dev branch.

set -euo pipefail

cleanup() {
    git checkout - 2>/dev/null || true
    git stash pop 2>/dev/null || true
}
trap cleanup ERR

TMPDIR=$(mktemp -d)
cp -r . "$TMPDIR"

FILES=(BazaarUtility.lua data.lua init.lua binds.lua tlo.lua)
for f in "${FILES[@]}"; do
    sed -i \
        -e "s|require('lib.lawlgames.lg-logger')|require('bazutils.lib.logger')|g" \
        -e "s|require('lib.lawlgames.lg-fs')()|require('bazutils.lib.easyfs')|g" \
        "$TMPDIR/$f"
done

git stash
git checkout main
mkdir -p lib
cp "$TMPDIR"/*.lua .
cp "$TMPDIR"/lib/* lib/
git add -A
git commit -m "release: sync from dev"
git push origin main
git checkout -
git stash pop

rm -rf "$TMPDIR"
echo "Done."
