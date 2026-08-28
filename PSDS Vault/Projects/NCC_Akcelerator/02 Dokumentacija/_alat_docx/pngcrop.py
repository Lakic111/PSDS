# -*- coding: utf-8 -*-
"""Odsecanje bele ivice sa PNG-a, samo standardnom bibliotekom.

Snimak ekrana formule je uvek veci od same formule, a Word je ne bi centrirao
kako treba sa nekoliko stotina piksela belog oko nje.
"""
import struct, sys, zlib


def _delovi(bajtovi):
    i = 8
    while i < len(bajtovi):
        (n,) = struct.unpack(">I", bajtovi[i:i + 4])
        tip = bajtovi[i + 4:i + 8]
        yield tip, bajtovi[i + 8:i + 8 + n]
        i += 8 + n + 4


def _slozi(bajtovi):
    """Vraca (sirina, visina, kanali, raspakovani redovi bez filtera)."""
    w = h = None
    bit_dubina = boja = None
    sirovi = b""
    for tip, sadrzaj in _delovi(bajtovi):
        if tip == b"IHDR":
            w, h, bit_dubina, boja = struct.unpack(">IIBB", sadrzaj[:10])
        elif tip == b"IDAT":
            sirovi += sadrzaj
    if bit_dubina != 8:
        raise ValueError("podrzana je samo dubina 8 bita")
    kanali = {0: 1, 2: 3, 4: 2, 6: 4}[boja]
    podaci = zlib.decompress(sirovi)

    bpp = kanali
    duzina = w * kanali
    prethodni = bytearray(duzina)
    redovi = []
    p = 0
    for _ in range(h):
        f = podaci[p]; p += 1
        red = bytearray(podaci[p:p + duzina]); p += duzina
        if f == 1:
            for i in range(bpp, duzina):
                red[i] = (red[i] + red[i - bpp]) & 0xFF
        elif f == 2:
            for i in range(duzina):
                red[i] = (red[i] + prethodni[i]) & 0xFF
        elif f == 3:
            for i in range(duzina):
                a = red[i - bpp] if i >= bpp else 0
                red[i] = (red[i] + ((a + prethodni[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(duzina):
                a = red[i - bpp] if i >= bpp else 0
                b = prethodni[i]
                c = prethodni[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                red[i] = (red[i] + pr) & 0xFF
        elif f != 0:
            raise ValueError("nepoznat filter %d" % f)
        redovi.append(red)
        prethodni = red
    return w, h, kanali, redovi


def _upisi(putanja, w, h, kanali, redovi):
    boja = {1: 0, 2: 4, 3: 2, 4: 6}[kanali]
    sirovi = b"".join(b"\x00" + bytes(r) for r in redovi)
    def deo(tip, sadrzaj):
        return (struct.pack(">I", len(sadrzaj)) + tip + sadrzaj
                + struct.pack(">I", zlib.crc32(tip + sadrzaj) & 0xFFFFFFFF))
    with open(putanja, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(deo(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, boja, 0, 0, 0)))
        f.write(deo(b"IDAT", zlib.compress(sirovi, 9)))
        f.write(deo(b"IEND", b""))


def odseci(ulaz, izlaz, prag=245, ivica=8):
    w, h, k, redovi = _slozi(open(ulaz, "rb").read())
    def prazan(red):
        # tekst je taman na beloj podlozi, pa je crveni kanal dovoljan pokazatelj
        for x in range(0, w * k, k):
            if red[x] < prag:
                return False
        return True

    gore = 0
    while gore < h and prazan(redovi[gore]):
        gore += 1
    if gore == h:
        raise ValueError("prazna slika: " + ulaz)
    dole = h - 1
    while dole > gore and prazan(redovi[dole]):
        dole -= 1

    levo, desno = w, 0
    for y in range(gore, dole + 1):
        red = redovi[y]
        for x in range(w):
            if red[x * k] < prag:
                if x < levo: levo = x
                if x > desno: desno = x

    gore = max(0, gore - ivica); dole = min(h - 1, dole + ivica)
    levo = max(0, levo - ivica); desno = min(w - 1, desno + ivica)
    nw, nh = desno - levo + 1, dole - gore + 1
    novi = [redovi[y][levo * k:(desno + 1) * k] for y in range(gore, dole + 1)]
    _upisi(izlaz, nw, nh, k, novi)
    return nw, nh


if __name__ == "__main__":
    print(odseci(sys.argv[1], sys.argv[2]))
