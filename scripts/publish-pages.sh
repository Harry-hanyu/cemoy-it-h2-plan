#!/bin/bash
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
cp "$ROOT/docs/IT半年度工作规划-正式版.html" "$ROOT/public/index.html"
cp "$ROOT/docs/IT半年度工作规划-正式版.html" "$ROOT/index.html"
cd "$ROOT"
git add index.html public/index.html docs/ progress.md
git commit -m "Update IT semi-annual plan page" || echo "no changes"
git push origin main
echo "Pages: https://harry-hanyu.github.io/cemoy-it-h2-plan/"
echo "CDN:   https://cdn.jsdelivr.net/gh/Harry-hanyu/cemoy-it-h2-plan@main/index.html"
