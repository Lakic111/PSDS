# Korak 8 — Plan implementacije (analiza i dokumentacija)

> **Za agentske izvršioce:** OBAVEZNA POD-VEŠTINA: `superpowers:subagent-driven-development`
> (preporučeno) ili `superpowers:executing-plans` za izvršavanje task po task.
> Koraci koriste `- [ ]` sintaksu za praćenje.

**Cilj:** Proširiti PDF dokumentaciju sa Koraka 2-5 na Korake 2-8 i uskladiti postojeća
poglavlja sa RTL-om kakav JESTE (23 stanja, post-route brojke).

**Pristup:** Jedan HTML fajl je izvor; PDF se generiše headless Edge-om. Poglavlja 1-4
se ne diraju. Poglavlja 5-7 se usklađuju (tekst, dve SVG slike, sve brojke). Dodaju se
poglavlja 8/9/10, zaključak postaje 11. Svaki task se završava `grep` proverom koja
mora dati 0 pogodaka na zastarelom sadržaju.

**Tehnologije:** ručno pisan HTML + inline SVG (bez biblioteka), headless Edge za PDF.

## Globalna ograničenja

- **Merodavan izvor RTL-a:** `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd`.
  Kopija u `src/vhdl/` je identična (kapija u `create_bd.tcl`) — ne čitati je zasebno.
- **Nijedna brojka se ne prepisuje iz beleški.** Sve dolaze iz tabele §2 dizajn
  dokumenta `(C) Korak 8 - Dizajn analize (integrisani sistem).md`, koja je izvedena iz
  izveštaja pokrenutih 2026-07-26.
- **Naslovna strana ostaje bez ličnih imena** — jedina oznaka grupe je `y25-g10` u imenu
  fajla (isto kao ESL dokumentacija).
- **Jezik:** srpski, latinica, ijekavica kako je već u dokumentu. Decimalni zarez.
- **Bez mermaid-a** — nema interneta u headless renderu; svi dijagrami su ručni SVG.
- **PDF komanda** (dve potvrđene zamke):
  ```
  --headless=old --disable-gpu --no-first-run --user-data-dir=<svež temp profil>
  --virtual-time-budget=12000 --no-pdf-header-footer --print-to-pdf=<temp>\out.pdf <file:// URL>
  ```
  (a) ciljna putanja NE SME imati razmake — generiši u temp bez razmaka pa kopiraj;
  (b) `--print-to-pdf-no-header` NE radi, ispravan naziv je `--no-pdf-header-footer`.
- **Radni fajl:** `PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.html`
  (preimenuje se tek u Tasku 9 — do tada svi putevi koriste staro ime).
- ⚠️ **Pravilo celog pasusa (nađeno u Tasku 3).** Kada izmena dopunjuje postojeći tekst,
  **pročitaj ceo pasus rečenicu po rečenicu i uskladi ga u celini** — ne samo rečenice
  koje menjaš. U Tasku 3 je stara rečenica o *dvostepenoj* protočnosti preživela pored
  novog opisa *trostepene*, ostavljajući pasus samoprotivrečnim; u diff-u je bila samo
  „context" linija pa je niko nije video kao svoju. Isti rizik nose Taskovi 5-8, koji svi
  dopunjuju zatečeni tekst umesto da pišu nov.
- ⚠️ **Ista provera važi za natpise slika i tabela** (`<figcaption>`, `<caption>`) — oni
  opisuju sadržaj koji se menja, a lako se previde jer stoje odvojeno od teksta.
- ⚠️ **Provere se puštaju POSLE poslednje izmene, ne pre** (nađeno u Tasku 7). Provera je
  puštena, pa je zatim ispravljena strelica i dodat komentar sa **dvostrukom crticom** —
  što je u XML komentaru zabranjeno i obara `svgcheck.py`. Browser to ne prikazuje kao
  grešku, pa je render prošao a sintaksa ne. Redosled je: izmeni sve → pa proveri.
- ⚠️ **U XML/SVG komentarima ne sme `--`.** Kontrolna provera nad celim fajlom:
  ```bash
  python -c "import re;s=open(FILE,encoding='utf-8').read();print(sum(1 for c in re.findall(r'<!--.*?-->',s,re.S) if '--' in c[4:-3]))"
  ```
  Očekivano: **0**.

---

## Pregled fajlova

| Akcija | Fajl | Odgovornost |
|---|---|---|
| Menja | `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.html` | ceo dokument (Task 1-9) |
| Stvara | `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.html` | preimenovanjem (Task 9) |
| Stvara | `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf` | generisanjem (Task 9) |
| Menja | `BUGS.md` | pravilo o slack-u, ispravka naslova (Task 10) |
| Menja | `CLAUDE.md`, `(C) Plan implementacije (10 koraka).md`, `(C) Sljedeća sesija.md` | status (Task 10) |
| Menja | `src/vhdl/script/run_synth_core.tcl` | parametrizovati period takta (Task 10) |

---

## Task 1: Uskladiti §5.1 tekst i Tabelu 5 na 23 stanja

**Fajlovi:**
- Menja: `...Korak2-5.html:572` (tekst), `:581` (naslov Tabele 5), telo tabele ispod

**Interfejsi:**
- Proizvodi: usklađen naziv „23 stanja" koji Task 2 i Task 4 koriste dosledno.

- [ ] **Korak 1: Pročitati stvarni FSM da se potvrdi spisak stanja**

Pokreni:
```bash
grep -n "type state_t" -A 12 src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd
```
Očekivano: 23 imena, dva nova u odnosu na dokument — `S_L_YX_DRAIN2` i `S_NCC_SQ`.

- [ ] **Korak 2: Izmeniti rečenicu u §5.1**

Linija 572, zameniti `<b>21 stanjem</b>` sa `<b>23 stanja</b>`.

- [ ] **Korak 3: Izmeniti naslov Tabele 5**

Linija 581: `Svih 21 stanje kontrolne jedinice, grupisano po fazama`
→ `Svih 23 stanja kontrolne jedinice, grupisano po fazama`

- [ ] **Korak 4: Dodati dva reda u Tabelu 5**

⚠️ **Ispravka plana (nađeno pri izvršavanju):** Tabela 5 ima **četiri** kolone —
`Faza | Stanja | Broj taktova | Namena` — a HTML ispod je pisan sa tri ćelije.
Prilagodi ćelije stvarnoj tabeli: prva ćelija je faza (`<b>D</b>` / `<b>E</b>`), druga
ime stanja u `<span class="mono">`, treća **`1`** (oba nova stanja su bezuslovan
jednotaktni prelaz — potvrđeno u RTL-u), četvrta opis iz teksta ispod.

U fazu D, posle reda `S_L_YX_DRAIN`:
```html
<tr><td class="mono">S_L_YX_DRAIN2</td><td>D</td>
<td>Akumulira poslednji registrovani par <span class="mono">df_reg·dt_reg</span>;
poništava <span class="mono">mac_v</span>. Dodato u Koraku 8b uz MAC protočnost.</td></tr>
```

U fazu E, **pre** reda `S_NCC_DIV`:
```html
<tr><td class="mono">S_NCC_SQ</td><td>E</td>
<td>Provera <span class="mono">den = 0</span>; ako nije, registruje
<span class="mono">num_sq &lt;= sum_num²</span> i
<span class="mono">den_prod &lt;= sum_den_f · sum_den_t</span>. Dodato u Koraku 8b da
kvadriranje ne ulazi kombinaciono u 83-bitni delilac.</td></tr>
```

