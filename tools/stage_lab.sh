#!/bin/bash
# LAB BUILD -> one gh-pages commit on the remote tip: lab/ <- build/web of this clone (VER=0.26.0-lab<N>).
# Root (live), staging/ and everything else stay untouched; CNAME untouched. This script does NOT push:
# it prints the push command for whoever publishes (05 Handoff/handoffs/LAB-BUILD-PLAN 2026-11-23.md).
# Usage (from the clone root, after a Web export into build/web):  VER=0.26.0-lab1 bash tools/stage_lab.sh
set -e
R="$(cd "$(dirname "$0")/.." && pwd)"
T="${R}-ghpages"
SRC="$R/build/web"
: "${VER:?set VER, e.g. VER=0.26.0-lab1}"
[ -f "$SRC/index.pck" ] || { echo "no $SRC/index.pck: export Web first"; exit 1; }
cd "$R"; git fetch -q origin gh-pages
TIP=$(git rev-parse origin/gh-pages)
git worktree remove --force "$T" 2>/dev/null || rm -rf "$T"
git worktree prune
git worktree add -q --detach "$T" "$TIP"
cd "$T"; git config core.autocrlf false
rm -rf lab; mkdir -p lab; cp -r "$SRC/"* lab/
find lab -name '*.import' -delete
git add -A lab
git -c core.autocrlf=false commit -q -m "gh-pages: lab/ = ${VER} (lab $(git -C "$R" rev-parse --short HEAD)); root and staging/ untouched"
BAD=$(git diff --name-only "$TIP" HEAD | grep -v '^lab/' || true)
[ -z "$BAD" ] || { echo "TOUCHED OUTSIDE lab/:"; echo "$BAD" | head; exit 1; }
echo "TIP   $TIP"; echo "BUILT $(git rev-parse HEAD)"; git diff --stat "$TIP" HEAD | tail -1
echo root:; git ls-tree -l HEAD | grep ".pck$" || true
echo staging:; git ls-tree -l HEAD:staging | grep ".pck$" || true
echo lab:; git ls-tree -l HEAD:lab | grep ".pck$"
echo "CNAME: $(cat CNAME)"
echo "NOT PUSHED. To publish (fast-forward only, never force):"
echo "  git -C \"$T\" push origin HEAD:gh-pages"
