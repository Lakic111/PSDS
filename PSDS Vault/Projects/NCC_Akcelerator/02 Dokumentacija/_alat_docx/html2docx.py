# -*- coding: utf-8 -*-
"""HTML -> .docx bez spoljnih biblioteka.

Na ovoj masini nema pandoc-a, LibreOffice-a, python-docx-a ni pip-a, pa se .docx
sastavlja rucno: to je ZIP sa WordprocessingML sadrzajem.

Pokriva: naslove (h1/h2/h3), pasuse, liste, tabele sa zaglavljem i natpisom,
podebljano/kurziv/monospace, sup/sub, i slike (PNG) na mestu SVG figura.
"""
import io, os, re, sys, zipfile
from html.parser import HTMLParser
from xml.sax.saxutils import escape

# ---------------------------------------------------------------- model
class Run:
    def __init__(self, text, b=False, i=False, mono=False, sup=False, sub=False):
        self.text, self.b, self.i, self.mono = text, b, i, mono
        self.sup, self.sub = sup, sub

class Para:
    def __init__(self, style="Telo"):
        self.style = style
        self.runs = []

class Table:
    def __init__(self):
        self.rows = []       # lista redova; red = lista celija; celija = lista Run
        self.header = 0      # broj redova zaglavlja
        self.caption = None

class Prelom:
    pass

class Slika:
    def __init__(self, putanja, natpis, skala=1.0):
        self.putanja, self.natpis = putanja, natpis
        self.skala = skala          # udeo prirodne sirine; formule su krupno
                                    # renderovane radi ostrine, pa se umanjuju


# ---------------------------------------------------------------- parser
class Citac(HTMLParser):
    def __init__(self, slike, formule=()):
        super().__init__(convert_charrefs=True)
        self.blokovi = []
        self.slike = slike          # redosled PNG putanja za <figure>
        self.br_slike = 0
        self.formule = list(formule)  # redosled PNG putanja za div.formula
        self.br_formule = 0
        self.p = None
        self.t = None
        self.red = None
        self.celija = None
        self.u_caption = False
        self.cap_buf = []
        self.b = self.i = self.mono = self.sup = self.sub = 0
        self.u_svg = 0
        self.u_figure = 0
        self.fig_cap = []
        self.u_figcaption = 0
        self.preskoci = 0           # style/script/head
        self.u_pre = 0              # <pre>: razmaci i prelomi se cuvaju
        self.div_klase = []         # stek klasa <div> radi naslovne i sadrzaja

    # --- pomocno ---
    def _dodaj(self, txt):
        if not txt:
            return
        r = Run(txt, self.b > 0, self.i > 0, self.mono > 0 or self.u_pre > 0, self.sup > 0, self.sub > 0)
        if self.celija is not None:
            self.celija.append(r)
        elif self.u_figcaption:
            self.fig_cap.append(txt)
        elif self.u_caption:
            self.cap_buf.append(r)
        elif self.p is not None:
            self.p.runs.append(r)

    def _u_divu(self, klasa):
        return any(klasa in k for k in self.div_klase)

    def _stil_naslovne(self):
        for k in reversed(self.div_klase):
            for ime, stil in (("subj", "NaslovnaPredmet"), ("title", "NaslovnaNaslov"),
                              ("sub", "NaslovnaPodnaslov"), ("meta", "NaslovnaMeta")):
                if ime in k.split():
                    return stil
        return None

    def _novi_p(self, style):
        self._zatvori_p()
        self.p = Para(style)

    def _zatvori_p(self):
        if self.p is not None and any(r.text.strip() for r in self.p.runs):
            self.blokovi.append(self.p)
        self.p = None

    # --- dogadjaji ---
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("style", "script", "head"):
            self.preskoci += 1
            return
        if self.preskoci:
            return
        if tag == "svg":
            self.u_svg += 1
            return
        if self.u_svg:
            return

        if tag == "div":
            self.div_klase.append(a.get("class") or "")
            return
        if tag == "figure":
            self.u_figure += 1
            self.fig_cap = []
        elif tag == "figcaption":
            self.u_figcaption += 1
        elif tag in ("h1", "h2", "h3"):
            self._novi_p({"h1": "Naslov1", "h2": "Naslov2", "h3": "Naslov3"}[tag])
        elif tag == "pre":
            self.u_pre += 1
            self._novi_p("Kod")
        elif tag == "p":
            self._novi_p("Telo")
        elif tag == "li":
            if self._u_divu("toc"):
                self._novi_p("Sadrzaj2" if "l2" in (a.get("class") or "") else "Sadrzaj1")
            else:
                self._novi_p("Stavka")
        elif tag == "table":
            self._zatvori_p()
            self.t = Table()
        elif tag == "caption":
            self.u_caption = True
            self.cap_buf = []
        elif tag == "tr" and self.t is not None:
            self.red = []
        elif tag in ("td", "th") and self.red is not None:
            self.celija = []
            if tag == "th":
                self.b += 1
        elif tag in ("b", "strong"):
            self.b += 1
        elif tag in ("i", "em"):
            self.i += 1
        elif tag == "code":
            self.mono += 1
        elif tag == "sup":
            self.sup += 1
        elif tag == "sub":
            self.sub += 1
        elif tag == "span" and "mono" in (a.get("class") or ""):
            self.mono += 1
        elif tag == "br":
            self._dodaj("\n")

    def handle_endtag(self, tag):
        if tag in ("style", "script", "head"):
            self.preskoci = max(0, self.preskoci - 1)
            return
        if self.preskoci:
            return
        if tag == "svg":
            self.u_svg = max(0, self.u_svg - 1)
            return
        if self.u_svg:
            return

        if tag == "div":
            k = self.div_klase.pop() if self.div_klase else ""
            self._zatvori_p()
            if "formula" in k.split():
                if self.br_formule < len(self.formule):
                    self.blokovi.append(
                        Slika(self.formule[self.br_formule], "", skala=0.58))
                self.br_formule += 1
            elif "cover" in k or "toc" in k:
                self.blokovi.append(Prelom())
            return
        if tag == "figure":
            self.u_figure = max(0, self.u_figure - 1)
            natpis = " ".join(x.strip() for x in self.fig_cap if x.strip())
            put = self.slike[self.br_slike] if self.br_slike < len(self.slike) else None
            self.br_slike += 1
            if put:
                self.blokovi.append(Slika(put, natpis))
        elif tag == "figcaption":
            self.u_figcaption = max(0, self.u_figcaption - 1)
        elif tag == "pre":
            self.u_pre = max(0, self.u_pre - 1)
            self._zatvori_p()
        elif tag in ("h1", "h2", "h3", "p", "li"):
            self._zatvori_p()
        elif tag == "caption":
            self.u_caption = False
            if self.t is not None:
                self.t.caption = self.cap_buf
        elif tag == "thead" and self.t is not None:
            self.t.header = len(self.t.rows)
        elif tag == "tr" and self.t is not None and self.red is not None:
            self.t.rows.append(self.red)
            self.red = None
        elif tag in ("td", "th") and self.celija is not None:
            self.red.append(self.celija)
            self.celija = None
            if tag == "th":
                self.b = max(0, self.b - 1)
        elif tag == "table" and self.t is not None:
            self.blokovi.append(self.t)
            self.t = None
        elif tag in ("b", "strong"):
            self.b = max(0, self.b - 1)
        elif tag in ("i", "em"):
            self.i = max(0, self.i - 1)
        elif tag == "code":
            self.mono = max(0, self.mono - 1)
        elif tag == "sup":
            self.sup = max(0, self.sup - 1)
        elif tag == "sub":
            self.sub = max(0, self.sub - 1)
        elif tag == "span" and self.mono:
            self.mono = max(0, self.mono - 1)

    def handle_data(self, data):
        if self.preskoci or self.u_svg:
            return
        if self.u_pre:
            # unutar <pre> se razmaci i prelomi cuvaju; pocetni prelom
            # posle same oznake nije deo sadrzaja
            if not (self.p and self.p.runs):
                data = data.lstrip(chr(10))
            self._dodaj(data.rstrip(chr(10)))
            return
        t = re.sub(r"\s+", " ", data)
        if (self.p is None and self.celija is None and not self.u_caption
                and not self.u_figcaption and t.strip()):
            stil = self._stil_naslovne()
            if stil:
                self.p = Para(stil)
        if t.strip() or (self.p is not None and self.p.runs):
            self._dodaj(t)