- [ ] **Korak 5: Ispraviti opis S_NCC_DIV u istoj tabeli**

Stari opis pominje kvadriranje. Zameni telo ćelije opisa za `S_NCC_DIV` sa:
```html
Startuje <span class="mono">div_ncc</span> nad registrovanim vrednostima:
<span class="mono">(num_sq &lt;&lt; 31) / den_prod</span>.
```

- [ ] **Korak 6: Ispraviti golo „21" u istom pasusu §5.1**

⚠️ **Dodato pri izvršavanju.** Linija ~578 istog pasusa glasi
`sva su &mdash; svih 21 &mdash; nabrojana u Tabeli 5`. Zameni sa `svih 23`.
Nije uhvaćeno prvobitnim `grep`-om jer niz nije „21 stanj".

- [ ] **Korak 7: Prepisati §5.6 (Faza E) — rupa u pokrivenosti plana**

⚠️ **Dodato pri izvršavanju: §5.6 nije bio dodeljen nijednom tasku**, a njegov pasus je
činjenično netačan na dva mesta posle preseka iz Koraka 8b:

(a) tvrdi da se degenerisani slučaj proverava u `S_NCC_DIV` — provera `den = 0` je
prešla u `S_NCC_SQ`;
(b) tvrdi da se `num_sq` i `den_prod` računaju **kombinaciono** — sada se **registruju**
u `S_NCC_SQ`. Reč „kombinaciono" mora nestati; ona protivreči svrsi izmene.

Nov tok koji pasus mora opisati: `S_NCC_SQ` (provera; ako nije degenerisan, registruje
`num_sq <= sum_num²` i `den_prod <= den_f · den_t`) → `S_NCC_DIV` (pomera deljenik za 31
mesto ulevo, pokreće 83-bitni delilac nad **registrovanim** vrednostima) → `S_NCC_WAIT`
(čeka signal završetka) → `S_WRITE_RESULT` (upis u mapu, pomeranje brojača prozora).

Dodati i rečenicu **zašto** je razdvojeno: putanja od kvadriranja `sum_num` do delioca
bila je najgora posle rutiranja, pa je presečena registrom.

- [ ] **Korak 8: Provera**

Pokreni:
```bash
ns=$(grep -n "21 stanj\|svih 21" <fajl> | grep -vc "figcaption\|state_reg")
echo "preostali '21' van Task 2/4 domena: $ns"
grep -c "kombinaciono računaju\|kombinaciono se računaju" <fajl>
grep -c "S_L_YX_DRAIN2\|S_NCC_SQ" <fajl>
```
Očekivano: **0**, **0**, i **najmanje 3**.

⚠️ **Ne pisati odvojene provere `grep -c "21 stanj"` = 2 i `grep -c "svih 21"` = 0** —
one se međusobno isključuju, jer `figcaption` glasi „svih 21 stanje" pa pogađa oba
obrasca. To je bila greška u prvoj verziji plana. Zato provera iznad **izuzima** linije
sa `figcaption` i `state_reg`, koje pripadaju Task-u 2 i 4.

---

## Task 2: Prepraviti ASMD dijagram (Slika 1) na 23 stanja

**Fajlovi:**
- Menja: `...Korak2-5.html:614-834` (SVG), `:835` (figcaption)

**Interfejsi:**
- Konzumira: spisak stanja iz Taska 1.
- Proizvodi: `viewBox="0 0 660 1180"` — Task 3 ne zavisi od ovoga.

**Kontekst:** SVG je ručno pisan sa apsolutnim koordinatama. Stanja su `<rect class="st">`
sa `<text class="nm">` (ime) i `<text class="op">` (operacije); prelazi su `<path class="ln">`.
Faze su pozadinski `<rect class="ph">`. Dodavanje dva stanja pomera sve ispod.

- [ ] **Korak 1: Pročitati semantiku nova dva stanja iz RTL-a**

Pokreni:
```bash
grep -n "when S_L_YX_DRAIN\b" -A 18 src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd
grep -n "when S_NCC_SQ" -A 12 src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd
```
Ključno: **provera `den = 0` je prešla u `S_NCC_SQ`**, pa se romb „den = 0 ?" u dijagramu
pomera da izlazi iz `S_NCC_SQ`, a ne iz `S_NCC_DIV`.

- [ ] **Korak 2: Proširiti viewBox i FAZA D/E pozadine**

Linija 614: `viewBox="0 0 660 1100"` → `viewBox="0 0 660 1180"`

FAZA D (bila `y="726" height="118"`) → `y="726" height="158"`;
oznaka faze `translate(80,785)` → `translate(80,805)`.

FAZA E (bila `y="846" height="200"`) → `y="886" height="240"`;
oznaka faze `translate(80,946)` → `translate(80,1006)`.

- [ ] **Korak 3: Ispraviti S_L_YX_DRAIN i dodati S_L_YX_DRAIN2**

Zameni blok `<!-- 17 S_L_YX_DRAIN -->` (linije 782-786) sa:
```html
  <!-- 17 S_L_YX_DRAIN -->
  <rect class="st" x="88" y="810" width="224" height="30" rx="4"/>
  <text class="nm" x="200" y="824" text-anchor="middle">S_L_YX_DRAIN</text>
  <text class="op" x="200" y="835" text-anchor="middle">df,dt &lt;= poslednji ; acc += df_reg&middot;dt_reg</text>
  <path class="ln" d="M200,840 L200,850"/>

  <!-- 18 S_L_YX_DRAIN2 (novo, Korak 8b) -->
  <rect class="st" x="88" y="850" width="224" height="30" rx="4"/>
  <text class="nm" x="200" y="864" text-anchor="middle">S_L_YX_DRAIN2</text>
  <text class="op" x="200" y="875" text-anchor="middle">acc += df_reg&middot;dt_reg (poslednji) ; mac_v&lt;=0</text>
  <path class="ln" d="M200,880 L200,892"/>
```

- [ ] **Korak 4: Zameniti celu FAZU E**

