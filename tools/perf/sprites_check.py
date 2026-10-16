"""Valida el formato de los BG sprites leyendolos del .sna (sin emulador).

    python tools/perf/sprites_check.py CARPETA

Recorre BgGfxPtrById (ptr + bank por id) y comprueba en cada sprite RLE que el
stream cubre exactamente alto x ancho bytes (lo que supone la copia exacta de
LoadBgSpriteToBuffer, parche P2) y que nada pasa de BG_SPRITE_BUFFER_SIZE.
Informa de cuantos bytes se copian hoy frente a la copia exacta.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_common as pc


def banks_from_sna(path):
    d = open(path, 'rb').read()
    cur = d[49181] & 7
    banks = {5: d[27:27 + 16384], 2: d[27 + 16384:27 + 32768], cur: d[27 + 32768:27 + 49152]}
    p = 49183
    for b in range(8):
        if b not in (2, 5, cur):
            banks[b] = d[p:p + 16384]; p += 16384
    return banks, cur


def main():
    build = sys.argv[1]
    banks, cur = banks_from_sna(os.path.join(build, 'juego.sna'))
    syms = pc.load_syms(os.path.join(build, 'build.sym'))
    bufsize = syms.get('BG_SPRITE_BUFFER_SIZE', 832)

    def rd(addr, bank=None):
        if addr < 0x8000:
            return banks[5][addr - 0x4000]
        if addr < 0xC000:
            return banks[2][addr - 0x8000]
        return banks[cur if bank is None else bank][addr - 0xC000]

    tab = syms['BgGfxPtrById']
    seen, bad = set(), []
    n_rle = n_lit = old = new = longest = 0
    for i in range(256):
        ptr = rd(tab + 3 * i) | rd(tab + 3 * i + 1) << 8
        bank = rd(tab + 3 * i + 2)
        if ptr < 0xC000 or bank > 7 or (ptr, bank) in seen:
            continue
        seen.add((ptr, bank))
        H, W = rd(ptr, bank), rd(ptr + 1, bank)
        if not H:
            continue
        a, rle, W = ptr + 2, W & 0x80, W & 0x7F
        need = H * W
        if rle:
            cov = 0
            while cov < need:
                c = rd(a, bank); a += 1
                if c == 0:
                    bad.append((i, 'control 0 en el stream')); break
                if c & 0x80:
                    cov += (c & 0x7F) + 2; a += 1
                else:
                    cov += c; a += c
            if cov != need:
                bad.append((i, f'el stream cubre {cov} y no {need}'))
            n_rle += 1
        else:
            a += need; n_lit += 1
        a += 1                                       # tint
        a += 2 + rd(a, bank) * rd(a + 1, bank)       # AH, AW, attrs
        ln = a - ptr
        longest = max(longest, ln)
        new += ln
        old += (bufsize - 2) if rle else ln
        if ln > bufsize:
            bad.append((i, f'{ln} B > buffer {bufsize}'))
    print(f'sprites: {n_rle + n_lit} ({n_rle} RLE, {n_lit} literales); bytes copiados por carga: '
          f'hoy {old}, exacto {new} (-{100 - 100 * new / max(1, old):.0f} %); el mas largo {longest} B')
    print('PROBLEMAS:', bad if bad else 'ninguno')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
