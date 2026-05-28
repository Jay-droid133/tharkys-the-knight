#!/usr/bin/env python3
"""Dev server for the web wrapper with aggressive no-cache headers.

`python -m http.server` lets the browser cache the .wasm, which makes it
look like code changes "do nothing" after a rebuild. This server forces a
fresh fetch on every request and sets the correct WASM mime type.

Usage:  python serve_web.py [port]   (default 8766)
Serves: build-web/bin/  (the Emscripten output dir)
"""
import http.server
import os
import socketserver
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build-web", "bin")


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        return super().guess_type(path)


class Server(socketserver.TCPServer):
    allow_reuse_address = True


with Server(("", PORT), NoCacheHandler) as httpd:
    print(f"serving {ROOT} at http://localhost:{PORT}/tharkys.html (no-cache)")
    httpd.serve_forever()