⚠️ **Ne koristiti brojeve linija** — Korak 3 je već ubacio ~7 linija pa je sve ispod
pomereno. Zameni po sadržaju: sve od komentara `<!-- 18 S_NCC_DIV -->` do poslednje
`<path>` linije bloka `<!-- 21 S_DONE -->` (ona koja se završava sa `L200,30 L200,44"/>`),
zaključno sa njom, sa:
```html
  <!-- 19 S_NCC_SQ (novo, Korak 8b) -->
  <rect class="st" x="88" y="892" width="224" height="30" rx="4"/>
  <text class="nm" x="200" y="906" text-anchor="middle">S_NCC_SQ</text>
  <text class="op" x="200" y="917" text-anchor="middle">num_sq&lt;=sum_num&sup2; ; den_prod&lt;=den_f&middot;den_t</text>
  <path class="ln" d="M200,922 L200,930"/>

  <!-- D5 den=0? -->
  <path class="st" d="M200,930 L258,945 L200,960 L142,945 z"/>
  <text class="lb" x="200" y="948" text-anchor="middle">den = 0 ?</text>
  <path class="lnd" d="M258,945 L398,945 L398,1103 L314,1103"/>
  <text class="lb" x="300" y="940">da &rarr; result 0</text>
  <path class="ln" d="M200,960 L200,971"/>
  <text class="lb" x="206" y="970">ne</text>

  <!-- 20 S_NCC_DIV -->
  <rect class="st" x="88" y="971" width="224" height="30" rx="4"/>
  <text class="nm" x="200" y="985" text-anchor="middle">S_NCC_DIV</text>
  <text class="op" x="200" y="996" text-anchor="middle">div_ncc start: (num_sq&lt;&lt;31)/den_prod</text>
  <path class="ln" d="M200,1001 L200,1011"/>

  <!-- 21 S_NCC_WAIT -->
  <rect class="st" x="88" y="1011" width="224" height="30" rx="4"/>
  <text class="nm" x="200" y="1025" text-anchor="middle">S_NCC_WAIT</text>
  <text class="op" x="200" y="1036" text-anchor="middle">čekaj dn_done ; result_q &lt;= dn_quot</text>
  <path class="ln" d="M200,1041 L200,1048"/>

  <!-- D6 gotovo? -->
  <path class="st" d="M200,1048 L248,1062 L200,1076 L152,1062 z"/>
  <text class="lb" x="200" y="1065" text-anchor="middle">gotovo ?</text>
  <path class="lnd" d="M248,1062 L344,1062 L344,1026 L314,1026"/>
  <text class="lb" x="342" y="1048" text-anchor="end">ne</text>
  <path class="ln" d="M200,1076 L200,1087"/>

  <!-- 22 S_WRITE_RESULT -->
  <rect class="st" x="88" y="1087" width="224" height="32" rx="4"/>
  <text class="nm" x="200" y="1101" text-anchor="middle">S_WRITE_RESULT</text>
  <text class="op" x="200" y="1113" text-anchor="middle">result_map[v&middot;res_w+u] &lt;= result_q</text>
  <path class="ln" d="M200,1119 L200,1125"/>

  <!-- D7 u+1<res_w? -->
  <path class="st" d="M200,1125 L268,1140 L200,1155 L132,1140 z"/>
  <text class="lb" x="200" y="1143" text-anchor="middle">u+1 &lt; res_w ?</text>
  <path class="lnd" d="M132,1140 L58,1140 L58,495 L88,495"/>
  <text class="lb" x="54" y="770" text-anchor="end">da</text>
  <path class="lnd" d="M200,1155 L200,1168 L44,1168 L44,420 L88,420"/>
  <text class="lb" x="150" y="1165">ne (novi red, v++)</text>

  <!-- 23 S_DONE -->
  <rect class="st" x="360" y="1124" width="140" height="30" rx="4"/>
  <text class="nm" x="430" y="1139" text-anchor="middle">S_DONE</text>
  <text class="op" x="430" y="1150" text-anchor="middle">busy&lt;=0 ; done&lt;=1</text>
  <path class="ln" d="M500,1139 L540,1139 L540,30 L200,30 L200,44"/>
```

- [ ] **Korak 5: Ispraviti figcaption**

Linija 835: `(svih 21 stanje, pet faza)` → `(svih 23 stanja, pet faza)`

- [ ] **Korak 6: Provera da je SVG i dalje ispravan XML**

⚠️ **Ne koristiti goli `xml.dom.minidom.parseString`** — pada na imenovanim HTML
entitetima (`&minus;`, `&hellip;`, `&Sigma;`, `&middot;`) koje XML ne poznaje, pa daje
**lažno pozitivnu grešku i na neizmenjenom fajlu**. Nađeno pri izvršavanju Taska 2.

Koristi pripremljenu skriptu koja prvo razrešava imenovane entitete (čuvajući pet XML
ugrađenih), pa parsira:

```bash
python "C:/Users/pc/AppData/Local/Temp/claude/C--Users-pc-Desktop-PSDS/e4bd0e98-58b3-4d2d-a0e8-57e805b7b492/scratchpad/svgcheck.py" \
  "PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.html" \
  "0 0 660 1180"
```
Očekivano: `SVG OK  (elemenata sa class="nm": 24)` — **24, ne 23**, jer klasu `nm`
koristi i elipsa „reset".

Ako skripta ne postoji (druga sesija), njena logika je: izdvoji `<svg viewBox="...">…</svg>`
regexom, zameni svaki `&ime;` osim `lt/gt/amp/quot/apos` odgovarajućim znakom preko
`html.unescape`, pa `xml.dom.minidom.parseString`.

- [ ] **Korak 6b: Vizuelna provera renderom (obavezna za SVG taskove)**

Sintaksna ispravnost ne hvata strelicu koja pokazuje u prazno. Renderuj stranicu headless
Edge-om u PNG i pogledaj Sliku 1. Naročito proveri **duge strelice definisane ranije u
SVG-u** koje ciljaju elemente pri dnu (povratne petlje ka `S_L_U_A`/`S_L_V`, i strelica sa
odluke `v >= res_h` ka `S_DONE`) — one su van bloka koji Korak 4 zamenjuje, pa im
odredište treba ručno pomeriti. Nađeno pri izvršavanju: ta strelica je pokazivala na
y=1059 umesto y=1139.

- [ ] **Korak 7: Vizuelna provera**

Otvori HTML u Edge-u i pogledaj Sliku 1: 23 pravougaonika, nijedna strelica ne visi u
prazno, nijedan tekst ne izlazi iz okvira faze, romb „den = 0 ?" izlazi iz `S_NCC_SQ`.

---

## Task 3: Prepraviti Sliku 2 (protočnost MAC petlje) na tri stepena

**Fajlovi:**
- Menja: `...Korak2-5.html:868-882` (tekst §5.5), `:883-955` (SVG Slika 2)

**Kontekst:** Slika 2 je vremenski dijagram sa tri reda (`stanje`, `izdaje adresu`,
`akumulira`). Posle MAC preseka postoji međustepen: podatak → `df/dt` registri →
množenje/akumulacija. Treba **četvrti red** i **jedna kolona više** (DRAIN2).

- [ ] **Korak 1: Ispraviti tekst §5.5**

Rečenicu koja opisuje dva stepena zameni opisom tri stepena. Konkretno, zameni deo
„a <span class="mono">S_L_YX_DRAIN</span> je prazni (akumulira poslednji podatak bez
izdavanja nove adrese). Cena je time <b>jedan takt po pikselu</b> plus jedan takt
režije po prozoru." sa:

```html
a <span class="mono">S_L_YX_DRAIN</span> i
<span class="mono">S_L_YX_DRAIN2</span> je prazne. Od Koraka 8b protočna struktura ima
<b>tri stepena</b>: izdavanje adrese, registrovanje razlika
<span class="mono">df</span>/<span class="mono">dt</span>, pa množenje i akumulacija.
Presek je uveden da bi se putanja BRAM &rarr; oduzimanje &rarr; množenje &rarr;
akumulator razdvojila na dva takta; sam je doneo <b>2,43 ns</b> vremenske rezerve
(odeljak 10.5). Cena je i dalje <b>jedan takt po pikselu</b>, uz <b>dva</b> takta
režije po prozoru umesto jednog.
```

- [ ] **Korak 2: Dodati kolonu tN+1 u zaglavlje Slike 2**

Posle `<text class="hd" x="572" y="24" ...>tN</text>` dodaj:
```html
    <text class="hd" x="644" y="24" text-anchor="middle">tN+1</text>
```
i produži liniju: `<line class="gl" x1="104" y1="30" x2="680" y2="30"/>`.
Proširi `viewBox` sa `0 0 660 210` na `0 0 700 250`.

- [ ] **Korak 3: Dodati DRAIN2 u red „stanje"**

