# -*- coding: utf-8 -*-
"""Sastavlja PSDS_dokumentacija_y25-g10_Korak2-8.docx iz HTML izvora.

.docx je ZIP sa WordprocessingML delovima. Pravi se rucno jer na ovoj masini
nema pandoc-a, LibreOffice-a ni python-docx-a.
"""
import io, os, struct, sys, zipfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from html2docx import (Citac, Para, Table, Slika, Prelom, Run,
                       xml_runs, xml_para, xml_table)

SCRATCH = os.path.dirname(os.path.abspath(__file__))
HTML = r"C:\Users\pc\Desktop\PSDS\PSDS Vault\Projects\NCC_Akcelerator\02 Dokumentacija\PSDS_dokumentacija_y25-g10_Korak2-8.html"
IZLAZ = r"C:\Users\pc\Desktop\PSDS\PSDS Vault\Projects\NCC_Akcelerator\02 Dokumentacija\PSDS_dokumentacija_y25-g10_Korak2-8.docx"

EMU_PO_TWIP = 635
SIRINA_TEKSTA = 9638          # A4 (11906) minus 2 x 1134 twips margine


def png_dim(putanja):
    """Sirina i visina PNG-a iz IHDR zaglavlja."""
    with open(putanja, "rb") as f:
        glava = f.read(24)
    if glava[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("nije PNG: " + putanja)
    return struct.unpack(">II", glava[16:24])


# ---------------------------------------------------------------- stilovi
STILOVI = u"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr>
  <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
  <w:sz w:val="21"/><w:szCs w:val="21"/><w:lang w:val="sr-Latn-RS"/>
</w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>
</w:docDefaults>

<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
  <w:name w:val="Normal"/><w:qFormat/></w:style>

<w:style w:type="paragraph" w:styleId="Telo">
  <w:name w:val="Telo teksta"/><w:basedOn w:val="Normal"/><w:qFormat/>
  <w:pPr><w:jc w:val="both"/></w:pPr></w:style>

<w:style w:type="paragraph" w:styleId="Naslov1">
  <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Telo"/>
  <w:qFormat/><w:pPr><w:outlineLvl w:val="0"/>
  <w:spacing w:before="360" w:after="180"/><w:keepNext/></w:pPr>
  <w:rPr><w:b/><w:sz w:val="34"/><w:color w:val="1F3864"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Naslov2">
  <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Telo"/>
  <w:qFormat/><w:pPr><w:outlineLvl w:val="1"/>
  <w:spacing w:before="300" w:after="150"/><w:keepNext/>
  <w:pBdr><w:bottom w:val="single" w:sz="4" w:space="3" w:color="B4C6E7"/></w:pBdr></w:pPr>
  <w:rPr><w:b/><w:sz w:val="27"/><w:color w:val="1F3864"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Naslov3">
  <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Telo"/>
  <w:qFormat/><w:pPr><w:outlineLvl w:val="2"/>
  <w:spacing w:before="240" w:after="120"/><w:keepNext/></w:pPr>
  <w:rPr><w:b/><w:sz w:val="23"/><w:color w:val="2E5496"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Stavka">
  <w:name w:val="Stavka liste"/><w:basedOn w:val="Normal"/><w:qFormat/>
  <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>
  <w:spacing w:after="60"/><w:jc w:val="both"/></w:pPr></w:style>

<w:style w:type="paragraph" w:styleId="Celija">
  <w:name w:val="Celija tabele"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:spacing w:before="40" w:after="40" w:line="240" w:lineRule="auto"/></w:pPr>
  <w:rPr><w:sz w:val="18"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Natpis">
  <w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:qFormat/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="60" w:after="180"/></w:pPr>
  <w:rPr><w:i/><w:sz w:val="18"/><w:color w:val="595959"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Slika">
  <w:name w:val="Slika"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="180" w:after="0"/><w:keepNext/></w:pPr></w:style>

<w:style w:type="paragraph" w:styleId="Razmak">
  <w:name w:val="Razmak"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr>
  <w:rPr><w:sz w:val="10"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Kod">
  <w:name w:val="Kod"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:spacing w:before="120" w:after="120" w:line="240" w:lineRule="auto"/>
  <w:ind w:left="284"/><w:shd w:val="clear" w:fill="F5F5F5"/>
  <w:pBdr><w:left w:val="single" w:sz="12" w:space="6" w:color="B4C6E7"/></w:pBdr></w:pPr>
  <w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="NaslovnaPredmet">
  <w:name w:val="Naslovna predmet"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="2400" w:after="240"/></w:pPr>
  <w:rPr><w:caps/><w:sz w:val="24"/><w:color w:val="595959"/><w:spacing w:val="60"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="NaslovnaNaslov">
  <w:name w:val="Naslovna naslov"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="240" w:after="240"/>
  <w:pBdr><w:top w:val="single" w:sz="6" w:space="12" w:color="1F3864"/>
  <w:bottom w:val="single" w:sz="6" w:space="12" w:color="1F3864"/></w:pBdr></w:pPr>
  <w:rPr><w:b/><w:sz w:val="44"/><w:color w:val="1F3864"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="NaslovnaPodnaslov">
  <w:name w:val="Naslovna podnaslov"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:after="480"/></w:pPr>
  <w:rPr><w:i/><w:sz w:val="24"/><w:color w:val="404040"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="NaslovnaMeta">
  <w:name w:val="Naslovna meta"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:jc w:val="center"/><w:spacing w:before="240"/></w:pPr>
  <w:rPr><w:sz w:val="24"/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Sadrzaj1">
  <w:name w:val="toc 1"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:spacing w:before="120" w:after="0"/><w:ind w:left="0"/></w:pPr>
  <w:rPr><w:b/></w:rPr></w:style>

<w:style w:type="paragraph" w:styleId="Sadrzaj2">
  <w:name w:val="toc 2"/><w:basedOn w:val="Normal"/>
  <w:pPr><w:spacing w:before="0" w:after="0"/><w:ind w:left="454"/></w:pPr>
  <w:rPr><w:color w:val="404040"/></w:rPr></w:style>
</w:styles>
"""

NUMBERING = u"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>
<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="&#8226;"/>
<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="454" w:hanging="284"/></w:pPr>
<w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" w:hint="default"/></w:rPr></w:lvl>
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>"""


def xml_slika(s, rid, dok_id):
    w_px, h_px = png_dim(s.putanja)
    # PNG je snimljen u dvostrukoj rezoluciji; logicka sirina je pola.
    sirina_tw = min(SIRINA_TEKSTA, int(w_px / 2 * 15 * s.skala))
    cx = sirina_tw * EMU_PO_TWIP
    cy = int(cx * h_px / w_px)
    crtez = (
        '<w:p><w:pPr><w:pStyle w:val="Slika"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="%d" cy="%d"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
        '<wp:docPr id="%d" name="Slika %d"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>'
        '</wp:cNvGraphicFramePr>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr><pic:cNvPr id="%d" name="slika%d.png"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
        % (cx, cy, dok_id, dok_id, dok_id, dok_id, rid, cx, cy))
    natpis = ""
    if s.natpis:
        natpis = ('<w:p><w:pPr><w:pStyle w:val="Natpis"/></w:pPr>%s</w:p>'
                  % xml_runs([Run(s.natpis)]))
    return crtez + natpis


def main():
    slike = [os.path.join(SCRATCH, "fig%d.png" % i) for i in (1, 2, 3, 4)]
    formule = [os.path.join(SCRATCH, "form%d.png" % i) for i in range(1, 8)]
    for s in slike + formule:
        if not os.path.exists(s):
            raise SystemExit("nedostaje " + s)

    izvor = io.open(HTML, encoding="utf-8").read()
    c = Citac(slike, formule)
    c.feed(izvor)
    c.close()
    c._zatvori_p()

    n_p = sum(1 for b in c.blokovi if isinstance(b, Para))
    n_t = sum(1 for b in c.blokovi if isinstance(b, Table))
    n_s = sum(1 for b in c.blokovi if isinstance(b, Slika))
    print("blokova: %d pasusa, %d tabela, %d slika (4 figure + 7 formula)" % (n_p, n_t, n_s))
    if n_t != 27:
        print("UPOZORENJE: ocekivano 27 tabela, nadjeno %d" % n_t)
    if n_s != 11:
        raise SystemExit("ocekivane 4 figure + 7 formula = 11, nadjeno %d" % n_s)

    telo, veze, media, dok_id = [], [], [], 1000
    for b in c.blokovi:
        if isinstance(b, Prelom):
            telo.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
        elif isinstance(b, Para):
            telo.append(xml_para(b))
        elif isinstance(b, Table):
            telo.append(xml_table(b))
        elif isinstance(b, Slika):
            rid = "rId%d" % (100 + len(media))
            ime = "slika%d.png" % (len(media) + 1)
            media.append((ime, b.putanja))
            veze.append('<Relationship Id="%s" Type="http://schemas.openxmlformats.org/'
                        'officeDocument/2006/relationships/image" Target="media/%s"/>'
                        % (rid, ime))
            dok_id += 1
            telo.append(xml_slika(b, rid, dok_id))

    sekcija = ('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
               '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
               'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>')

    document = (
        u'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>%s%s</w:body></w:document>' % ("".join(telo), sekcija))

    content_types = (
        u'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-'
        'officedocument.wordprocessingml.numbering+xml"/>'
        '</Types>')

    root_rels = (
        u'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/officeDocument" Target="word/document.xml"/></Relationships>')

    doc_rels = (
        u'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/numbering" Target="numbering.xml"/>'
        '%s</Relationships>' % "".join(veze))

    with zipfile.ZipFile(IZLAZ, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types.encode("utf-8"))
        z.writestr("_rels/.rels", root_rels.encode("utf-8"))
        z.writestr("word/document.xml", document.encode("utf-8"))
        z.writestr("word/styles.xml", STILOVI.encode("utf-8"))
        z.writestr("word/numbering.xml", NUMBERING.encode("utf-8"))
        z.writestr("word/_rels/document.xml.rels", doc_rels.encode("utf-8"))
        for ime, put in media:
            z.write(put, "word/media/" + ime)

    print("napisano:", IZLAZ, os.path.getsize(IZLAZ), "B")


if __name__ == "__main__":
    main()
