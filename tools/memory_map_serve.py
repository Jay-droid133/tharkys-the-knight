"""
memory_map_serve.py - Mini servidor HTTP stdlib que sirve el mapa de memoria.

Endpoints:
  GET    /              → memory_map_template.html (HTML autocontenido).
  GET    /data          → JSON con el modelo actual + baseline si existe.
  POST   /snapshot      → guarda el resumen actual como baseline.
  DELETE /snapshot      → descarta el baseline.
  GET    /healthz       → "ok" (para el chequeo idempotente del .bat).

Lanzar:
  python tools/memory_map_serve.py [--port 8765]

Idempotencia: el .bat antes de lanzarnos prueba TCP a 8765; si responde,
no nos relanza. Aquí sólo nos preocupamos por servir.
"""

from __future__ import annotations

import argparse
import json
import queue
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

# Importar el parser desde el mismo directorio.
TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))
from memory_map import (  # noqa: E402
    build_model, summarize, DEFAULT_SLD, DEFAULT_STATS,
    build_call_graph, propagate_heat, find_dead_code,
    cohesion_per_system, simulate_move,
)

TEMPLATE_PATH = TOOLS_DIR / "memory_map_template.html"
SNAPSHOT_PATH = TOOLS_DIR / ".memory_map_snapshot.json"

# ----------------------------------------------------------------------
# Cache del call graph: parsearlo cuesta ~1-2 s, así que lo guardamos
# y sólo lo recomputamos cuando cambia el mtime del .sld.
# ----------------------------------------------------------------------

_cached_graph: dict | None = None
_cached_graph_mtime: float | None = None
_cache_lock = threading.Lock()


def _cached_call_graph() -> dict:
    """Devuelve el grafo cacheado, recomputándolo si .sld cambió."""
    global _cached_graph, _cached_graph_mtime
    with _cache_lock:
        cur_mtime = (DEFAULT_SLD.stat().st_mtime
                     if DEFAULT_SLD.exists() else 0.0)
        if _cached_graph is None or cur_mtime != _cached_graph_mtime:
            _cached_graph = build_call_graph(DEFAULT_SLD)
            _cached_graph_mtime = cur_mtime
        return _cached_graph

# ----------------------------------------------------------------------
# Server-Sent Events: watcher del .sld + registro de subscribers.
# ----------------------------------------------------------------------

# Lista de queues, una por conexión SSE viva. Cada queue recibe los mensajes
# raw que se enviarán por el wire (ya formateados al estilo SSE).
_subscribers: list[queue.Queue] = []
_subs_lock = threading.Lock()


def _broadcast(sse_payload: str) -> None:
    with _subs_lock:
        dead: list[queue.Queue] = []
        for q in _subscribers:
            try:
                q.put_nowait(sse_payload)
            except queue.Full:
                dead.append(q)
        for q in dead:
            _subscribers.remove(q)


def _watcher_loop(poll_interval: float = 1.5) -> None:
    """Mira el mtime del .sld cada `poll_interval` segundos. Cuando cambia
    (porque sjasmplus terminó un build), notifica a todos los subscribers.
    También observa build_stats.json como fallback (a veces el .sld no se
    regenera pero el build_stats sí, ej. fast paths).
    """
    last = {p: None for p in (DEFAULT_SLD, DEFAULT_STATS)}
    while True:
        try:
            for p in last.keys():
                if not p.exists():
                    continue
                mt = p.stat().st_mtime
                if last[p] is not None and mt > last[p]:
                    payload = (
                        "event: refresh\n"
                        f"data: {json.dumps({'mtime': mt, 'src': p.name})}\n\n"
                    )
                    _broadcast(payload)
                    # No notificamos dos veces por el mismo build: actualiza
                    # los demás "last" al mtime actual para evitar redundancia.
                    for q in last.keys():
                        if q.exists():
                            last[q] = q.stat().st_mtime
                    break
                last[p] = mt
        except Exception:
            pass
        time.sleep(poll_interval)


