# Bugs

> **Napomena o Koraku 6:** tri od četiri buga ispod su latentni defekti spakovanog IP-a
> koji su izbili tek pri **prvoj pravoj sintezi** (Korak 7/8). Zajednički koren: IP je bio
> verifikovan **isključivo simulacijom** (`xvhdl -2008` iz komandne linije, gde se
> instancira entitet direktno sa VHDL defaultima), a nikad sintetisan iz kataloga.
> Provera „IP se instancira bez greške" iz Koraka 6 (Task 7 Step 7) je pokrivala samo
> `Generate`, ne sintezu. **Pouka: pakovanje IP-a nije završeno dok se IP ne sintetiše
> iz kataloga.** Sve tri popravke su u `src/vhdl/script/fix_ip_package.tcl`, koji se MORA
> pokretati posle svakog Package IP-a.

## `C_S01_AXI_ADDR_WIDTH` spakovan kao 10 — S01 dekodira 1 KB umesto 128 KB  [POPRAVLJENO 2026-07-25]

`component.xml` je deklarisao `PARAM_VALUE` **i** `MODELPARAM_VALUE` za
`C_S01_AXI_ADDR_WIDTH` kao **10**, dok je VHDL default u `ncc_accel.vhd` **17**.

Instanca iz kataloga dobija **10** → `s01_axi_araddr`/`awaddr` su 10-bitni → S01 dekodira
samo **1 KB**. Sva tri regiona (slika `+0x00000`, šablon `+0x08000`, rezultat `+0x10000`)
preslikala bi se jedan na drugi — **IP nefunkcionalan na ploči.**

Simptom u sintezi:
```
ERROR [Synth 8-11324] array index 16 out of range
                      ncc_accel_slave_full_v1_0_S01_AXI.vhd:473
```

