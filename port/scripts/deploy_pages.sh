#!/usr/bin/env bash
# Deploy the web build to the public Pages repo (Jay-droid133/tharkys, branch
# main) WITH cache-busting, so the browser always fetches the latest build
# instead of reusing same-named cached files.
#
# Version = short content hash of tharkys.wasm (changes whenever the build
# changes). It's injected into the HTML as window.__BUILD_V (read by
# Module.locateFile in shell.html to load tharkys.wasm?v=<hash>) and appended
# to the tharkys.js <script src>. The files keep their real names in the repo;
# the ?v=<hash> lives only in the request URL, so GitHub Pages still serves
# them and the browser treats a new hash as a fresh URL.
#
# Uses the current repo's object store for git plumbing and pushes the result
# to the tharkys repo's main branch WITHOUT touching the working tree.
#
# usage: bash port/scripts/deploy_pages.sh
set -euo pipefail

BIN="$(cd "$(dirname "$0")/../build-web/bin" && pwd)"
REMOTE="https://github.com/Jay-droid133/tharkys.git"
cd "$BIN"

[ -f tharkys.wasm ] && [ -f tharkys.js ] && [ -f tharkys.html ] || {
    echo "deploy_pages: missing build output in $BIN" >&2; exit 1; }

V=$(git hash-object tharkys.wasm | cut -c1-10)

# index.html = shell + cache-bust (inject version, bust the .js src).
sed -e "s#<body>#<body><script>window.__BUILD_V='${V}';</script>#" \
    -e "s#src=tharkys\.js#src=tharkys.js?v=${V}#" \
    tharkys.html > index.deploy.html

H_HTML=$(git hash-object -w index.deploy.html)
H_JS=$(git hash-object -w tharkys.js)
H_WASM=$(git hash-object -w tharkys.wasm)
TREE=$(printf '100644 blob %s\tindex.html\n100644 blob %s\ttharkys.js\n100644 blob %s\ttharkys.wasm\n' \
    "$H_HTML" "$H_JS" "$H_WASM" | git mktree)
PARENT=$(git rev-parse --verify --quiet gh-pages || true)
if [ -n "$PARENT" ]; then
    COMMIT=$(printf 'Deploy web build (v=%s)\n' "$V" | git commit-tree "$TREE" -p "$PARENT")
else
    COMMIT=$(printf 'Deploy web build (v=%s)\n' "$V" | git commit-tree "$TREE")
fi
git update-ref refs/heads/gh-pages "$COMMIT"
rm -f index.deploy.html

git push "$REMOTE" gh-pages:main
echo "deployed v=${V}  ->  https://jay-droid133.github.io/tharkys/"
