#!/usr/bin/env python3
"""Konvertuje .txt podatke u C nizove za ugradnju u .elf.
board2.txt i sabloni: vrednosti razdvojene zarezom, jedan red po liniji.
seg90.txt i crnitop.txt: jedna vrednost po liniji.
"""
import os, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT  = os.path.join(REPO, "src", "vitis", "app")

def read_csv_grid(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip().rstrip(",")
            if not line:
                continue
            rows.append([int(float(v)) for v in line.split(",")])
    w = len(rows[0])
    for r in rows:
        assert len(r) == w, "%s: neujednacena sirina reda" % path
    return [v for r in rows for v in r], w, len(rows)

def read_flat(path):
    with open(path) as f:
        vals = [int(float(l.strip())) for l in f if l.strip()]
    return vals

def downsample2x(px, w, h):
    ow, oh = w // 2, h // 2
    out = []
    for y in range(oh):
        for x in range(ow):
            s = (px[(2*y)*w + 2*x] + px[(2*y)*w + 2*x + 1]
                 + px[(2*y+1)*w + 2*x] + px[(2*y+1)*w + 2*x + 1])
            out.append((s + 2) >> 2)  # +2 = zaokruzivanje (v. tb.cpp:tb_vp::downsample2x)
    return out, ow, oh

def emit(fh, name, vals, per_line=16):
    fh.write("const unsigned char %s = {\n" % name)
    for i in range(0, len(vals), per_line):
        fh.write("    " + ",".join("%3d" % v for v in vals[i:i+per_line]) + ",\n")
    fh.write("};\n\n")

TMPL_NAMES = ["Belakraljica","Belikonj","Belikralj","Belilovac","Belipesak","Belitop",
              "Crnakraljica","Crnikonj","Crnikralj","Crnilovac","Crnipesak","Crnitop"]

def main():
    data_dir = os.path.join(REPO, "src", "hls", "data", "data")
    tb_dir   = os.path.join(REPO, "src", "vhdl", "tb")

    img, iw, ih = read_csv_grid(os.path.join(data_dir, "board2.txt"))
    assert (iw, ih) == (720, 720), "slika nije 720x720 nego %dx%d" % (iw, ih)
    with open(os.path.join(OUT, "data_board.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        emit(f, "BOARD_IMG[%d]" % len(img), img)

    fulls, coarses, fw, fh_, cw, ch = [], [], [], [], [], []
    for n in TMPL_NAMES:
        px, w, h = read_csv_grid(os.path.join(data_dir, n + "template.txt"))
        cpx, ccw, cch = downsample2x(px, w, h)
        fulls.append(px); fw.append(w); fh_.append(h)
        coarses.append(cpx); cw.append(ccw); ch.append(cch)

    with open(os.path.join(OUT, "data_tmpl.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        for i, px in enumerate(fulls):
            emit(f, "TMPL_FULL_%d[%d]" % (i, len(px)), px)
        for i, px in enumerate(coarses):
            emit(f, "TMPL_COARSE_%d[%d]" % (i, len(px)), px)
        f.write("const unsigned char *const TMPL_FULL[12] = {%s};\n"
                % ",".join("TMPL_FULL_%d" % i for i in range(12)))
        f.write("const unsigned char *const TMPL_COARSE[12] = {%s};\n"
                % ",".join("TMPL_COARSE_%d" % i for i in range(12)))
        f.write("const int TMPL_FULL_W[12]   = {%s};\n" % ",".join(map(str, fw)))
        f.write("const int TMPL_FULL_H[12]   = {%s};\n" % ",".join(map(str, fh_)))
        f.write("const int TMPL_COARSE_W[12] = {%s};\n" % ",".join(map(str, cw)))
        f.write("const int TMPL_COARSE_H[12] = {%s};\n" % ",".join(map(str, ch)))

    seg  = read_flat(os.path.join(tb_dir, "seg90.txt"))
    tmpl = read_flat(os.path.join(tb_dir, "crnitop.txt"))
    assert len(seg) == 8100, "seg90 ima %d, ocekivano 8100" % len(seg)
    assert len(tmpl) == 375, "crnitop ima %d, ocekivano 375" % len(tmpl)
    with open(os.path.join(OUT, "data_golden.c"), "w") as f:
        f.write('#include "data.h"\n\n')
        emit(f, "GOLD_SEG[8100]", seg)
        emit(f, "GOLD_TMPL[375]", tmpl)

    print("OK: slika %dx%d, 12 sablona, zlatni vektor %d/%d" %
          (iw, ih, len(seg), len(tmpl)))

if __name__ == "__main__":
    main()