**Zašto nije izbilo u Koraku 6:** beleška Koraka 6 pominje ovu zamku („wizard *Memory
Size* staje na 1024 B → `C_S01_AXI_ADDR_WIDTH` ručno postavljen na 17"), ali je popravka
primenjena **samo u VHDL-u, ne i u paketu**. Simulacija instancira entitet direktno pa
koristi VHDL default 17 i ništa ne prijavljuje. Deklarisani *opsezi memorijske mape* su
bili tačni (4096 / 131072), zato je i `validate_bd_design` prošao — neslaganje je bilo
samo u model-parametru koji ide u RTL.

**Popravka:** `fix_ip_package.tcl` postavlja oba na 17 (`ipx::get_user_parameters` i
`ipx::get_hdl_parameters`).

**Zaštita da se ne ponovi:** dodat statički assert u `S01_AXI.vhd` odmah posle `begin`:

```vhdl
assert C_S_AXI_ADDR_WIDTH = 17
    report "... pokreni src/vhdl/script/fix_ip_package.tcl" severity failure;
```

`mem_addr_o` je fiksno 17-bitni port ka `mem_subsystem`-u, pa je 17 jedina ispravna
vrednost — assert to čini eksplicitnim ugovorom umesto tihe pretpostavke.

**Nije problem:** `C_S01_AXI_*USER_WIDTH` su u paketu 1 a u VHDL-u 0 — Xilinx namerno
forsira minimum 1 (IP-XACT ne može izraziti širinu 0), a ti portovi se ne koriste.

---

## Spakovan IP se NE MOŽE sintetisati — svi fajlovi deklarisani kao VHDL-93  [POPRAVLJENO 2026-07-25]

Prva prava sinteza `ncc_system_wrapper` (Korak 8) je pala na oba `ncc_accel` bloka:

```
ERROR [Synth 8-2757] this construct is only supported in VHDL 1076-2008
                     ...ipshared/7d55/src/ncc_core.vhd:237
ERROR [Synth 8-12189] Failed to read vhdl '...src/ncc_core.vhd'
```

`ncc_core.vhd:237` je `comb_proc : process (all)` — **`process(all)` je VHDL-2008
konstrukt**. A `component.xml` je deklarisao **svih 7 `.vhd` fajlova u obe grupe**
(`xilinx_vhdlsynthesis` i `xilinx_vhdlbehavioralsimulation`) kao
`<spirit:fileType>vhdlSource</spirit:fileType>`, tj. VHDL-93.

**Zašto nije izbilo u Koraku 6 — dve slepe mrlje odjednom:**
1. Ceo simulacioni tok eksplicitno prosleđuje `xvhdl -2008` u komandnoj liniji, pa
   deklarisani tip fajla u IP-u nikad nije bio upotrebljen.
2. `synth_design -rtl` (RTL elaboracija, Korak 7 Task 8) je **prošao** — pa je ta kapija
   bila preslaba. **Elaboracija nije zamena za sintezu.** IP nikad nije bio sintetisan iz
   kataloga pre pakovanja; provera „instancira se bez greške" u Koraku 6 Task 7 Step 7 je
   proveravala samo `Generate`, ne sintezu.

**Popravka:** `src/vhdl/script/fix_ip_package.tcl` postavlja `TYPE = vhdlSource-2008` na
svih 14 unosa (7 fajlova × 2 grupe) preko `ipx::` API-ja i verifikuje upis. Rezultat u
XML-u je `<spirit:userFileType>vhdlSource-2008</spirit:userFileType>` bez
`<spirit:fileType>` — isto kao Xilinx-ovi IP-ovi koji koriste 2008 (referenca:
`data/ip/xilinx/dds_compiler_v6_0/component.xml`).
**Idempotentno — MORA se pokrenuti ponovo posle svakog Package IP-a**, jer wizard vraća
`vhdlSource`. Za Korak 10 to znači da `package_ip.tcl` mora sadržati ovaj korak.

### ⚠️ Zamka u samoj popravci: pravopis `vhdlSource-2008` (SA CRTICOM)

Prvi pokušaj popravke je koristio `vhdlSource2008` (bez crtice). Vivado to **ne odbija** —
prosto prestane da te fajlove prepoznaje kao VHDL, pa OOC sinteza IP-a napravi
`ncc_accel` kao **praznu kutiju bez ijedne greške**:

```
INFO: [Synth 8-637] synthesizing blackbox instance 'U0' of component 'ncc_accel'
|1  |ncc_accel_bbox  |  1|
```

Sinteza `synth_1` tada prođe **100%**, a padne tek implementacija:

```
CRITICAL WARNING [Project 1-486] Could not resolve non-primitive black box cell
                 'ncc_system_ncc0_0_ncc_accel' instantiated as 'ncc_system_i/ncc0/U0'
ERROR [DRC INBB-3] ... has undefined contents and is considered a black box
```

**Tiha greška je bila gora od originalne bučne.** Zato u `create_bd.tcl` toku postoji
kapija posle sinteze koja skenira `ncc_system.runs/ncc_system_ncc*_synth_1/*.vds` i pada
ako nađe `blackbox instance ... ncc_accel`.

**Usput naučeno o IP kešu:** dve instance istog IP-a (`ncc0`/`ncc1`) dele jednu OOC
sintezu preko IP keša (`INFO [IP_Flow 19-4838] Using cached IP synthesis design`,
`cache-ID`). To je normalno, ali znači da se pokvaren rezultat **umnožava tiho** — u logu
druge instance nema ničega osim „koristio keš". Pri dijagnostici gledati log instance
koja je **stvarno** sintetisana (ona sa `Added synthesis output to IP cache`).

**Posledica:** `.zip` arhiva IP-a je zastarela iz dva razloga (popravka S01 + tipovi
fajlova) — regeneriše se u Koraku 10.

---

## S01 (AXI-Full) burst čitanje — off-by-one  [POPRAVLJENO, Korak 7 Task 2]

`ncc_accel_slave_full_v1_0_S01_AXI.vhd` je vraćao **prethodnu** reč na svakom beat-u
posle prvog (7 od 8 pogrešno na `arlen=7`); poslednja reč burst-a se nikad nije pojavila.
Write burst-ovi su radili (8/8).

```
READ  beat 0: očekivano 0x32  dobijeno 0x32   ✓
READ  beat 1: očekivano 0x33  dobijeno 0x32   ✗
READ  beat 2: očekivano 0x34  dobijeno 0x33   ✗
...
READ  beat 7: očekivano 0x39  dobijeno 0x38   ✗
```

**Uzrok:** generisani Xilinx šablon čita interni primer-RAM **kombinaciono**. U Koraku 6
je zamenjen registrovanim `dp_bram` čitanjem (1 takt), a poravnanje je popravljeno samo
za prvi beat (adresa na ciklusu prihvata, `S_AXI_ARADDR`). Za beat-ove ≥1 se koristio
`axi_araddr`, koji se inkrementira u **istom** taktu kad se beat troši → podatak stiže
takt prekasno.

**Zašto nije uhvaćeno u Koraku 6:** `ncc_accel_tb` koristi `awlen=0`/`arlen=0` (single
beat) — burst put nije bio pokriven ni jednim testom. `Xil_In32`/`Xil_Out32` su takođe
single-beat pa ga CPU nikad ne pogodi; svaki DMA ga pogodi.

**Popravka:** look-ahead adresa — u taktu kad se beat *k* troši izdaje se adresa *k+1*
(`araddr_next`, samo za INCR; FIXED zadržava adresu, WRAP nije podržan).
**Test:** `src/vhdl/tb/ncc_accel_burst_tb.vhd` (`arlen`/`awlen` = 7), PASS 8/8 u oba smera.
**Regresija:** `ncc_accel_tb` nepromenjen — `0x80000000 @ idx 956`.

**Pouka:** kad se kombinaciono čitanje u generisanom AXI šablonu zameni registrovanim,
mora se popraviti **ceo** burst, ne samo prvi beat — i testirati sa `len > 0`.

---

## Poznato ograničenje: istovremeni R+W na istom S01  [NIJE POPRAVLJENO, prihvaćeno]

`mem_addr_o` (`S01_AXI.vhd`) daje **prioritet čitanju nad upisom**, a `mem_we_o` nije
zabranjen tokom čitanja. Ako bi upis i čitanje bili istovremeno aktivni na istom S01,
upis bi otišao na **adresu čitanja**.

**Zašto nije popravljeno:** sa jednim CPU-om i jednim CDMA kanalom koji se serijalizuju
u softveru (CPU čeka `XAxiCdma_IsBusy`) situacija je nedostižna, pa bi arbitracija bila
mrtav hardver. **Softverski invarijant za Korak 9:** nikad CDMA transfer prema/od jednog
S01 dok CPU pristupa istom S01.

**Nije testirano** — prijavljeno na osnovu čitanja koda, ne simulacije.

---

## S_AXI_HP0 na 64 bita → 6 nepotrebnih konvertora širine  [POPRAVLJENO 2026-07-26]

PS `S_AXI_HP0` je ostao na **fabričkom defaultu od 64 bita** (HP portovi su nativno
široki — pravljeni su za DDR saobraćaj). Sve ostalo u dizajnu je 32-bitno: CDMA
(`C_M_AXI_DATA_WIDTH = 32`), `ncc.S01`, PS `M_AXI_GP0`.

`axi_interconnect` postavlja širinu krosbara prema **najširem** portu, pa je zbog HP0
gradio 64-bitni krosbar i lepio konvertor (`auto_ds`) na **svaki** 32-bitni port — za
konverziju koju nijedan blok ne traži.

**Popravka:** `CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {32}` u `create_bd.tcl`.

| | HP0 = 64 | HP0 = 32 |
|---|---|---|
| Slice LUT | 9.681 (55,0%) | **6.261 (35,6%)** |
| Slice Registers | 8.696 (24,7%) | **5.024 (14,3%)** |
| `auto_ds`/`dwidth` ćelija | 6 | **0** |

**Propusnost se ne gubi:** HP0 pada sa 800 na 400 MB/s, ali CDMA je 32-bitan pa 64
nikad nije mogao ni da iskoristi. Konvertori su bili čist gubitak.

**Greška u rasuđivanju (zapisana da se ne ponovi):** tvrdio sam da kritična putanja
ide kroz konvertor i da će uklanjanje vratiti 100 MHz. Konvertori su nestali, a WNS
se pomerio sa −0,233 na **−0,232 ns** — dakle nula. Vezujuća putanja je sve vreme bila
adresna u `ncc_core`. Zaključivao sam iz **jednog** merenja (na 11 ns) gde se konvertor
pojavio kao najgori jer je adresna putanja tamo imala rezerve. **Pouka: pre pripisivanja
uzroka uporediti putanje na ISTOM taktu.** Izmena je ipak zadržana — zbog površine.

---

## Rezerva se NE prevodi aritmetički između ograničenja takta  [PRAVILO, 2026-07-26]

Merenje golog jezgra je prvo pušteno samo na 11 ns, a Fmax i „rezerva prema 100 MHz"
izvedeni **aritmetički** iz tog slack-a → dobijeno 94,22 MHz i −0,613 ns. **Oboje
netačno.** Alat optimizuje *do* zadatog ograničenja i staje čim ga ispuni, pa je kritična
putanja na labavijem ograničenju **duža**:

| Ograničenje | WNS | putanja | logika / rutiranje | nivoi |
|---|---|---|---|---|
| 11,0 ns | +0,387 ns | 10,638 ns | 5,72 / 4,92 (46% ruta) | 16, CARRY4=9 |
| **10,0 ns** | **+0,146 ns** | 9,832 ns | 7,90 / 1,93 (20% ruta) | 12, **DSP48E1=2** |

Na strožem ograničenju alat je kvadriranje mapirao u DSP48E1 i rutiranje spustio sa 4,92
na 1,93 ns — **druga implementacija istog RTL-a**, ne isto kolo na drugom taktu.

**Pravilo: Fmax se meri na ograničenju koje se tvrdi.** Ako se tvrdi 100 MHz, meri se na
10 ns. `run_synth_core.tcl` je zato parametrizovan (`-tclargs 11.0`), a `ncc_core_ooc.xdc`
čita `NCC_PERIOD`.

Ovo je **četvrti** slučaj istog obrasca u ovom projektu — uzrok ili brojka izvedeni iz
jednog merenja, bez kontrolnog. Prethodna tri su zapisana niže u ovom fajlu.

---

## `ncc_core` ne zatvara 100 MHz na `xc7z010clg400-1`  [POVUČENO — jezgro zatvara]

> **⚠️ ISPRAVKA 2026-07-26.** Naslov i ceo odeljak ispod opisuju RTL **pre** dva preseka
> iz Koraka 8b. Sa aktuelnim RTL-om **golo jezgro zatvara 100 MHz**: post-route OOC,
> WNS **+0,146 ns**, Fmax **~101,5 MHz**.
>
> Ograničenje je **integracija, ne jezgro.** `ncc_system_wrapper` na 10 ns daje
> −0,232 ns; vezujuća putanja je adresna unutar jezgra, ali kritična **samo pod pritiskom
> razmeštaja i zagušenja** u punom sistemu. Samostalno ta putanja nije ni blizu kritične.
>
> Posledica za dokumentaciju: ne pisati „jezgro ne zatvara 100 MHz". Tačno je da
> **sistem** ne zatvara, i to je poštenija formulacija — pokazuje da je RTL dobar, a da je
> cena integracija.
>
> Zapis ispod se zadržava kao istorija merenja na starom RTL-u.

**Post-route (merodavno), goli `ncc_core`, OOC, `clg400-1`:**

| Faza | WNS | krši |
|---|---|---|
| post-synth | −0,571 ns | 16/1444 |
| post-place | −1,199 ns | 53/1444 |
| **post-route** | **−0,754 ns** | **51/1444** |

**Fmax ≈ 93 MHz**, ne 100 MHz. Kritična putanja post-route:

```
sum_num_reg[19] → div_ncc/work_reg[82]
10,701 ns  (logika 6,132 / rutiranje 4,569)   17 nivoa logike (CARRY4=9)
```

Kvadriranje brojioca (`num_sq = sum_num²`) koje ulazi u 83-bitni delilac — tačno ona
putanja koju `IDEJE.md` označava kao presecivu.

### Dva pogrešna zaključka usput (zapisana da se ne ponove)

**(a) „Merenje je degenerisano zbog IOB prekoračenja" — NETAČNO.** Goli `ncc_core` traži
118 IOB-ova a paketi imaju 54 (`clg225`) / 100 (`clg400`), pa je prva hipoteza bila da
procjena rutiranja nije pouzdana. Oboreno `synth_design -mode out_of_context` (0 IOB):

| Part | WNS (OOC, 0 IOB) | putanja | logika / rutiranje |
|---|---|---|---|
| `xc7z010clg225-2` | **+1,277 ns** | 8,706 ns | 6,896 / 1,810 |
| `xc7z010clg400-1` | **−0,571 ns** | 10,549 ns | 5,419 / **5,130** |

Razlika ostaje bez IOB-ova. Uz to, procjena rutiranja je **identična** u IOB i OOC
režimu za isti part (1,810 na `clg225`, 5,130 na `clg400`) → zavisi od uređaja, ne od
razmeštaja. Trebalo je odmah primetiti i da je prekoračenje *veće* na partu koji prolazi
(218% vs 118%), što samo po sebi obara hipotezu.

**(b) „Odgovor daje Korak 8" — netačno kao izgovor za odlaganje.** Integracija može samo
da **pogorša** timing (više zagušenja); ne postoji scenario u kome integrisani dizajn
zatvara a golo jezgro ne zatvara. Odluka je bila potrebna odmah.

### Posledica za Korak 5 (nezavisna od parta)

Brojka **+1,179 ns iz Koraka 5 je bila samo post-sintezna.** Pravilnik za 5b i 8b traži
„nakon sinteze **i implementacije**". Post-route na `clg225-2` nikad nije pokrenut, pa ta
brojka nije bila merodavna ni na starom partu. Kad se timing reši, Korak 5 treba re-meriti
post-route i ažurirati PDF.

### Poluga

Registar između kvadriranja `sum_num` i ulaza u `div_ncc` (`IDEJE.md`): +1 takt po
prozoru od ~485 = **+0,2% latencije**. Zahteva izmenu `ncc_core.vhd` → oba TB-a iz
Koraka 4 (`ncc_core_tb`, `ncc_core_real_tb`) plus `ncc_accel_tb` moraju ponovo proći.

Alternativa bez izmene RTL-a: **FCLK_CLK0 = 90 MHz** (jedna linija u `create_bd.tcl`).
Košta 10% throughput-a i sve ms brojke se preračunavaju, ali je formalno u rubrici
(10% odstupanja, granica 20%).

### Rešenje (2026-07-26)

Dva preseka u `ncc_core` (FSM 21 → 23 stanja, latencija **+0,41%**, izlaz bit-identičan):

1. **MAC pipeline** — `df_reg`/`dt_reg` + `mac_v_reg`, tako da BRAM → oduzimanje ide u
   jedan takt, a množenje → 27-bitni akumulator u sledeći. Vratilo **2,43 ns**.
2. **Registar pred delilac** — `num_sq_reg`/`den_prod_reg` (poluga iz `IDEJE.md`).
   Vratilo 0,155 ns; putanja se odmah premestila na adresnu.

Plus, van jezgra: SmartConnect → AXI Interconnect, HP0 na 32 bita, `phys_opt_design`
(sam donosi **0,481 ns** — više nego drugi presek).

**Konačno: WNS +0,170 ns na 11,0 ns → zatvara na 90,909 MHz.** Fmax ~97,7 MHz.

**Preostala poluga za punih 100 MHz (NIJE primenjena):** inkrementalno računanje adrese
u unutrašnjoj petlji — umesto `(v+y)·img_w + (u+x)` u svakom taktu, adresa u registru
uz korak `+1` unutar reda i `+(img_w − tmp_w + 1)` na prelasku reda; adresa šablona
postaje prost brojač. Izbacuje množač iz petlje (11 nivoa logike → 1–2), ne menja
latenciju. Rizik je što greška u koraku daje **pogrešan rezultat**, ne pad — ali
`ncc_core_real_tb` to hvata jer traži tačan pik na (32,14).