Posle ćelije `DRAIN` (x=536) dodaj:
```html
  <rect class="cel" x="608" y="38" width="72" height="22" fill="#f0f0ee"/>
  <text class="txt" x="644" y="53" text-anchor="middle">DRAIN2</text>
```
Isto proširi i redove „izdaje adresu" (ćelija `—`, `fill="#fafafa"`) na x=608.

- [ ] **Korak 4: Ubaciti nov red „registruje df/dt" između adrese i akumulacije**

Posle reda „izdaje adresu" (y=78..100) dodaj red na y=118, a postojeći red
„akumulira" pomeri na y=158 (i njegove `<text>` sa y=132 na y=172):
```html
  <text class="hd" x="10" y="132">registruje df/dt</text>
  <rect class="cel" x="104" y="118" width="72" height="22" fill="#fafafa"/>
  <text class="txt" x="140" y="133" text-anchor="middle">—</text>
  <rect class="cel a" x="176" y="118" width="72" height="22"/>
  <text class="txt" x="212" y="133" text-anchor="middle">px 0</text>
  <rect class="cel a" x="248" y="118" width="72" height="22"/>
  <text class="txt" x="284" y="133" text-anchor="middle">px 1</text>
  <rect class="cel a" x="320" y="118" width="72" height="22"/>
  <text class="txt" x="356" y="133" text-anchor="middle">px 2</text>
  <rect class="cel a" x="392" y="118" width="72" height="22"/>
  <text class="txt" x="428" y="133" text-anchor="middle">…</text>
  <rect class="cel a" x="464" y="118" width="72" height="22"/>
  <text class="txt" x="500" y="133" text-anchor="middle">px N&minus;2</text>
  <rect class="cel a" x="536" y="118" width="72" height="22"/>
  <text class="txt" x="572" y="133" text-anchor="middle">px N&minus;1</text>
  <rect class="cel" x="608" y="118" width="72" height="22" fill="#fafafa"/>
  <text class="txt" x="644" y="133" text-anchor="middle">—</text>
```

- [ ] **Korak 5: Pomeriti red „akumulira" i dodati mu poslednju ćeliju**

Red „akumulira" ide na y=158; prva ćelija (t0) i druga (t1) su `—`, akumulacija
počinje od t2 (`px 0`), a poslednja ćelija na x=608 je `px N−1`.

- [ ] **Korak 6: Ispraviti sažetak unutar Slike 2**

⚠️ **Dodato pri izvršavanju.** Pri dnu SVG-a (~linija 964) stoji tekst:
`Ukupno: N + 1 takta za N piksela (jedan takt po pikselu + jedan takt režije).`
Zameni sa:
```html
  <text class="st2" x="104" y="164">Ukupno: N + 2 takta za N piksela (jedan takt po pikselu + dva takta režije).</text>
```
(ako je `y` drugačije zbog dodatog reda, zadrži postojeću vrednost `y` — menja se samo tekst)

- [ ] **Korak 7: Provera**

```bash
python "C:/Users/pc/AppData/Local/Temp/claude/C--Users-pc-Desktop-PSDS/e4bd0e98-58b3-4d2d-a0e8-57e805b7b492/scratchpad/svgcheck.py" \
  "PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.html" \
  "0 0 700 250"
grep -c "N + 1 takta" <fajl>
```
Očekivano: `SVG OK`, pa **0**.

Zatim **render headless Edge-om** i vizuelna provera: četiri reda, dijagonalno pomeranje
po jednu kolonu između redova (klasičan protočni obrazac), nijedna ćelija van okvira,
oznake kolona poravnate sa ćelijama ispod njih.

---

## Task 4: Uskladiti §6 (registri, funkcionalne jedinice, datapath dijagram)

**Fajlovi:**
- Menja: `...Korak2-5.html` §6.1 tabela registara, §6.2 tekst, `:1194` (datapath SVG)

- [ ] **Korak 1: Izlistati nove registre iz RTL-a**

Pokreni:
```bash
grep -nE "df_reg|dt_reg|mac_v_reg|num_sq_reg|den_prod_reg" src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/src/ncc_core.vhd | head -20
```
Očekivano: pet novih registara — `df_reg`, `dt_reg` (9-bitne razlike), `mac_v_reg`
(validnost stepena), `num_sq_reg`, `den_prod_reg` (52-bitni ulazi delioca).

- [ ] **Korak 2: Dodati pet redova u tabelu registara §6.1**

```html
<tr><td class="mono">df_reg</td><td class="n">9</td>
<td>Registrovana razlika piksela slike i srednje vrednosti prozora (MAC stepen 1).</td></tr>
<tr><td class="mono">dt_reg</td><td class="n">9</td>
<td>Registrovana razlika piksela šablona i njegove srednje vrednosti (MAC stepen 1).</td></tr>
<tr><td class="mono">mac_v_reg</td><td class="n">1</td>
<td>Validnost MAC stepena — sprečava akumulaciju u taktu punjenja.</td></tr>
<tr><td class="mono">num_sq_reg</td><td class="n">52</td>
<td>Registrovano <span class="mono">sum_num&sup2;</span> pred ulaz u delilac.</td></tr>
<tr><td class="mono">den_prod_reg</td><td class="n">52</td>
<td>Registrovan proizvod <span class="mono">den_f &middot; den_t</span> pred delilac.</td></tr>
```

- [ ] **Korak 3: Dopuniti §6.2 rečenicom o svrsi preseka**

Dodaj na kraj §6.2:
```html
<p>Pet registara iz tabele iznad (<span class="mono">df_reg</span>,
<span class="mono">dt_reg</span>, <span class="mono">mac_v_reg</span>,
<span class="mono">num_sq_reg</span>, <span class="mono">den_prod_reg</span>) nisu deo
prvobitnog dizajna &mdash; uvedeni su u Koraku 8b isključivo radi zatvaranja vremenskih
uslova, bez ikakve promene izlaza. Njihova cena je <b>+0,41 %</b> latencije i
<b>+110 flip-flopova</b>, a dobitak <b>2,59 ns</b> vremenske rezerve (odeljak 10.5).</p>
```

- [ ] **Korak 4: Ispraviti datapath dijagram**

Linija 1194: `state_reg (21 stanje)` → `state_reg (23 stanja)`

- [ ] **Korak 5: Provera**

```bash
grep -c "21 stanj" "PSDS Vault/.../PSDS_dokumentacija_y25-g10_Korak2-5.html"
```
Očekivano: **0**.

---

## Task 5: Prepisati §7 sa post-route brojkama

**Fajlovi:**
- Menja: `...Korak2-5.html:1240-1400` (§7 u celini), `:215` (ciljni uređaj), `:1418`, `:1424-1425`

**Izvor brojki:** §2.1 dizajn dokumenta. **Ne izmišljati i ne prepisivati iz starih beleški.**

- [ ] **Korak 1: Ispraviti naslov poglavlja i ciljni part**

Naslov `<h1>7. Analiza posle sinteze</h1>` → `<h1>7. Analiza posle sinteze i implementacije</h1>`

Linija 215: `<b>xc7z010-clg225-2</b>` → `<b>xc7z010clg400-1</b>` i dodaj rečenicu:
```html
Napomena: ESL dokumentacija navodi <span class="mono">xc7z010-clg225-2</span>, ali je to
bio podrazumevani part alata Vitis HLS, ne stvarna ploča &mdash; nijedna Digilent
Zynq-7010 ploča ne koristi kućište <span class="mono">clg225</span>. Isti čip i isti
kapacitet, brzinska klasa <span class="mono">-1</span> umesto <span class="mono">-2</span>.
```