class Handler(BaseHTTPRequestHandler):
    # Reducimos el ruido: sólo logueamos errores y peticiones que tarden mucho.
    def log_message(self, fmt, *args):  # noqa: N802
        if args and isinstance(args[0], str) and args[0].startswith(("4", "5")):
            super().log_message(fmt, *args)

    def _send(self, status: int, body: bytes, content_type: str):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _load_baseline(self) -> dict | None:
        if not SNAPSHOT_PATH.exists():
            return None
        try:
            return json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))
        except Exception:
            return None

    def do_GET(self):  # noqa: N802
        path = urlparse(self.path).path
        try:
            if path == "/" or path == "/index.html":
                if not TEMPLATE_PATH.exists():
                    self._send(500, b"template missing", "text/plain")
                    return
                self._send(200, TEMPLATE_PATH.read_bytes(),
                           "text/html; charset=utf-8")
                return
            if path == "/data":
                model = build_model(DEFAULT_SLD, DEFAULT_STATS)
                model["baseline"] = self._load_baseline()
                payload = json.dumps(model).encode("utf-8")
                self._send(200, payload, "application/json")
                return
            if path == "/snapshot":
                bl = self._load_baseline()
                if bl is None:
                    self._send(404, b'{"error":"no snapshot"}', "application/json")
                else:
                    self._send(200, json.dumps(bl).encode("utf-8"), "application/json")
                return
            if path == "/events":
                self._handle_sse()
                return
            if path == "/healthz":
                self._send(200, b"ok", "text/plain")
                return
            # ---------- v3 endpoints ----------
            if path == "/callgraph":
                g = _cached_call_graph()
                self._send(200, json.dumps(g).encode("utf-8"),
                           "application/json")
                return
            if path == "/heat":
                g = _cached_call_graph()
                payload = {"heat": propagate_heat(g)}
                self._send(200, json.dumps(payload).encode("utf-8"),
                           "application/json")
                return
            if path == "/dead":
                g = _cached_call_graph()
                dead = find_dead_code(g)
                self._send(200,
                    json.dumps({"count": len(dead), "dead": dead}).encode("utf-8"),
                    "application/json")
                return
            if path == "/cohesion":
                g = _cached_call_graph()
                payload = cohesion_per_system(g, DEFAULT_SLD)
                self._send(200, json.dumps(payload).encode("utf-8"),
                           "application/json")
                return
            self._send(404, b"not found", "text/plain")
        except Exception as exc:  # parser robust a fallos: devolvemos 500 con detalle.
            msg = f"500: {type(exc).__name__}: {exc}\n".encode("utf-8")
            self._send(500, msg, "text/plain")

    def _handle_sse(self) -> None:
        """Long-polling SSE: mantiene la conexión abierta y emite eventos
        'refresh' cuando el watcher detecta cambios en el .sld.
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")    # por si hubiera proxy.
        self.end_headers()
        q: queue.Queue = queue.Queue(maxsize=20)
        with _subs_lock:
            _subscribers.append(q)
        try:
            # Comment line de bienvenida (no es event: client reconoce que vive).
            self.wfile.write(b": memory_map sse connected\n\n")
            self.wfile.flush()
            while True:
                try:
                    payload = q.get(timeout=15)
                    self.wfile.write(payload.encode("utf-8"))
                    self.wfile.flush()
                except queue.Empty:
                    # Heartbeat cada 15 s para mantener viva la conexión.
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with _subs_lock:
                if q in _subscribers:
                    _subscribers.remove(q)

    def do_POST(self):  # noqa: N802
        path = urlparse(self.path).path
        try:
            if path == "/snapshot":
                model = build_model(DEFAULT_SLD, DEFAULT_STATS)
                summary = summarize(model)
                SNAPSHOT_PATH.write_text(
                    json.dumps(summary, indent=2), encoding="utf-8")
                self._send(200, json.dumps(
                    {"ok": True, "timestamp": summary["timestamp"]}
                ).encode("utf-8"), "application/json")
                return
            if path == "/movecost":
                # Body JSON: {system, from_bank, to_bank}
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length).decode("utf-8")
                                  if length else "{}")
                g = _cached_call_graph()
                result = simulate_move(g,
                                        body["system"],
                                        int(body["from_bank"]),
                                        int(body["to_bank"]),
                                        DEFAULT_SLD)
                self._send(200, json.dumps(result).encode("utf-8"),
                           "application/json")
                return
            self._send(404, b"not found", "text/plain")
        except Exception as exc:
            msg = f"500: {type(exc).__name__}: {exc}\n".encode("utf-8")
            self._send(500, msg, "text/plain")

    def do_DELETE(self):  # noqa: N802
        path = urlparse(self.path).path
        try:
            if path == "/snapshot":
                if SNAPSHOT_PATH.exists():
                    SNAPSHOT_PATH.unlink()
                self._send(200, b'{"ok":true}', "application/json")
                return
            self._send(404, b"not found", "text/plain")
        except Exception as exc:
            msg = f"500: {type(exc).__name__}: {exc}\n".encode("utf-8")
            self._send(500, msg, "text/plain")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--host", default="127.0.0.1")
    args = p.parse_args()

    # Lanzar watcher en daemon thread (muere automático al salir el proceso).
    watcher = threading.Thread(target=_watcher_loop, daemon=True,
                               name="sld-watcher")
    watcher.start()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"memory_map_serve: http://{args.host}:{args.port}/", flush=True)
    print(f"watching: {DEFAULT_SLD} + {DEFAULT_STATS}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