# ---------------------------------------------------------------- OOXML
def xml_runs(runs):
    out = []
    for r in runs:
        if not r.text:
            continue
        props = []
        if r.b:    props.append("<w:b/>")
        if r.i:    props.append("<w:i/>")
        if r.mono: props.append('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/>')
        if r.sup:  props.append('<w:vertAlign w:val="superscript"/>')
        if r.sub:  props.append('<w:vertAlign w:val="subscript"/>')
        rpr = "<w:rPr>%s</w:rPr>" % "".join(props) if props else ""
        delovi = r.text.split("\n")
        for k, d in enumerate(delovi):
            if k:
                out.append("<w:r><w:br/></w:r>")
            if d:
                out.append('<w:r>%s<w:t xml:space="preserve">%s</w:t></w:r>' % (rpr, escape(d)))
    return "".join(out)


def xml_para(p):
    return '<w:p><w:pPr><w:pStyle w:val="%s"/></w:pPr>%s</w:p>' % (p.style, xml_runs(p.runs))


def xml_table(t):
    sirine = []
    n = max((len(r) for r in t.rows), default=1)
    uk = 9350
    sirine = [uk // n] * n

    redovi = []
    for idx, red in enumerate(t.rows):
        celije = []
        for j in range(n):
            sadrzaj = red[j] if j < len(red) else []
            celije.append(
                '<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/></w:tcPr>'
                '<w:p><w:pPr><w:pStyle w:val="Celija"/></w:pPr>%s</w:p></w:tc>'
                % (sirine[j], xml_runs(sadrzaj)))
        zaglavlje = '<w:trPr><w:tblHeader/></w:trPr>' if idx < t.header else ""
        redovi.append("<w:tr>%s%s</w:tr>" % (zaglavlje, "".join(celije)))

    tabela = (
        '<w:tbl><w:tblPr><w:tblStyle w:val="Resetka"/>'
        '<w:tblW w:w="0" w:type="auto"/>'
        '<w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="999999"/>'
        '<w:left w:val="none" w:sz="0" w:color="auto"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
        '<w:right w:val="none" w:sz="0" w:color="auto"/>'
        '<w:insideH w:val="single" w:sz="2" w:color="CCCCCC"/>'
        '<w:insideV w:val="none" w:sz="0" w:color="auto"/>'
        '</w:tblBorders></w:tblPr>%s</w:tbl>' % "".join(redovi))

    natpis = ""
    if t.caption:
        natpis = '<w:p><w:pPr><w:pStyle w:val="Natpis"/></w:pPr>%s</w:p>' % xml_runs(t.caption)
    return tabela + natpis + '<w:p><w:pPr><w:pStyle w:val="Razmak"/></w:pPr></w:p>'