Linije 1248, 1260, 1418: svako pominjanje `clg225-2` → `clg400-1`.

- [ ] **Korak 2: Zameniti Tabelu 9 (resursi)**

```html
    <tr><td>Slice LUT (sve kao logika)</td><td class="n">1.472</td><td class="n">17.600</td><td class="n">8,36 %</td></tr>
    <tr><td>Slice registri (FF)</td><td class="n">664</td><td class="n">35.200</td><td class="n">1,89 %</td></tr>
```
DSP (9 / 80 / 11,25 %), Block RAM (9 / 60 / 15,00 %) i LUT as Memory (0) ostaju.
Naslov tabele → `Utrošeni resursi posle implementacije (xc7z010clg400-1, post-route)`.

Prilagoditi i rečenicu na liniji 1274 koja koristi „8,67 %" → „8,36 %".

- [ ] **Korak 3: Zameniti tabelu timing-a**

```html
    <tr><td>Najgora vremenska rezerva (WNS) @ 11,0 ns</td><td class="n"><b>+0,387 ns</b></td></tr>
    <tr><td>Najgora vremenska rezerva (WNS) @ 10,0 ns</td><td class="n"><b>+0,146 ns</b></td></tr>
    <tr><td>Kritična putanja (@ 10,0 ns)</td><td class="n">9,832 ns<br>(logika 7,901 ns &middot; rutiranje 1,931 ns)</td></tr>
    <tr><td>Nivoa logike</td><td class="n">12 (CARRY4=10, DSP48E1=2)</td></tr>
    <tr><td><b>Maksimalna frekvencija</b></td><td class="n"><b>~101,5 MHz</b></td></tr>
```
Sva pominjanja „113 MHz" (linije 1289, 1297, 1424) → „101,5 MHz"; „+1,179 ns" → „+0,146 ns".

- [ ] **Korak 4: Dodati pasus o metodologiji merenja**

Odmah ispod tabele timing-a:
```html
<p><b>Zašto dva merenja.</b> Alat optimizuje <i>do</i> zadatog ograničenja i staje čim
ga ispuni, pa je kritična putanja na labavijem ograničenju duža: na 11,0 ns iznosi
10,638 ns sa 46 % rutiranja, a na 10,0 ns svega 9,832 ns sa 20 % rutiranja, jer je alat
kvadriranje mapirao u <span class="mono">DSP48E1</span>. Vremenska rezerva se zato
<b>ne sme aritmetički prevoditi</b> između ograničenja &mdash; maksimalna frekvencija se
navodi na osnovu merenja na ograničenju koje se tvrdi.</p>
```

- [ ] **Korak 5: Ispraviti ceo §7.4 (latencija) — više posla nego što je izgledalo**

⚠️ **Prošireno pri izvršavanju.** §7.4 ne sadrži samo ukupnu brojku nego i **razlaganje
modela `N + 110` na komponente** i Tabelu 12 izvedenu iz njega. Presek menja sve to.

**(a) Izraz za `T_prozor`** (~linija 1360): `tmp_w &middot; tmp_h + 110 taktova`
→ `tmp_w &middot; tmp_h + 112 taktova`.

**(b) Razlaganje sabirka** (~linija 1363): sada `112` čine — pet taktova za čitanje
integralne slike, oko 19 za deljenje pri računanju `f_bar`, **tri** takta za punjenje i
pražnjenje protočne strukture (`FILL`, `DRAIN`, `DRAIN2` — bilo dva), **jedan takt za
registrovanje `num_sq`/`den_prod` u `S_NCC_SQ`** (nov), oko 83 za 83-bitno deljenje i
jedan za upis rezultata.

**(c) Brojke u istom pasusu:**

| Bilo | Treba |
|---|---|
| `485 taktova po prozoru` | **487** |
| `2.432.760 taktova za svih 5.016 pozicija` | **2.442.792** |
| `faza B (769)` | 769 — **nepromenjeno** |
| `model predviđa 2.449.729` | **2.459.761** |
| `izmereno 2.451.212` | **2.461.201** |
| `odstupanje 1.483 takta` | **1.440** |
| `0,06 %` | 0,06 % — **nepromenjeno** |

**(d) Tabela 12** — zameniti tri reda:
```html
    <tr><td>C, D, E &mdash; glavna petlja</td><td class="mono">res_w·res_h·(N+112) = 66·76·487</td><td class="n">2.442.792</td><td class="n">99,3 %</td></tr>
    <tr><td>ostatak (prelazi <span class="mono">S_L_V</span>, zaokruženja modela)</td><td>&mdash;</td><td class="n">1.440</td><td class="n">0,1 %</td></tr>
    <tr><td><b>Ukupno (izmereno)</b></td><td>&mdash;</td><td class="n"><b>2.461.201</b></td><td class="n">100 %</td></tr>
```
Redovi za fazu A (16.200 / 0,7 %) i fazu B (769 / < 0,1 %) ostaju **nepromenjeni**.

**(e) Poslednji pasus §7.4** — `77 % troška po prozoru` ostaje **nepromenjeno**
(`375/487 = 77,0 %`).

**(f) Ostala mesta sa `2.451.212`** (~linije 1327, 1343): → `2.461.201`;
na liniji 1343 `1,30` → `1,31` (`2.461.201 / (5.016 · 375)`).

⚠️ **Ne koristiti brojku 2.459.742 ovde.** Dizajn dokument koristi model `2·N` za fazu B,
a ovaj dokument `2·N + 19` (uključuje deljenje) — otud 2.459.761. Obe su tačne na svom
nivou detalja; **unutar ovog dokumenta važi 2.459.761**.

**Ne tvrditi mehanizam ostatka.** Ako pasus pripisuje razliku „prozorima sa nultom
varijansom", ukloniti to — izmereno je *veće* od modela, pa preskakanje takta ne može
biti uzrok. Opisati kao zaokruženja modela i fiksnu režiju, kako Tabela 12 već kaže.

- [ ] **Korak 6: Dopuniti §7.5 verifikaciju sa dva nova testbencha**

```html
<tr><td class="mono">ncc_accel_tb</td><td>90×90 / 25×15 kroz AXI</td>
<td>peak <span class="mono">0x80000000</span> @ idx 956 &mdash; bit-identično golom jezgru</td></tr>
<tr><td class="mono">ncc_accel_burst_tb</td><td>AXI burst, <span class="mono">len=7</span></td>
<td>8/8 čitanje i upis, RLAST po beat-u, WSTRB, rani AW</td></tr>
```

- [ ] **Korak 7: Provera**

