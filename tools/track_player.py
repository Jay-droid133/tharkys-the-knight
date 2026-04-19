#!/usr/bin/env python3
"""
Watcher: conecta a ZEsarUX por ZRCP (puerto 10000) y vuelca la posicion
del player a code/_player_pos.json cada ~100ms para que el level editor
pueda dibujar un marcador en tiempo real.

Direcciones resueltas dinamicamente desde code/juego.map (regenerado por
sjasmplus en cada build), asi sobrevive a cambios de layout.
Simbolos consultados:
  EntityTable     (slot 0 = player; +3=PosX, +4=PosY)
  CurrentScreenX  (CurrentScreenY = +1)
  GameState

Salida JSON:
  { "screenX": int, "screenY": int, "posX": int, "posY": int,
    "gameState": int, "ts": float }

Si ZEsarUX no esta arriba, reintenta hasta que aparezca.
"""
import socket
import json
import time
import os
import sys
import re

HOST = '127.0.0.1'
PORT = 10000
POLL_HZ = 10                                # 10 lecturas/seg
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CODE_DIR   = os.path.normpath(os.path.join(SCRIPT_DIR, '..', 'code'))
OUT_FILE   = os.path.join(CODE_DIR, '_player_pos.json')
TMP_FILE   = OUT_FILE + '.tmp'
MAP_FILE   = os.path.join(CODE_DIR, 'juego.map')

# Fallbacks — solo se usan si juego.map no se puede leer (poco probable).
FALLBACK_ADDRS = {
    'ENTITYTABLE':    0x80A7,
    'GAMESTATE':      0x80A6,
    'CURRENTSCREENX': 0x81D5,
}


def parse_map_file(path):
    """Devuelve dict {SYMBOL: addr} a partir del .map de sjasmplus.

    Formato (3 columnas + nombre): '000080A7 000080A7 00 ENTITYTABLE'
    Solo nos quedamos con la primera columna (LMA) que es la direccion final.
    """
    out = {}
    if not os.path.exists(path):
        return out
    line_re = re.compile(r'^([0-9A-Fa-f]+)\s+[0-9A-Fa-f]+\s+\S+\s+(\S+)\s*$')
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            m = line_re.match(line)
            if m:
                addr = int(m.group(1), 16)
                out[m.group(2).upper()] = addr
    return out


def resolve_addresses():
    syms = parse_map_file(MAP_FILE)
    def get(name):
        if name in syms: return syms[name]
        addr = FALLBACK_ADDRS.get(name)
        print(f'[track_player] WARN: {name} no encontrado en juego.map, '
              f'usando fallback 0x{addr:04X}', flush=True)
        return addr
    addrs = {
        'ENTITY0':    get('ENTITYTABLE'),
        'GAMESTATE':  get('GAMESTATE'),
        'SCREEN_XY':  get('CURRENTSCREENX'),
    }
    print(f'[track_player] addrs: ENTITY0=0x{addrs["ENTITY0"]:04X} '
          f'GAMESTATE=0x{addrs["GAMESTATE"]:04X} '
          f'SCREEN_XY=0x{addrs["SCREEN_XY"]:04X} '
          f'(de {MAP_FILE if syms else "fallbacks"})', flush=True)
    return addrs


def connect_with_retry():
    """Bloquea hasta tener un socket conectado y el banner consumido."""
    while True:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect((HOST, PORT))
            # drena banner hasta primer prompt
            buf = b''
            while b'command> ' not in buf:
                chunk = s.recv(4096)
                if not chunk:
                    raise ConnectionError('socket cerrado durante banner')
                buf += chunk
            print(f'[track_player] conectado a {HOST}:{PORT}', flush=True)
            return s
        except (ConnectionError, OSError, socket.timeout):
            print('[track_player] esperando ZEsarUX...', flush=True)
            time.sleep(1.0)


def cmd(sock, c, timeout=0.4):
    """Envia comando ZRCP y devuelve la respuesta sin el prompt final."""
    sock.sendall((c + '\r\n').encode())
    sock.settimeout(timeout)
    out = b''
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                raise ConnectionError('socket cerrado')
            out += chunk
            if b'command> ' in out:
                break
        except socket.timeout:
            break
    return out.decode(errors='replace').replace('command>', '').strip()


def read_bytes(sock, addr, length):
    """Devuelve list[int] o None si la respuesta no parsea."""
    resp = cmd(sock, f'read-memory {addr} {length}')
    # Respuesta ZEsarUX: hex puro tipo "FE0238F318"
    hexstr = ''.join(c for c in resp if c in '0123456789abcdefABCDEF')
    if len(hexstr) < length * 2:
        return None
    try:
        return [int(hexstr[i*2:i*2+2], 16) for i in range(length)]
    except ValueError:
        return None


def atomic_write_json(payload):
    with open(TMP_FILE, 'w', encoding='utf-8') as f:
        json.dump(payload, f, separators=(',', ':'))
    os.replace(TMP_FILE, OUT_FILE)


def main():
    period = 1.0 / POLL_HZ
    addrs = resolve_addresses()
    print(f'[track_player] escribiendo {OUT_FILE} a {POLL_HZ} Hz', flush=True)
    sock = connect_with_retry()
    last_emit = (None, None, None, None)

    while True:
        t0 = time.monotonic()
        try:
            ent = read_bytes(sock, addrs['ENTITY0'], 5)    # 5 bytes
            scr = read_bytes(sock, addrs['SCREEN_XY'], 2)
            gst = read_bytes(sock, addrs['GAMESTATE'], 1)
            if ent and scr and gst:
                pos_x, pos_y = ent[3], ent[4]
                screen_x, screen_y = scr[0], scr[1]
                key = (screen_x, screen_y, pos_x, pos_y)
                if key != last_emit:
                    atomic_write_json({
                        'screenX': screen_x,
                        'screenY': screen_y,
                        'posX':    pos_x,
                        'posY':    pos_y,
                        'gameState': gst[0],
                        'ts': time.time(),
                    })
                    last_emit = key
        except (ConnectionError, OSError, socket.timeout):
            print('[track_player] conexion perdida, reintentando...', flush=True)
            try: sock.close()
            except Exception: pass
            sock = connect_with_retry()
            last_emit = (None, None, None, None)

        # rate-limit
        dt = time.monotonic() - t0
        if dt < period:
            time.sleep(period - dt)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('[track_player] bye')
        sys.exit(0)
