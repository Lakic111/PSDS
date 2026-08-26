---
name: ncc-vivado-workflow
description: Use when working on the NCC FPGA accelerator in this repo — packaging or repackaging the ncc_accel IP, running Vivado batch scripts (create_bd.tcl, run_impl.tcl, run_synth_core.tcl, package_ip.tcl), claiming an Fmax or WNS number, editing ncc_core.vhd or the AXI wrappers, writing bare-metal software that drives the accelerator, or naming signals and registers in the documentation.
---

# NCC akcelerator — Vivado tok

Zamke koje su u ovom projektu **već izbile** i koštale vremena. Svaka je izmerena ili
reprodukovana; nijedna nije pretpostavka. Sve što ovde piše ima izvor u repou.

## Zajednički koren svih tihih grešaka

**Simulacija ne dokazuje sintezu, a elaboracija nije sinteza.** Tri od četiri buga
spakovanog IP-a izbila su tek pri prvoj pravoj sintezi, jer je IP bio verifikovan
isključivo simulacijom (`xvhdl -2008` iz komandne linije instancira entitet direktno i
koristi VHDL defaulte, pa deklarisani tip fajla u paketu nikad nije upotrebljen).
`synth_design -rtl` je takođe **prošao** — ta kapija je preslaba.

**Pakovanje IP-a nije završeno dok se IP ne sintetiše iz kataloga.**

## Pakovanje IP-a

**Posle SVAKOG Package IP wizarda pokrenuti `src/vhdl/script/fix_ip_package.tcl`.**
Wizard vraća `vhdlSource` i `C_S01_AXI_ADDR_WIDTH = 10`. Skripta je idempotentna i
postavlja tip na svih 14 unosa (7 fajlova × 2 grupe) i širinu na 17.

Za Korak 10 to znači: `package_ip.tcl` **mora** na kraju pozvati `fix_ip_package.tcl`.

| Zamka | Posledica ako se promaši |
|---|---|
| `vhdlSource2008` bez crtice | Vivado **ne odbija**. Prestane da prepoznaje fajlove kao VHDL → IP se sintetiše kao **prazna kutija bez ijedne greške**. `synth_1` prođe 100%, pada tek implementacija (`DRC INBB-3`). Tačno je `vhdlSource-2008`. |
| `C_S01_AXI_ADDR_WIDTH = 10` | S01 dekodira 1 KB umesto 128 KB; sva tri regiona (slika `+0x00000`, šablon `+0x08000`, rezultat `+0x10000`) se preklapaju → IP nefunkcionalan na ploči. |

Obe imaju kapiju, koristiti ih umesto oka:

- **Statički assert** u `ncc_accel_slave_full_v1_0_S01_AXI.vhd:248` — `C_S_AXI_ADDR_WIDTH = 17`.
- **KAPIJA 1** u `run_impl.tcl:29` skenira `ncc_system.runs/ncc_system_ncc*_synth_1/*.vds`
  i pada na `blackbox instance ... ncc_accel`. **KAPIJA 2** (linija 68) pada ako WNS < 0.

**IP keš umnožava pokvaren rezultat tiho.** `ncc0` i `ncc1` dele jednu OOC sintezu
(`INFO [IP_Flow 19-4838] Using cached IP synthesis design`). U logu druge instance nema
ničega osim „koristio keš" — pri dijagnostici gledati log instance sa
`Added synthesis output to IP cache`.

## Merenje tajminga

**Fmax se meri na ograničenju koje se tvrdi.** Rezerva se **ne prevodi aritmetički**
između ograničenja — alat optimizuje *do* zadatog cilja i staje čim ga ispuni, pa je
kritična putanja na labavijem ograničenju **duža**:

| Ograničenje | WNS | putanja | logika / rutiranje | nivoi |
|---|---|---|---|---|
| 11,0 ns | +0,387 ns | 10,638 ns | 5,72 / 4,92 | 16, CARRY4=9 |
| 10,0 ns | +0,146 ns | 9,832 ns | 7,90 / 1,93 | 12, **DSP48E1=2** |

Na strožem ograničenju alat je kvadriranje mapirao u DSP48E1 — **druga implementacija
istog RTL-a**, ne isto kolo na drugom taktu. Tvrdi se 100 MHz → meri se na 10 ns.
`run_synth_core.tcl` je zato parametrizovan: `-tclargs 10.0`.