```bash
grep -c "1526\|1\.526\|1,179\|113 MHz\|2\.451\.212\|clg225-2\|8,67" "PSDS Vault/.../PSDS_dokumentacija_y25-g10_Korak2-5.html"
```
Očekivano: **0** (osim jednog dozvoljenog pominjanja `clg225-2` u napomeni iz Koraka 1,
koje je u kontekstu „ESL navodi, ali je pogrešno" — proveri ručno da je to jedini pogodak).

---

## Task 6: Novo poglavlje 8 — Pakovanje u IP jezgro

**Fajlovi:**
- Menja: `...Korak2-5.html` — umeće `<h1>8. Pakovanje u IP jezgro</h1>` posle §7, pre zaključka

**Izvor sadržaja:** `(C) Korak 6 - Dizajn AXI omotača (IP pakovanje).md` i
`src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/*.vhd`.

- [ ] **Korak 1: Napisati §8.1 — izbor obrasca**

Sadržaj: obrazac **slave + interne memorije** iz Vežbe 08-09 (matrix-multiply); zašto
NE master (vežba master interfejs uopšte ne razrađuje, a Korak 6 nosi 10 bodova koje ne
vredi rizikovati); posledica — `REG_IMG_ADDR`/`REG_TMP_ADDR` postaju rezervisani, a
`ADDR_BRAM 0x4000_0000` iz ESL modela ne postoji jer nema deljenog BRAM-a.

- [ ] **Korak 2: Napisati §8.2 — dva AXI interfejsa (tabela)**

| Interfejs | Tip | Širina adrese | Opseg | Uloga |
|---|---|---|---|---|
| `S00_AXI` | AXI4-Lite | 6 bita | 4 KB | kontrolni registri |
| `S01_AXI` | AXI4-Full | **17 bita** | 128 KB | memorije slike/šablona/rezultata |

Uz napomenu da je `C_S01_AXI_ADDR_WIDTH = 17` obavezna vrednost (`mem_addr_o` je fiksno
17-bitni port), osigurana statičkim `assert`-om u `S01_AXI.vhd`.

- [ ] **Korak 3: Napisati §8.3 — regioni unutar S01 (tabela)**

Dekodovanje `addr(16:15)`, indeks reči `addr(14:2)`, **jedan piksel po 32-bitnoj reči**:
slika `+0x00000` (8-bit × 8192), šablon `+0x08000` (8-bit × 1024), rezultat `+0x10000`
(32-bit × 8192).

- [ ] **Korak 4: Napisati §8.4 — kontrolni registri (tabela)**

`0x00` IMG_W, `0x04` IMG_H, `0x08` TMP_W, `0x0C` TMP_H, `0x30` CTRL (upis 1 = start,
jednotaktni puls), `0x34` STATUS (bit0 = `done_sticky`, bit1 = `busy`).
Napomenuti odstupanje od ESL-a: ESL je imao STATUS 0=busy/1=done.

- [ ] **Korak 5: Provera**

Otvori HTML, potvrdi da se poglavlje 8 pojavljuje posle 7 i da tabele imaju `<caption>`
sa doslednim brojevima (nastavak numeracije, ne od 1).

---

## Task 7: Novo poglavlje 9 — Integracija u sistem

**Fajlovi:**
- Menja: `...Korak2-5.html` — `<h1>9. Integracija u sistem</h1>`
- Izvor: `(C) Korak 7 - Dizajn integracije (block design).md`, `src/vhdl/script/create_bd.tcl`

- [ ] **Korak 1: Napisati §9.1 — topologija**

Zynq PS (board preset) + `proc_sys_reset` + **2× `ncc_accel`** + `axi_cdma` (mem-na-mem,
simple mode, bez SG i DRE, 32-bit, burst 256) + **jedan** `axi_interconnect` (2 mastera
→ 6 slave-ova). Jedan takt na sve → **nema CDC**, nema `set_false_path`.

Obavezno objasniti **zašto jedan interkonekt**: AXI slave interfejs može biti povezan
na samo jedan interkonekt, a `ncc.S01` mora biti dostupan i PS-u i CDMA-u.

- [ ] **Korak 2: Nacrtati SVG blok dijagram (Slika 4)**

Ručni SVG, **isti stil kao Slika 1** (klase `.st`, `.nm`, `.op`, `.ln` — kopirati blok
`<style>` iz ASMD dijagrama). Dokument već ima tri slike (1 = ASMD, 2 = protočnost,
3 = datapath/controlpath), pa je ovo **Slika 4**. Prikazati: PS sa
`M_AXI_GP0` i `S_AXI_HP0`, interkonekt kao centralni blok, dva `ncc_accel` sa po dva
porta (S00/S01), CDMA sa `S_AXI_LITE` i `M_AXI`, i `proc_sys_reset`. Strelice pokazuju
smer master→slave. Predložene dimenzije: `viewBox="0 0 660 420"`.

- [ ] **Korak 3: Napisati §9.2 — adresna mapa (tabela po masteru)**

PS `M_AXI_GP0`: `ncc0.S00` `0x5000_0000` 4K, `ncc0.S01` `0x5002_0000` 128K,
`ncc1.S00` `0x5100_0000` 4K, `ncc1.S01` `0x5102_0000` 128K,
`cdma.S_AXI_LITE` `0x6000_0000` 64K.
CDMA `M_AXI`: DDR `0x0000_0000` (iz PS preseta), `ncc0.S01`, `ncc1.S01`.

Uz tabelu poklapanja sa ESL `common.hpp` (`ADDR_NCC`, `ADDR_NCC1`, `ADDR_DMA` identični).

- [ ] **Korak 4: Napisati §9.3 — tok podataka po polju table**

Sedam koraka: provera praznog polja (CPU, iz DDR-a) → staging u DDR (1 piksel po `u32`)
→ CDMA punjenje slike u oba bloka → CDMA punjenje šablona → upis dimenzija i `CTRL=1`
→ polling `STATUS` bit0 → CDMA čitanje rezultata + `Xil_DCacheInvalidateRange`.

- [ ] **Korak 5: Napisati §9.4 — dva softverska pravila za Korak 9**

(a) **`u32` poređenje, ne `int32`** — `0x80000000` (NCC² = 1,0) je kao `int32` negativan,
pa bi egzaktno poklapanje bilo odbačeno.
(b) **Nikad CDMA i CPU nad istim S01 istovremeno** — `mem_addr_o` daje prioritet čitanju
a `mem_we_o` nije zabranjen tokom čitanja; održava se prirodno jer CPU čeka
`XAxiCdma_IsBusy`, ali mora biti zapisano.

- [ ] **Korak 6: Napisati §9.5 — zašto CDMA, pošteno**

CDMA nije performansni dobitak: po polju ~146 KB, CPU put ~3,4 ms (~7 % od ~48 ms
računanja), CDMA ~0,4 ms (~1 %) → dobitak ~6 %. Preklapanje nije moguće jer su memorije
jednostruko baferovane i `ncc_core` ih čita dok računa. Izabran je zbog pravilnika (DMA
je izričito nabrojan za ovaj korak) i zato što je popravka burst čitanja ionako bila
neophodna. **Tako i reći na odbrani.**

- [ ] **Korak 7: Provera**

XML test nad novim SVG-om (kao Task 2 Korak 6) i vizuelna provera da nijedan blok ne
preklapa drugi.

---

## Task 8: Novo poglavlje 10 — Analiza integrisanog sistema

**Fajlovi:**
- Menja: `...Korak2-5.html` — `<h1>10. Analiza integrisanog sistema</h1>`
- Izvor: §2.3, §2.4, §4, §5 dizajn dokumenta

- [ ] **Korak 1: §10.1 Metod**

`vivado.bat -mode batch -source src/vhdl/script/run_impl.tcl`, post-route + phys_opt,
strategija `Performance_ExplorePostRoutePhysOpt`. Napomenuti da su u toku **kapije**:
protiv blackbox IP-a i protiv razilaženja dve kopije izvora.

- [ ] **Korak 2: §10.2 Resursi (8a) — tabela**

| Resurs | Iskorišćeno | Kapacitet | % |
|---|---|---|---|
| Slice LUT | 6.261 | 17.600 | 35,57 % |
| Slice Registers | 5.024 | 35.200 | 14,27 % |
| Block RAM Tile | 39 | 60 | 65,00 % |
| DSP48E1 | 18 | 80 | 22,50 % |

Plus tabela po instanci (`ncc0`/`ncc1` po 1.910 LUT / 1.240 FF / 19 RAMB36 / 9 DSP;
`axi_interconnect_0` 1.616; `axi_cdma_0` 807) i poređenje sa ESL referencom.

**Obavezno reći da je BRAM naša slabost** (65 %, gore od ESL-ovih 4×BRAM_18K po instanci),
sa uzrokom (32-bitni `sat_t` gde je dovoljan 21 bit) i procenom dobitka (~3 RAMB36 po
instanci). Bolje da profesor to pročita nego da pita.

- [ ] **Korak 3: §10.3 Takt i kritična putanja (8b)**

WNS **+0,170 ns** na 11,0 ns, WHS +0,025 ns, 0/15.459 endpoint-ova krši, 0 DRC CRITICAL.
Kritična putanja `ncc1/core_inst/y_reg[0]` → `ncc1/ms_inst/img_mem/ADDRBWRADDR[13]`.

Izlaganje takta 90,909 MHz **kao odluke**: PS PLL daje 1000/11 za traženih 95 MHz;
odstupanje od nominalnih 100 MHz je 9,1 % (rubrika dozvoljava 20 %); **golo jezgro
zatvara 100 MHz** (+0,146 ns), pa je ograničenje **integracija**, ne RTL; i navesti
neiskorišćenu polugu (inkrementalno računanje adrese u unutrašnjoj petlji — izbacuje
množač iz petlje, ne menja latenciju), uz napomenu da je 62 % te putanje rutiranje pa
dobitak nije zagarantovan.

- [ ] **Korak 4: §10.4 Propusnost (8c)**

Model `T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 112)`, `N = tmp_w·tmp_h`.
Provera: `2·8100 + 2·375 + 5016·487 = 2.459.742` naspram izmerenih **2.461.201** →
**0,06 %**. Ostatak od 1.459 taktova opisati kao fiksnu režiju koju model ne obuhvata
(inicijalizacija FSM-a, sekvencijalno deljenje pri računanju srednje vrednosti šablona)
— **bez tvrdnje o tačnom mehanizmu**, nije izmeren.

| Veličina | Taktova | @ 90,909 MHz |
|---|---|---|
| 90×90 / 25×15 (izmereno) | 2.461.201 | 27,07 ms |
| 90×90 / 30×30 (ekstrapolacija) | 3.783.652 | 41,6 ms |

- [ ] **Korak 5: §10.5 Put do zatvaranja vremenskih uslova (tabela)**

| Mera | Dobitak |
|---|---|
| MAC pipeline u `ncc_core` | +2,43 ns |
| `phys_opt_design` + `Performance_ExplorePostRoutePhysOpt` | +0,481 ns |
| SmartConnect → AXI Interconnect (`STRATEGY=1`) | 8.673 → 1.616 LUT |
| Registar pred delilac | +0,155 ns |
| `S_AXI_HP0` 64 → 32 bita | −3.334 LUT / −3.659 FF, 6 → 0 konvertora |

Ukupno **−3,299 → +0,170 ns**. Napomenuti da `phys_opt_design` sam donosi više od
drugog RTL preseka, pa je deo build ugovora a ne opcija.

- [ ] **Korak 6: §10.6 Poređenje sa ESL/PEUSN referencom (8e)**

| | ESL/HLS referenca | Naš RTL |
|---|---|---|
| LUT po instanci | 5.269 | **1.910** |
| DSP po instanci | 16 | **9** |
| BRAM po instanci | 4 × BRAM_18K | 19 × RAMB36 ← slabije |
| 2× NCC LUT | 10.538 (59,9 %) | **ceo sistem** 6.261 (35,6 %) |
| Taktova, 90×90/30×30 | 10.360.183 | **3.783.652** |
| Taktova po piksel-operaciji (30×30) | 3,09 | **1,13** |

⚠️ **Brojka je 1,13, ne 1,30** (vault je grešio — 1,30 je sa 25×15). Provera:
`3,094 / 1,130 = 2,74×`, što se slaže sa odnosom taktova.
Dodati rečenicu da efikasnost po piksel-operaciji raste sa veličinom šablona (1,31 na
25×15, 1,13 na 30×30) jer se režija od 112 taktova po prozoru amortizuje.

**Ukupno vreme obrade `board2.txt` se NE poredi tabelarno** (odluka korisnika). Jedna
rečenica u tekstu: naš RTL je 2,74× efikasniji po piksel-operaciji od HLS reference na
koju je ESL `K_CYC` kalibrisan, pa sistemsko vreme nije direktno uporedivo bez
rekalibracije modela.

- [ ] **Korak 7: Provera aritmetike**

```bash
python -c "print(2*8100+2*375+5016*487, 3721*1012+16200+1800, round(3783652/(61*61*30*30),3), round(3.094/1.130,2))"
```
Očekivano: `2459742 3783652 1.13 2.74`

---

## Task 9: Zaključak, sadržaj, preimenovanje i PDF

**Fajlovi:**
- Menja: `...Korak2-5.html` (zaključak, `<h1>Sadržaj</h1>` blok na liniji 131)
- Stvara: `...Korak2-8.html`, `...Korak2-8.pdf`

- [ ] **Korak 1: Prenumerisati zaključak**

`<h1>8. Zaključak</h1>` → `<h1>11. Zaključak</h1>`.

- [ ] **Korak 2: Dopuniti zaključak**

Dodati stavke: IP spakovan i integrisan; sistem staje u 35,6 % LUT (manje nego ESL-ova
dva NCC bloka sama); zatvara na 90,909 MHz sa WNS +0,170 ns; latencija 27,07 ms za
90×90/25×15; sve verifikovano bit-tačno kroz šest testbencheva.

- [ ] **Korak 3: Ažurirati Sadržaj**

Blok od linije 131 — dodati unose za poglavlja 8, 9, 10 i promeniti 8→11 za zaključak.
Proveriti da se numeracija u Sadržaju poklapa sa `<h1>`/`<h2>` u telu.

- [ ] **Korak 4: Preimenovati oba fajla**

```bash
cd "PSDS Vault/Projects/NCC_Akcelerator/02 Dokumentacija"
git mv PSDS_dokumentacija_y25-g10_Korak2-5.html PSDS_dokumentacija_y25-g10_Korak2-8.html 2>/dev/null || mv PSDS_dokumentacija_y25-g10_Korak2-5.html PSDS_dokumentacija_y25-g10_Korak2-8.html
```
Stari `.pdf` obrisati tek posle uspešnog generisanja novog.

- [ ] **Korak 5: Generisati PDF**

```bash
TMPD=/c/Users/pc/AppData/Local/Temp/nccpdf
mkdir -p "$TMPD/profile"
"/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  --headless=old --disable-gpu --no-first-run \
  --user-data-dir="C:\\Users\\pc\\AppData\\Local\\Temp\\nccpdf\\profile" \
  --virtual-time-budget=12000 --no-pdf-header-footer \
  --print-to-pdf="C:\\Users\\pc\\AppData\\Local\\Temp\\nccpdf\\out.pdf" \
  "file:///C:/Users/pc/Desktop/PSDS/PSDS%20Vault/Projects/NCC_Akcelerator/02%20Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.html"
```
Zatim kopirati `out.pdf` na finalnu putanju (koja ima razmake — zato se generiše u temp).

- [ ] **Korak 6: Provera PDF-a**

Otvoriti PDF i proveriti: (a) nema datuma/putanje u zaglavlju ili podnožju;
(b) Slika 1 (ASMD) staje na stranu i čitljiva je; (c) Sadržaj se poklapa sa telom;
(d) nijedna tabela nije presečena na sredini reda.

- [ ] **Korak 6b: Provera unakrsnih referenci (nijedna ne sme da visi)**

⚠️ **Dodato pri izvršavanju.** Ranija poglavlja upućuju na odeljke koji nastaju tek u
Taskovima 6-8 (npr. §5.5 pominje „odeljak 10.5" i brojku 2,43 ns; §6.2 pominje 10.5;
§7.2 upućuje na 10.2). Posle Taska 9 numeracija je konačna, pa se sve mora poklopiti.

```bash
grep -noE "odeljak [0-9]+\.[0-9]+|odeljku [0-9]+\.[0-9]+|Tabel[ai] [0-9]+|Slik[ai] [0-9]+" <fajl> | sort -u
```
Za svaku referencu potvrdi da ciljni odeljak/tabela/slika **stvarno postoji** pod tim
brojem. Naročito proveri da je numeracija tabela i slika **uzastopna** — Taskovi 6-8
dodaju nove, pa se lako preskoči broj ili se dva puta upotrebi isti.

- [ ] **Korak 7: Finalna provera zastarelog sadržaja**

```bash
grep -cE "21 stanj|1\.526|\+1,179|113 MHz|2\.451\.212|2\.449\.729|1,30 takt" \
  "PSDS Vault/.../PSDS_dokumentacija_y25-g10_Korak2-8.html"
```
Očekivano: **0**.

---

## Task 10: Ažurirati vault i parametrizovati skriptu

**Fajlovi:**
- Menja: `BUGS.md`, `CLAUDE.md`, `(C) Plan implementacije (10 koraka).md`,
  `(C) Sljedeća sesija.md`, `src/vhdl/script/run_synth_core.tcl`

- [ ] **Korak 1: Ispraviti naslov u `BUGS.md`**

Naslov „`ncc_core` ne zatvara 100 MHz na `xc7z010clg400-1`" opisuje RTL **pre** preseka.
Dodati u taj odeljak:
```markdown
**Ispravka 2026-07-26:** posle dva preseka golo jezgro **zatvara 100 MHz**
(post-route OOC, WNS **+0,146 ns**, Fmax ~101,5 MHz). Ograničenje je **integracija**,
ne jezgro — `ncc_system_wrapper` na 10 ns daje −0,232 ns.
```

- [ ] **Korak 2: Dodati četvrti zapis u `BUGS.md` — pravilo o slack-u**

```markdown
## Vremenska rezerva se ne prevodi između ograničenja takta  [PRAVILO]

Merenje golog jezgra pušteno je prvo samo na 11 ns, pa su Fmax i „rezerva prema 100 MHz"
izvedeni aritmetički iz tog slack-a → 94,22 MHz i −0,613 ns. **Oboje netačno.** Alat
optimizuje *do* ograničenja i staje kad ga ispuni.

| Ograničenje | WNS | putanja | logika / rutiranje | nivoi |
|---|---|---|---|---|
| 11,0 ns | +0,387 | 10,638 ns | 5,72 / 4,92 | 16, CARRY4=9 |
| 10,0 ns | +0,146 | 9,832 ns | 7,90 / 1,93 | 12, DSP48E1=2 |

Na strožem ograničenju alat je kvadriranje mapirao u DSP48E1. **Fmax se meri na
ograničenju koje se tvrdi.** Isti obrazac kao tri ranije pogrešne hipoteze — zaključak
iz jednog merenja.
```

- [ ] **Korak 3: Ispraviti dve nasleđene greške u vault-u**

U `(C) Sljedeća sesija.md` i `(C) Plan implementacije (10 koraka).md`:
- `2.459.712` → `2.459.742`
- ukloniti objašnjenje „prozori sa nultom varijansom preskaču takt" (nemoguće: izmereno
  je *veće* od modela)
