# -*- coding: utf-8 -*-
"""Izdvaja SVG iz svake <figure> u zaseban HTML radi snimanja u PNG."""
import io, os, re

HTML = r"C:\Users\pc\Desktop\PSDS\PSDS Vault\Projects\NCC_Akcelerator\02 Dokumentacija\PSDS_dokumentacija_y25-g10_Korak2-8.html"
OUT  = os.path.dirname(os.path.abspath(__file__))
s = io.open(HTML, encoding="utf-8").read()

stil = re.search(r"<style>(.*?)</style>", s, re.S)
stil = stil.group(1) if stil else ""

figure = re.findall(r"<figure\b.*?</figure>", s, re.S)
print("figura:", len(figure))

SKALA = 2  # dvostruko za ostrinu

for i, f in enumerate(figure, 1):
    svg = re.search(r"<svg\b.*?</svg>", f, re.S)
    if not svg:
        print(i, "nema svg"); continue
    svg = svg.group(0)
    vb = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
    w, h = float(vb.group(1)), float(vb.group(2))
    cap = re.search(r"<figcaption[^>]*>(.*?)</figcaption>", f, re.S)
    cap = re.sub(r"<[^>]+>", "", cap.group(1)).strip() if cap else ""
    svg = re.sub(r"<svg\b", '<svg width="%d" height="%d"' % (w*SKALA, h*SKALA), svg, count=1)
    doc = ("<!doctype html><meta charset='utf-8'><style>%s\n"
           "html,body{margin:0;padding:0;background:#fff}</style>%s" % (stil, svg))
    io.open(os.path.join(OUT, "fig%d.html" % i), "w", encoding="utf-8").write(doc)
    io.open(os.path.join(OUT, "fig%d.txt" % i), "w", encoding="utf-8").write(
        "%d %d\n%s" % (w*SKALA, h*SKALA, cap))
    print("fig%d  %dx%d  %s" % (i, w*SKALA, h*SKALA, cap[:60]))
