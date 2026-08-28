# -*- coding: utf-8 -*-
"""Izdvaja svaku <div class="formula"> u zaseban HTML radi snimanja u PNG."""
import io, os, re

HTML = r"C:\Users\pc\Desktop\PSDS\PSDS Vault\Projects\NCC_Akcelerator\02 Dokumentacija\PSDS_dokumentacija_y25-g10_Korak2-8.html"
OUT = os.path.dirname(os.path.abspath(__file__))
s = io.open(HTML, encoding="utf-8").read()
stil = re.search(r"<style>(.*?)</style>", s, re.S).group(1)

# div.formula nema ugnjezdenih div-ova, pa je netaknuto poklapanje do </div> tacno
f = re.findall(r'<div class="formula">.*?</div>\s*(?=<)', s, re.S)
f = [x for x in f if x.count("<div") == 1]
print("formula:", len(f))

for i, x in enumerate(f, 1):
    doc = ("<!doctype html><meta charset='utf-8'><style>%s\n"
           "html,body{margin:0;padding:0;background:#fff}\n"
           ".formula{margin:0;padding:14px 8px;font-size:30px}\n"
           "</style><div id='w' style='display:inline-block'>%s</div>" % (stil, x))
    io.open(os.path.join(OUT, "form%d.html" % i), "w", encoding="utf-8").write(doc)
    tekst = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", x)).strip()
    print("form%d: %s" % (i, tekst[:90]))