- `1,30 vs 3,09` → `1,13 vs 3,09` (1,30 je sa 25×15, ne sa 30×30)

- [ ] **Korak 4: Parametrizovati `run_synth_core.tcl`**

Sada je period fiksno 10 ns u `ncc_core_ooc.xdc`. Dodati na početak skripte:
```tcl
# Period takta u ns; podrazumevano 10,0 (100 MHz). Za radni takt sistema:
#   set NCC_PERIOD 11.0   (pre source-ovanja)
if {![info exists NCC_PERIOD]} { set NCC_PERIOD 10.0 }
```
i generisati XDC u vreme izvršavanja umesto čitanja fiksnog fajla, uz `report` oba broja.

- [ ] **Korak 5: Ažurirati status u `CLAUDE.md` i plan fajlu**

Korak 8 → `[x]` ZAVRŠENO; upisati brojke 8a-8e; sledeći korak je **Korak 9**.

- [ ] **Korak 6: Ažurirati `(C) Sljedeća sesija.md`**

Nov odeljak „PRVO za sledeću sesiju" → Korak 9 (bitstream, XSA, Vitis), sa otvorenim
pitanjem identiteta ploče (Zybo vs Zybo Z7-10) kao prvom stavkom, jer je blokirajuće.

- [ ] **Korak 7: Provera**