**Pre pripisivanja uzroka uporediti putanje na ISTOM taktu.** Uzrok izveden iz jednog
merenja bez kontrolnog bio je pogrešan **četiri puta** u ovom projektu. Poslednji put:
tvrdnja da kritična putanja ide kroz `auto_ds` konvertor — konvertori uklonjeni, WNS se
pomerio sa −0,233 na −0,232 ns, dakle nula.

**Ne pisati „jezgro ne zatvara 100 MHz".** Golo jezgro **zatvara** (OOC post-route, WNS
+0,146 ns, Fmax ~101,5 MHz). Sistem ne zatvara (−0,232 ns). Ograničenje je integracija.

## Softver koji vozi akcelerator

Dva invarijanta koja **hardver ne proverava**:

1. **Skorovi se porede kao `u32`, ne `int32`.** `0x80000000` je NCC²=1,0 — savršeno
   poklapanje — ali kao `int32` je negativan, pa bi traženje maksimuma od `-1` odbacilo
   baš najbolji rezultat.
2. **Nikad CDMA i CPU nad istim S01 istovremeno.** `mem_addr_o` daje prioritet čitanju, a
   `mem_we_o` nije zabranjen tokom čitanja → upis bi otišao na adresu čitanja. Arbitracija
   nije implementirana svesno; održava se time što CPU čeka `XAxiCdma_IsBusy`.

Adresna mapa, registri i tok podataka po polju su **već dokumentovani** u poglavljima 8 i
9 PDF-a (`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`). Ne izvoditi ih
iznova — pročitati ih.

DDR je **512 MB** (originalni Zybo) → baferi moraju stati ispod `0x1FFFFFFF`.

## Ploča

`board_part` je **`digilentinc.com:zybo:part0:B.4`** — originalni Zybo, potvrđeno VGA
konektorom (Z7-10 ima dva HDMI-ja i nijedan VGA). Segment verzije je **ime direktorijuma**
board fajla, ne `schema_version` iz `board.xml` (koji je `2.0` i nije verzija ploče).

⚠️ Sve brojke Koraka 7 i 8 merene su sa **Z7-10** presetom. Part `xc7z010clg400-1` je isti,
PS preset nije — tajming i FCLK treba potvrditi. `create_bd.tcl` sam štampa `PS_CLK`,
`DDR partno` i `FCLK0`; pročitati taj ispis umesto pretpostavljanja.

## Pisanje dokumentacije o ovom dizajnu

- **Svako ime signala proveriti u RTL-u.** Skraćenice su tri puta bile izmišljene
  (`den_f`/`den_t`, `diff_f`/`diff_t` ne postoje). Stvarni registri preseka:
  `df_reg`, `dt_reg`, `mac_v_reg`, `num_sq_reg`, `den_prod_reg` u `ncc_core.vhd`.
- **Pravilo celog pasusa.** Kad izmena dopunjuje zatečeni tekst, pročitati **ceo** pasus —
  stara rečenica preživi kao „context" linija u diff-u i niko je ne vidi kao svoju. Tako su
  nađene tri protivrečnosti. Važi i za `<figcaption>` i `<caption>`.
- **Provere se puštaju POSLE poslednje izmene.** Dvostruka crtica u XML komentaru ušla je
  posle provere; browser to ne prikazuje kao grešku, pa je render prošao a sintaksa nije.
- **SVG traži pravi render.** Sintaksna provera ne hvata strelicu koja pokazuje u prazno.
  Goli `xml.dom.minidom` daje lažnu grešku — prvo razrešiti HTML entitete.

## Crvene zastavice — stani

- „Simulacija prolazi, IP je gotov" → nije, dok se ne sintetiše iz kataloga.
- „Sinteza je prošla 100%" → proveri da nije blackbox (KAPIJA 1).
- „Fmax je otprilike X" izvedeno iz slack-a na drugom ograničenju → izmeri na tom ograničenju.
- „Ova putanja je kriva" iz jednog merenja → uporedi na istom taktu, sa kontrolnim.
- Ime signala napisano iz glave → `grep` ga u `ncc_core.vhd`.

## Izvori (merodavni, ovaj fajl je izvod)

| Šta | Gde |
|---|---|
| Puna hronologija bugova | `PSDS Vault/Projects/NCC_Akcelerator/BUGS.md` |
| Stanje projekta, brojke | `PSDS Vault/Projects/NCC_Akcelerator/CLAUDE.md` |
| Šta je sledeće | `PSDS Vault/Projects/NCC_Akcelerator/(C) Sljedeća sesija.md` |
| Adresna mapa, registri, integracija | PDF poglavlja 8-10 |
| Neprimenjene poluge | `PSDS Vault/Projects/NCC_Akcelerator/IDEJE.md` |
