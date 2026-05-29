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
WEB="$(cd "$(dirname "$0")/../web" && pwd)"
REMOTE="https://github.com/Jay-droid133/tharkys.git"
cd "$BIN"

[ -f tharkys.wasm ] && [ -f tharkys.js ] && [ -f tharkys.html ] || {
    echo "deploy_pages: missing build output in $BIN" >&2; exit 1; }
[ -f "$WEB/manifest.webmanifest" ] && [ -f "$WEB/icon-192.png" ] && [ -f "$WEB/icon-512.png" ] || {
    echo "deploy_pages: missing PWA assets in $WEB (run: python port/web/gen_icons.py)" >&2; exit 1; }

V=$(git hash-object tharkys.wasm | cut -c1-10)

# Self-update bootstrap. GitHub Pages won't let us set no-cache headers, and
# the entry index.html always lives at the same URL (/tharkys/), so a phone
# keeps serving the cached old HTML and never sees the new __BUILD_V. This
# snippet makes a stale HTML fetch version.txt (uncached) on load; if a newer
# build is live it reloads itself with ?v=<hash> — a fresh URL that bypasses
# the browser/CDN HTML cache. sessionStorage caps redirects at 3 to rule out
# any loop if an edge briefly serves a stale version.txt.
INJECT="<script>window.__BUILD_V='${V}';(function(){try{var u=new URL(location.href),c=u.searchParams.get('v'),s=window.sessionStorage,n=s?+(s.getItem('vr')||0):0;fetch('version.txt?t='+Date.now(),{cache:'no-store'}).then(function(r){return r.ok?r.text():null}).then(function(v){if(!v)return;v=v.trim();if(v===c){if(s)s.removeItem('vr');return}if(v&&n<3){if(s)s.setItem('vr',n+1);u.searchParams.set('v',v);location.replace(u.href)}}).catch(function(){})}catch(e){}})();</script>"

# CRITICAL: in sed's REPLACEMENT text, '&' means "the whole matched string" and
# '\' escapes. INJECT contains '&&' (in `if(v&&n<3)`), which sed would expand to
# the match ('<body>'), corrupting the script into `if(v<body><body>n<3)` -- a
# syntax error that silently kills the whole bootstrap (no auto-update, and
# __BUILD_V never set so the wasm loads uncached). Escape & and \ for sed.
INJECT_ESC=${INJECT//\\/\\\\}
INJECT_ESC=${INJECT_ESC//&/\\&}

# index.html = shell + cache-bust (inject version + self-update, bust the .js src).
sed -e "s#<body>#<body>${INJECT_ESC}#" \
    -e "s#src=tharkys\.js#src=tharkys.js?v=${V}#" \
    tharkys.html > index.deploy.html

H_HTML=$(git hash-object -w index.deploy.html)
H_JS=$(git hash-object -w tharkys.js)
H_WASM=$(git hash-object -w tharkys.wasm)
H_VER=$(printf '%s' "$V" | git hash-object -w --stdin)
H_MAN=$(git hash-object -w "$WEB/manifest.webmanifest")
H_I192=$(git hash-object -w "$WEB/icon-192.png")
H_I512=$(git hash-object -w "$WEB/icon-512.png")
# Entries MUST be in git's sorted (byte) order for mktree.
TREE=$(printf '100644 blob %s\ticon-192.png\n100644 blob %s\ticon-512.png\n100644 blob %s\tindex.html\n100644 blob %s\tmanifest.webmanifest\n100644 blob %s\ttharkys.js\n100644 blob %s\ttharkys.wasm\n100644 blob %s\tversion.txt\n' \
    "$H_I192" "$H_I512" "$H_HTML" "$H_MAN" "$H_JS" "$H_WASM" "$H_VER" | git mktree)
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