```bash
grep -rn "2\.459\.712\|1,30 nasp\|nultom varijansom" "PSDS Vault/Projects/NCC_Akcelerator/"
```
Očekivano: **0 pogodaka**.

---

## Redosled i zavisnosti

```
Task 1 ──► Task 2 ──┐
                    ├──► Task 9 ──► Task 10
Task 3 ─────────────┤
Task 4 ─────────────┤
Task 5 ─────────────┤
Task 6 ──► Task 7 ──► Task 8 ─┘
```

Taskovi 1-2 moraju ići redom (Task 2 koristi spisak stanja iz Taska 1).
Taskovi 3, 4, 5 su nezavisni i mogu paralelno.
Taskovi 6-7-8 idu redom (numeracija poglavlja i tabela je uzastopna).
Task 9 zahteva sve prethodne. Task 10 je poslednji.

## Kriterij završenosti celog koraka

| # | Provera | Očekivano |
|---|---|---|
| 1 | `grep -c "21 stanj"` u HTML-u | 0 |
| 2 | `grep -cE "1\.526\|1,179\|113 MHz\|2\.451\.212"` | 0 |
| 3 | Poglavlja 8, 9, 10, 11 postoje; Sadržaj se poklapa | ručna provera |
| 4 | Oba SVG-a parsiraju kao XML | `SVG OK` |
| 5 | PDF se generiše bez zaglavlja/podnožja | ručna provera |
| 6 | Aritmetika iz Taska 8 Korak 7 | `2459742 3783652 1.13 2.74` |
| 7 | Vault bez nasleđenih grešaka | 0 pogodaka |

## Šta ovaj plan NE pokriva

- Bitstream, XSA, Vitis aplikacija — **Korak 9**.
- `package_ip.tcl` i regeneracija `.zip` arhive IP-a — **Korak 10**.
- Suženje `sat_t` na 21 bit i inkrementalna adresa — poluge, ostaju dokumentovane.
- Rekalibracija `K_CYC` i pokretanje SystemC modela — po odluci korisnika.
