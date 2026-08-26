# Sljedeća sesija

## PRVO za sljedeću sesiju — Korak 10 (posljednji)

> **Stanje 2026-08-27. KORACI 1-9 ZAVRŠENI — 90 bodova.** Preostaje **Korak 10 (10)**.

### Korak 9 je gotov i potvrđen na hardveru

FEN sa ploče je znak po znak identičan zvaničnom:
`rnbqkbnr/pp5p/4ppp1/2pp4/5P2/1P1BPN2/P1PPQ1PP/RNB1K2R`, **32/32 polja**, **1.782 ms**.

| Faza | Šta dokazuje | Rezultat |
|---|---|---|
| 1 | AXI-Lite radi u oba smjera | `IMG_W` upisano 90, pročitano 90 |
| 2 | S01 memorije | 8.100 riječi, **0 neslaganja** |
| 3 | Jezgro računa | **`0x80000000` @ idx 956** — bit-identično Koraku 4 |
| 4 | Prenosi | isto kao faza 3 |
| 5 | Pun tok | FEN tačan, 1.782 ms |

Izmjerena raspodjela: računanje **1.555 ms (87,3 %)**, upis u S01 120 ms, čitanje
rezultata 67 ms, obrada na procesoru 40 ms. Naspram ESL reference (3,667 s)
**2,06× brže** uz identičan rezultat.

### ⚠️ Prenosi idu PROCESOROM, ne DMA-om

`#define NCC_USE_CDMA 0` u `src/vitis/app/ncc_hw.c`. Razlog: **burstovi duži od dva
beata zaglavljuju `axi_interconnect_0`** (STRATEGY=1, dijeljena magistrala). Izmjereno
preko JTAG-a, bez našeg koda: 1 i 2 beata rade, 3 i 4 zaglavljuju — podjednako za
DDR→DDR i S01→S01. CDMA, HP0, S01 i topologija block designa su time isključeni.
Puni zapis u `BUGS.md`.

Košta najviše ~9 % vremena. **DMA ostaje u block designu** (Korak 7 nepromijenjen),
aplikacija ga ne koristi. Povratak je **jedna linija** kad interkonekt proradi.

**Nedovršeno (dogovoreno kao sljedeće poboljšanje):** izmjestiti tri AXI-Lite slave-a
(`ncc0.S00`, `ncc1.S00`, `axi_cdma_0.S_AXI_LITE`) na zaseban interkonekt i vidjeti hoće
li burstovi proraditi. Hipoteza je da dijeljeni podatkovni put trpi zbog njih, ali
**nije potvrđena**.

### Dva bug-a u IP-u nađena i popravljena usput

Oba AXI slave-a su visila kad `W` stigne prije `AW` (AXI to izričito dozvoljava):

- **S00** (AXI-Lite) — commit `720d162`
- **S01** (AXI-Full, burstovi) — commit `4bac595`, uz dodatnu zamku: adresni proces je
  pre-inkrementirao na goli `WVALID`, pa je morao i on

Oba su imala **polovičnu popravku iz Koraka 8** (`wr_beat`) koja je riješila samo
posljedicu po podatke, ne i protokolarni zastoj. Preživjeli su Korake 6, 7 i 8.

Novi testbenčevi `ncc_accel_wfirst_tb` i `ncc_accel_s01_burst_wfirst_tb` pokrivaju sve
redoslijede i **dokazano padaju na starom RTL-u**. Popravke su smanjile površinu
(6.274 → 6.225 LUT) i poboljšale tajming (+0,181 → **+0,268 ns**).

Usput: **`ncc_accel_burst_tb` iz Koraka 7 je kodirao bug** — nikad nije čitao
`s01_wready`, pa je prolazio samo zato što je `wready` bio trajno visok. Popravljen
(`cb8b67a`) da poštuje handshake i da svaka petlja ima timeout.

### Otvoreno — završiti prvo

**Poglavlje 10.3 još nosi „−0,054 ns na 10 ns", mjereno PRIJE AXI popravki.** Kontrolno
mjerenje sa popravljenim RTL-om je pokrenuto na kraju sesije (`run100.tcl`, odvojen
projekat `C:/ncc100`, ispis u scratchpad `run100_out.txt`). Pošto su popravke na 11 ns
donijele +0,087 ns, **moguće je da sistem sada zatvara 100 MHz** — što bi promijenilo
zaključak dokumenta.

**Gdje naći rezultat.** Ispis je u scratchpadu sesije
(`run100_out.txt`), ali taj direktorijum se može očistiti. Trajna kopija je **sam Vivado
projekat na `C:
cc100`** — otvori ga i pročitaj tajming bez ponovne sinteze:

```tcl
open_project C:/ncc100/ncc_system.xpr
open_run impl_1
report_timing_summary -delay_type max -max_paths 1
```

Ako ni toga nema, mjerenje se ponavlja iz repoa (~40 min), jer je `NCC_FCLK` sada
parametar u `create_bd.tcl`:

```tcl
set NCC_PROJ_DIR       C:/ncc100
set NCC_FCLK           100
set NCC_SKIP_BITSTREAM 1
source src/vhdl/script/run_impl.tcl
```

**PDF nije regenerisan** poslije te izmjene i čeka taj rezultat. Sve ostalo u HTML-u je
ažurno (Tabele 19-21, 25, 26, zaključak).

### Korak 10 — šta treba

`package_ip.tcl` i ulančavanje cijelog toka do XSA. Skripte uglavnom postoje:
`create_bd.tcl` (sad sa parametrima `NCC_FCLK` i `NCC_PROJ_DIR`), `run_impl.tcl`
(sinteza → implementacija → **bitstream → XSA**, sa četiri kapije), `run_synth_core.tcl`,
`fix_ip_package.tcl`, `build_app.tcl`, `run_app.tcl`, `uart_log.ps1`.

⚠️ `package_ip.tcl` **mora** na kraju pozvati `fix_ip_package.tcl` — wizard vraća
`vhdlSource` i `ADDR_WIDTH=10`, a sa pogrešnim tipom fajla IP se sintetiše kao **prazna
kutija bez ijedne greške**. `.zip` arhiva IP-a je zastarjela i regeneriše se tu.

### Korisno za sljedeći put

- **UART bez ijednog dodatnog programa:** ploča je **COM6** (FTDI: kanal A `...A6A`
  JTAG, kanal B `...A6B` UART). `src/vitis/scripts/uart_log.ps1` snima ispis preko
  .NET `SerialPort`. Baud **115200** izveden iz `ps7_init.tcl`, nije pretpostavljen.
- **Oporavak zaglavljene ploče:** `rst -srst` na `xc7z010`, pa `fpga -file`, pa `stop`.
  Poslije više zaglavljivanja DAP ode u trajnu grešku i treba **fizički restart**.
- **Vitis radni prostor** ume da se pokvari; `build_app.tcl` sad radi `app remove`
  prije `app create` i ispisuje gdje je tražio `.elf`.
- **Tcl za XSCT mora biti bez BOM-a** — PowerShell `Set-Content -Encoding utf8` ga
  upisuje i XSCT pukne sa `invalid command name`.
- `xsct.bat` je u `Vitisin`, ne u `Vivadoin`.

---

## Ranije zabilježeno

## PRVO za sledeću sesiju — Korak 9 (bitstream + Vitis)

> **Stanje 2026-07-26 (kraj sesije). KORACI 1-8 ZAVRŠENI — 70 bodova.**
> Preostaju **Korak 9 (20 bodova)** i **Korak 10 (10 bodova)**.
>
> ### ✅ RAZREŠENO 2026-08-26: ploča je ORIGINALNI Zybo
>
> To je **jedina blokirajuća stavka** za Korak 9. `board_part` je postavljen na
> Korisnik je nabavio ploču i pogledao je: **jedan VGA + jedan HDMI** → originalni Zybo
> (Z7-10 ima dva HDMI-ja i nijedan VGA). `create_bd.tcl` je prebačen na
> **`digilentinc.com:zybo:part0:2.0`** — tačno kako je tabela ispod i tvrdila.
>
> ⚠️ **Zabeleženo da se ne ponovi:** prvo sam ovo „ispravio" na `part0:B.4`, rezonujući
> da je `2.0` zapravo `schema_version` iz `board.xml` a da segment verzije dolazi iz
> imena direktorijuma (`zybo/B.3`, `zybo/B.4`). **Netačno** — Vivado je odbio:
> `ERROR [Board 49-71] board_part definition was not found`. Segment verzije je
> `<file_version>` iz `board.xml`: B.3 → `1.0`, B.4 → `2.0`. Dakle `2.0` **jeste**
> revizija B.4, novija od dve. Merodavan izvor je `get_board_parts`, ne struktura
> direktorijuma:
>
> ```
> digilentinc.com:zybo:part0:1.0
> digilentinc.com:zybo:part0:2.0
> digilentinc.com:zybo-z7-10:part0:1.2
> digilentinc.com:zybo-z7-20:part0:1.2
> ```
>
> Preseti B.3 i B.4 imaju identične PS_CLK (50 MHz), DDR partno (MT41K128M16 JT-125),
> UART1 i sva četiri `DDR_BOARD_DELAY`/`DQS_TO_CLK_DELAY`; razlika je samo u broju
> deklarisanih board interfejsa, što nas ne dotiče (koristimo samo FIXED_IO + DDR).
>
> ⚠️ **Sve brojke Koraka 7 i 8 su merene sa Z7-10 presetom.** Part `xc7z010clg400-1` je
> isti, ali PS preset nije — tajming i FCLK se moraju **ponovo potvrditi** pri prvom
> pokretanju (`create_bd.tcl` sam štampa PS_CLK, DDR partno i FCLK0).
>
> ### ✅ Izmereno sa Zybo presetom 2026-08-26 — TAJMING ZATVARA
>
> `run_impl.tcl` pušten sa `part0:2.0`; obe kapije prošle (nema blackbox-a, WNS ≥ 0).
> Vivado potvrdio preset: `PS_CLK=50.000000 DDR=MT41K128M16 JT-125 FCLK0=95`,
> DDR segment `0x20000000` (512 MB).
>
> | | Z7-10 preset (staro) | **Zybo preset (novo)** |
> |---|---|---|
> | Takt | 90,909 MHz | **90,909 MHz** (period 11,0 ns) |
> | WNS | +0,170 ns | **+0,181 ns** |
> | LUT | 6.261 (35,6%) | 6.274 (35,65%) |
> | FF | 5.024 (14,3%) | 5.024 (14,27%) |
> | BRAM | 39 (65,0%) | 39 (65,0%) |
> | DSP | 18 (22,5%) | 18 (22,5%) |
>
> **Promena preseta praktično nije pomerila ništa** — WNS +0,011 ns, LUT +13. Očekivano:
> PS preset menja MIO, DDR kontroler i PLL, a kritična putanja je u PL-u. Ostala je
> adresna, kako je i zapisano:
>
> ```
> ncc0/core_inst/v_reg_reg[1] → ncc0/ms_inst/img_mem/ram_reg_1/ADDRBWRADDR[14]
> 9,896 ns   logika 4,384 (44%) / rutiranje 5,512 (56%)   10 nivoa, CARRY4=6
> ```
>
> **Posledica: brojke Koraka 7 i 8 u PDF-u OSTAJU VAŽEĆE — ne treba prepravljati.**
> Jedina stvarna promena za Korak 9: DDR je **512 MB**, baferi moraju stati ispod
> `0x1FFFFFFF`.
>
> Razlike između varijanti, za istoriju:
>
> | | Zybo (originalni) | Zybo Z7-10 |
> |---|---|---|
> | Prepoznavanje na oko | **VGA** + 1× HDMI, 6 Pmod | **2× HDMI**, MIPI CSI, 5 Pmod |
> | `board_part` | `digilentinc.com:zybo:part0:2.0` | `digilentinc.com:zybo-z7-10:part0:1.2` |
> | PS_CLK kristal | 50 MHz | 33,333 MHz |
> | DDR3 | 512 MB | 1 GB |
>
> Pogrešan preset → ploča ne bootuje i UART je na pogrešnom baud rate-u. Promena je
> **jedna linija** u `src/vhdl/script/create_bd.tcl`.
>
> ### Korak 9 — šta treba
>
> 1. **Bitstream.** `run_impl.tcl` staje na `phys_opt_design (Post-Route)` i **ne zove
>    `write_bitstream`** — dodati taj korak.
> 2. **Export XSA** (sa bitstream-om) za Vitis.
> 3. **Bare-metal aplikacija:** port logike iz `src/tb.cpp` (`tb_vp::test()`) — učitavanje
>    slike, petlja 8×8, provera praznog polja, coarse/fine NCC, generisanje FEN-a — ali sa
>    `Xil_Out32`/`Xil_In32` umesto TLM `b_transport`, i pravim CDMA drajverom
>    (`XAxiCdma_*`) umesto modela iz `dma.cpp`.
> 4. **Interfejs je već dokumentovan** — adresna mapa, registri, tok podataka po polju i
>    dva obavezna pravila su u poglavljima 8 i 9 PDF-a. Ne izvoditi ih iznova.
>
> **Dva pravila koja softver MORA poštovati** (hardver ih ne proverava):
> - skorovi se porede kao **`u32`**, ne `int32` — `0x80000000` (NCC²=1,0) je kao `int32`
>   negativan, pa bi traženje maksimuma od `-1` odbacilo savršeno poklapanje;
> - **nikad CDMA i CPU nad istim `S01` istovremeno** — prioritet ima čitanje, a upis nije
>   zabranjen, pa bi upis otišao na adresu čitanja. Održava se time što CPU čeka
>   `XAxiCdma_IsBusy`.
>
> ### Korak 10 — šta već postoji
>
> Skripte su uglavnom napisane: `create_bd.tcl` (block design), `run_impl.tcl` (sinteza +
> implementacija sa kapijama), `run_synth_core.tcl` (OOC jezgro, period je parametar),
> `fix_ip_package.tcl`. Ostaje **`package_ip.tcl`** i ulančavanje u jedan tok do XSA.
>
> ⚠️ `package_ip.tcl` **mora** na kraju pozvati `fix_ip_package.tcl` — wizard vraća
> `vhdlSource` i `ADDR_WIDTH=10`, a sa pogrešnim tipom fajla IP se sintetiše kao **prazna
> kutija bez ijedne greške**. `.zip` arhiva IP-a je zastarela i regeneriše se tu.
>
> ### Šta je Korak 8 dao (2026-07-26)
>
> Dokumentacija je proširena sa Koraka 2-5 na **2-8**:
> **`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf`** — 34 strane (bilo 22),
> 24 tabele, 4 SVG dijagrama. Stari `Korak2-5.pdf` je uklonjen (ostaje u git istoriji).
>
> Deset taskova, svi komitovani na `korak6-axi-ip`:
>
> | Commit | Šta |
> |---|---|
> | `8a999fb` `052960b` `3cc6ca4` | §5.1, Tabela 5, §5.6 na 23 stanja |
> | `e23da3d` | ASMD dijagram (Slika 1) prerisan na 23 stanja |
> | `b564af4` `8dc28cd` | §5.5 i Slika 2 na tri stepena protočnosti |
> | `142270c` | §6 registri (+5) i datapath |
> | `b97e3a9` | §7 na post-route brojke |
> | `55974a7` | novo poglavlje 8 — IP jezgro |
> | `e5f8f29` `9be9ba3` | novo poglavlje 9 — integracija + Slika 4 |
> | `317a7a6` | novo poglavlje 10 — analiza sistema |
> | `ebf3346` | zaključak, Sadržaj, preimenovanje, PDF |
>
> **Re-merene brojke Koraka 5** (bile su post-sintezne, na starom partu i starom RTL-u):
> goli `ncc_core` post-route na `clg400-1` daje 1.472 LUT / 664 FF, WNS **+0,146 ns na
> 10 ns** → **Fmax ~101,5 MHz, jezgro ZATVARA 100 MHz.** Latencija **2.461.201 taktova**.
> Reprodukcija: `run_synth_core.tcl`, period je parametar (`-tclargs 11.0`).
>
> **Ograničenje je integracija, ne jezgro** — sistem na 10 ns daje −0,232 ns; vezujuća
> putanja je adresna unutar jezgra, ali kritična samo pod pritiskom razmeštaja.
>
> ### Dve odluke koje čekaju korisnika
>
> 1. **Slika 3 (blok dijagram datapath-a) nije prerisana.** Još crta
>    oduzimač→množač→delilac bez register-kutija. Umesto prerade dodat je pošten pasus da
>    slika „radi preglednosti" ne iscrtava pet protočnih registara. ASMD (Slika 1) **je**
>    prerisan — ovo je svesno odstupanje. Prerisati ili zadržati napomenu?
> 2. **„+110 flip-flopova" u §6.2 nije čisto uporediv broj.** Izveden kao 664 (post-route,
>    `clg400-1`) − 554 (post-**synth**, `clg225-2`) — dva parta i dve faze toka. Suma
>    širina novih registara je 123 bita, ne 110. Izmeriti FF na istom partu/fazi, ili
>    preformulisati bez konkretnog broja.
>
> ### Git — REŠENO 2026-08-26
>
> Onih 25 nekomitovanih fajlova je komitovano u dva commita i pushovano na GitHub
> (`https://github.com/Lakic111/PSDS.git`):
>
> - `d0854e5` Korak 7: block design, popravke AXI IP-a i presek u `ncc_core`
> - `d39d1c1` Beleške: dizajn i planovi za Korake 7 i 8, BUGS, stanje projekta
>
> `main` je fast-forwardovan na `korak6-axi-ip`; obe grane su na `d39d1c1` i obe su
> na remote-u. Radno stablo je čisto. **Tačka povratka sada postoji.**
>
> ### Pouke iz izvršavanja — plan je ispravljen na 11 mesta
>
> Sve greške su bile u planu ili u mojim brojkama, nijedna u izvršenju subagenata.
> Najvrednije, i primenljive na Korake 9-10:
>
> - **Pravilo celog pasusa.** Kad izmena dopunjuje zatečeni tekst, pročitati **ceo** pasus
>   — stara rečenica preživi kao „context" linija u diff-u i niko je ne vidi kao svoju.
>   Tako su nađene tri protivrečnosti: §5.5 (dvostepena protočnost), §7.3 (predlagao
>   registar koji je već dodat), §4.4 (deljena memorija koja ne postoji). Važi i za
>   `<figcaption>` i `<caption>`.
> - **Provere se puštaju POSLE poslednje izmene.** Dvostruka crtica u XML komentaru je
>   ušla posle provere; browser to ne prikazuje kao grešku, pa je render prošao a
>   sintaksa nije.
> - **Rezerva se ne prevodi između ograničenja takta.** Videti `BUGS.md`.
> - **Skraćenice imena signala su tri puta bile izmišljene** (`den_f`/`den_t`,
>   `diff_f`/`diff_t`) — svako ime u `<span class="mono">` proveriti u RTL-u.
> - **Sintaksna provera SVG-a ne hvata strelicu koja pokazuje u prazno** — obavezan
>   render. Tako je nađeno da strelica `M05` prolazi kroz kutiju `proc_sys_reset`.
> - **`svgcheck.py`** (provera SVG-a koja prvo razrešava HTML entitete) je opisana u
>   planu, Task 2 Korak 6 — goli `xml.dom.minidom` daje lažnu grešku.

## Ranije zabeleženo za sledeću sesiju

> **KORACI 1-7 ZAVRŠENI; KORAK 8a i 8b IZMERENI** (stanje 2026-07-26).
> Ne vraćati se na njih bez konkretnog razloga.
>
> ## Stanje sistema (post-route + phys_opt, `xc7z010clg400-1`)
>
> | | vrednost |
> |---|---|
> | Takt | **90,909 MHz** (traženo 95; PS PLL daje 1000/11) |
> | WNS | **+0,170 ns** na 11,0 ns — **ZATVARA** |
> | Fmax | ~97,7 MHz (100 MHz ne zatvara: −0,232 ns) |
> | LUT | 6.261 / 17.600 = **35,6%** |
> | FF | 5.024 / 35.200 = 14,3% |
> | BRAM | 39 / 60 = **65,0%** |
> | DSP | 18 / 80 = 22,5% |
> | Latencija 90×90/25×15 | **2.461.201 taktova = 27,07 ms** |
>
> Po instanci: `ncc0`/`ncc1` po 1.910 LUT / 1.240 FF / 19 RAMB36 / 9 DSP;
> `axi_interconnect_0` 1.616; `axi_cdma_0` 807.
>
> **Ceo tok se reprodukuje iz skripti:**
> `vivado.bat -mode batch -source src/vhdl/script/run_impl.tcl`
> (sam sourcuje `create_bd.tcl`; nosi kapije za blackbox IP, razilaženje kopija
> izvora i negativan WNS).
>
> ## PRVO sledeći put — dovršiti Korak 8 (8c, 8d, 8e)
>
> **8c — propusnost/latencija.** Model latencije je re-izveden posle preseka u jezgru:
> `T = 2·img_w·img_h + 2·N + res_w·res_h·(N + 112)`, gde je `N = tmp_w·tmp_h`
> (bilo `N + 110`; +2 takta po prozoru od dva nova stepena). Provereno na merenju:
> 2·8100 + 2·375 + 5016·487 = **2.459.742** naspram izmerenih 2.461.201 → 0,06%.
> ⚠️ **Dve ispravke ove beleške (2026-07-26):** zbir je **2.459.742**, ne 2.459.712
> (aritmetička greška od 30); i razlika **nije** od „prozora sa nultom varijansom koji
> preskaču takt" — izmereno je *veće* od modela, a preskakanje bi ga učinilo *manjim*, uz
> to 43 takta ne objašnjavaju 1.459. Ostatak je fiksna režija koju model ne obuhvata
> (inicijalizacija FSM-a, deljenje pri računanju srednje vrednosti šablona); **mehanizam
> nije izmeren**, pa se u dokumentaciji tako i piše.
> Ekstrapolacija na 90×90/30×30: **3.783.652 takta = 41,6 ms** @ 90,909 MHz
> (ESL/HLS referenca 10.360.183 taktova = 103,6 ms → **2,74× manje taktova**).
> Po piksel-operaciji na istom poslu (30×30): **1,13 naspram 3,09**. ⚠️ Brojka 1,30 iz
> ranijih beleški je sa **25×15** i ne ide uz 3,09 — sa njom bi ispalo 2,37×, što
> protivreči odnosu taktova.
>
> **8d — dokumentacija.** Proširiti PDF (`02 Dokumentacija/*.html` → headless Edge)
> poglavljem o integrisanom sistemu: topologija, adresna mapa, tabele 8a/8b iznad,
> i objašnjenje zašto je takt 90,909 a ne 100.
>
> **8e — poređenje sa PEUSN, tu je prava odluka.** Frekvencija je u redu: 90,909
> naspram 100 MHz = **9,1% odstupanja** (granica 20%). Problem je throughput: sa
> softverskim optimizacijama 1/3/4 (Korak 9) izlazimo na **~1,7 s** naspram ESL
> reference **3,667 s** → ~54% **u našu korist**, što formalno krši pravilo.
> **Ne zasporavati veštački.** Ispravan pristup: rekalibrisati `K_CYC`
> (`src/ncc.cpp:83`, sada `10360183/(61·61·30·30)`) našim izmerenim modelom, pustiti
> SystemC model ponovo i porediti jabuke sa jabukama — tada se sistemski model i HW
> moraju poklopiti unutar 20%, a razlika prema originalnoj ESL brojci se objašnjava
> time što je naš RTL 2,74× efikasniji po piksel-operaciji od HLS reference.
>
> ## Otvoreno / nepotvrđeno
>
> 1. ~~**Koja je tačno ploča**~~ — **RAZREŠENO 2026-08-26: originalni Zybo**
>    (`digilentinc.com:zybo:part0:2.0`), potvrđeno VGA konektorom na ploči.
>    Istorijski zapis pitanja: `board_part` je bio `digilentinc.com:zybo-z7-10:part0:1.2`,
>    ali korisnik nije imao ploču pred sobom. Part `xc7z010clg400-1` je siguran u oba
>    slučaja; razlikuje se samo PS preset. Originalni Zybo: **VGA + 1× HDMI**, PS_CLK
>    50 MHz, DDR3 512 MB (`digilentinc.com:zybo:part0:2.0`). Zybo Z7-10: **2× HDMI bez
>    VGA**, MIPI CSI, PS_CLK 33,333 MHz, DDR3L 1 GB. Pogrešan preset = ne bootuje i
>    UART je na pogrešnom baud rate-u → **bitno tek za Korak 9**, jedna linija u
>    `create_bd.tcl`.
> 2. **`.zip` arhiva IP-a je ZASTARELA** (popravke S01 + tipovi fajlova + revizija).
>    Regenerisati u Koraku 10 kroz `package_ip.tcl`, koji **mora** na kraju pozvati
>    `fix_ip_package.tcl` — wizard vraća `vhdlSource` i `ADDR_WIDTH=10`.
> 3. **Za punih 100 MHz** ostaje jedna poluga koja NIJE primenjena: inkrementalno
>    računanje adrese u unutrašnjoj petlji (registar + korak umesto množenja svaki
>    takt). Objašnjeno u `BUGS.md`. Bio bi to **treći** zahvat u verifikovano jezgro.
> 4. **Svesno odloženo:** `shared variable` u `dp_bram.vhd` nije protected tip, a fajl
>    je sad deklarisan kao VHDL-2008. Vivado to spušta na upozorenje; striktniji alati
>    (Questa/Riviera u -2008 režimu) bi odbili. Ne koristimo ih.
> 5. ~~**Git: ništa nije komitovano.**~~ **REŠENO 2026-08-26** — sve je komitovano
>    (`d0854e5`, `d39d1c1`) i pushovano; `main` i `korak6-axi-ip` su obe na `d39d1c1`
>    na `github.com/Lakic111/PSDS`.
>
> ## Korak 7 (gotovo)
>
> Block design `ncc_system` = Zynq PS (board preset) + `proc_sys_reset` + 2× `ncc_accel`
> + `axi_cdma` (mem-na-mem, simple mode) + **jedan `axi_interconnect`** (`STRATEGY=1`,
> deljena magistrala, 2 mastera → 6 slave-ova). Jedan takt na sve, bez CDC.
> `S_AXI_HP0` sužen na **32 bita**. Fiksna adresna mapa po ESL `common.hpp` — tabela u
> projektnom `CLAUDE.md`. Dizajn: `01 Razvoj/(C) Korak 7 - Dizajn integracije
> (block design).md`; plan: `(C) Korak 7 - Plan implementacije (block design).md`
> (sadrži i tri greške nađene u samom planu, da se ne ponove).
>
> **Korak 6 (gotovo):** IP `ncc_accel` spakovan (slave + interne memorije, obrazac
> matrix-multiply iz vežbe). Dizajn: `01 Razvoj/(C) Korak 6 - Dizajn AXI omotača
> (IP pakovanje).md`; plan/koraci: `(C) Korak 6 - Plan implementacije (AXI IP).md`.
> Izvori su od Koraka 7 **konsolidovani u `src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/`**
> (`src/vhdl/ip/` je obrisan — bio je duplikat). `.zip` arhiva IP-a je **zastarela**
> posle popravke S01, regeneriše se u Koraku 10.

**Merodavan opis dizajna** je od sada PDF dokumentacija:
`02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf` (izvor: `.html` pored
njega). Markdown `(C) Korak 2 - Opis algoritma, ASMD...md` opisuje PRVOBITNI
dizajn (9 stanja, kombinaciona deljenja) i zadržan je samo kao istorija — ne
koristiti ga kao referencu za trenutni kod.

Otvorene sitnice (nijedna nije blokirajuća):

1. `sat_t` je 32-bitna, a dovoljna je **21 bita** (max suma 90·90·255 =
   2.065.500) — suženje bi spustilo BRAM sa 9 na ~6 blokova. Dokumentovano u
   PDF-u (odeljak 7.2) kao poznata rezerva.
2. Vivado projekat korisnika (`src/vhdl/result/ncc_core`) ima "Target language:
   Verilog" projektno podešavanje — nebitno za naše `.vhd` fajlove, ali vredi
   promeniti na VHDL radi doslednosti kad se doda block design wrapper
   (Korak 7) — ponuđeno korisniku, nije još urađeno.
3. Korak 7 (block design) nije dobro pokriven pročitanim vežbama (Vezba 8-9
   staje na pakovanju IP-a) — tražiti dodatni izvor kad dođe na red.

### Kako regenerisati PDF dokumentaciju

Izmeni `.html`, pa headless Edge (pandoc/LaTeX/Word NISU instalirani na ovoj
mašini; Edge jeste):

```
--headless=old --disable-gpu --no-first-run --user-data-dir=<svež temp profil>
--virtual-time-budget=12000 --no-pdf-header-footer --print-to-pdf=<temp>\out.pdf <file:// URL>
```

Dve zamke, obe potvrđene: **(a)** ciljna putanja PDF-a NE SME imati razmake —
Edge je protumači kao više URL-ova ("Multiple targets are not supported"), pa
generiši u temp folder bez razmaka i onda kopiraj; **(b)** `--print-to-pdf-no-header`
NE radi u ovoj verziji, ispravan naziv je `--no-pdf-header-footer` (inače Edge
utisne datum i lokalnu putanju do fajla u zaglavlje/podnožje).

## Istorija sesija

### 2026-07-26 (nastavak) — KORAK 8 ZAVRŠEN: dokumentacija proširena na Korake 2-8

Nastavak istog dana. Korak 8 izvršen kroz **plan od 10 taskova**, prvo subagent-driven
(Taskovi 1-4), pa inline zbog cene (Taskovi 5-10), sa nezavisnom recenzijom za Task 7.

**Rezultat:** `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-8.pdf` — **34 strane**
(bilo 22), 24 tabele, 4 SVG dijagrama. Tri nova poglavlja (IP jezgro, integracija sa novim
blok dijagramom, analiza sistema) i usklađena poglavlja 4-7. Deset commit-ova na
`korak6-axi-ip`, od `8a999fb` do `ebf3346`.

**Re-mereno pre pisanja, ne prepisano:** goli `ncc_core` post-route na `clg400-1`, na oba
ograničenja takta. Nalaz koji je promenio zaključak projekta: **jezgro ZATVARA 100 MHz**
(WNS +0,146 ns, Fmax ~101,5 MHz). Ograničenje je **integracija**, ne RTL — sistem na 10 ns
daje −0,232 ns. `BUGS.md` naslov „ncc_core ne zatvara 100 MHz" je time povučen.

**Sva šest testbencheva ponovo pušteno i prolaze** — presek jezgra (MAC pipeline + registar
pred delilac) i popravka `wr_beat` nisu promenili izlaz: `0x80000000 @ (32,14)`,
bit-identično Koraku 4. Latencija 2.461.201 takt, potvrđena nezavisno.

**Jedanaest ispravki plana i beleški, sve nađene pri izvršavanju.** Tri klase:
1. **Preživele zastarele tvrdnje** — §5.5 je opisivao dvostepenu protočnost pored nove
   trostepene; §7.3 je predlagao registar koji je već dodat; §4.4 je tvrdio da postoji
   deljena memorija koje nema. Sve tri su u diff-u bile „context" linije. Otud **pravilo
   celog pasusa**.
2. **Izmišljena imena signala** — `den_f`/`den_t` i `diff_f`/`diff_t` ne postoje u RTL-u.
3. **Aritmetičke i metodološke greške u nasleđenim brojkama** — model je davao 2.459.742
   a ne 2.459.712; „prozori sa nultom varijansom" ne mogu biti uzrok razlike (izmereno je
   *veće* od modela); „1,30 vs 3,09 → 2,74×" ne stoji, jer je 1,30 sa 25×15 a 3,09 sa
   30×30 (na istom poslu je 1,13).

**Nov metodološki zapis u `BUGS.md`:** rezerva se ne prevodi aritmetički između ograničenja
takta — alat optimizuje *do* cilja i staje, pa je putanja na labavijem ograničenju duža.
Fmax izveden iz merenja na 11 ns davao je lažnih 94 MHz umesto 101,5. To je **četvrti**
slučaj istog obrasca u projektu (uzrok iz jednog merenja), pa je `run_synth_core.tcl`
parametrizovan da se meri na ograničenju koje se tvrdi.

**8e po odluci korisnika bez rekalibracije `K_CYC`** — porede se resursi i taktovi, gde je
poređenje pošteno; ukupno vreme table se ne problematizuje. SystemC nije instaliran.

**Nekomitovano:** ~~korisnik je odlučio da se njegovih 25 nekomitovanih fajlova ne dira, pa
svaki commit dira samo ciljni HTML.~~ **Prevaziđeno 2026-08-26** — sve je komitovano
(`d0854e5`, `d39d1c1`) i pushovano na GitHub.

### 2026-07-26 — Korak 8a/8b izmereni + code review otkrio 3 AXI buga

Nastavak iste sesije. **Timing je dominirao danom** i završen je uspešno, ali kroz
niz pogrešnih hipoteza koje vredi zapamtiti.

**Timing: −3,299 → +0,170 ns**, kroz četiri mere (redosled je i redosled dobitka):
1. **MAC pipeline** u `ncc_core` — `df_reg`/`dt_reg` + `mac_v_reg`, razdvaja
   BRAM→oduzimanje od množenje→akumulator. **+2,43 ns.**
2. **`phys_opt_design`** + `Performance_ExplorePostRoutePhysOpt` strategija.
   **+0,481 ns** — više nego drugi RTL presek. Sad je deo build ugovora u
   `create_bd.tcl`, ne opcija: bez toga dizajn ne zatvara.
3. **SmartConnect → AXI Interconnect** (`STRATEGY=1`). Površina 8.673 → 1.616 LUT.
4. **Registar pred delilac** (`num_sq_reg`/`den_prod_reg`, poluga iz `IDEJE.md`).
   **+0,155 ns** — putanja se odmah premestila na adresnu.

Uz to `S_AXI_HP0` sužen na 32 bita: uklonio 6 konvertora širine, **−3.334 LUT /
−3.659 FF**. FSM jezgra 21 → 23 stanja, latencija **+0,41%**, izlaz **bit-identičan**.

**Tri pogrešne hipoteze, sve isti obrazac — uzrok pripisan iz JEDNOG merenja:**
- „Merenje je degenerisano zbog 118 IOB naspram 100" → OOC sinteza sa **nula** IOB-ova
  dala istu razliku. Trebalo je odmah primetiti da je prekoračenje *veće* na partu
  koji prolazi (218% vs 118%).
- „Kritična putanja ide kroz konvertor širine, uklanjanje vraća 100 MHz" → konvertori
  uklonjeni, WNS se pomerio sa −0,233 na −0,232 ns. Vezujuća putanja je sve vreme bila
  adresna u `ncc_core`; konvertor se pojavio kao najgori samo u merenju na 11 ns.
- „Odgovor daje Korak 8" kao razlog za odlaganje odluke → integracija timing može samo
  pogoršati, odluka je bila potrebna odmah.

**Code review (`/code-review`) našao 15 nalaza; 14 rešeno.** Najozbiljniji je klaster
AXI handshake-a — i **nije bio teorijski**:
- Generisani kontroleri drže `wready` na `'1'` od `Idle` nadalje, a korisnička logika je
  dekodirala adresu bez kvalifikacije handshake-a. S00 je upisivao registre na golo
  `S_AXI_WVALID` (bez `wready`, bez prihvaćenog AW).
- Dokazano testom: nad starom logikom **7 od 8 beat-ova upisnog bursta se gubi**, a upis
  sa `WSTRB(0)='0'` gazi piksel. Sa CDMA burst-ovima od 8100 reči = tiho pokvarena slika.
- Popravljeno uvođenjem `wr_beat` (W uz prihvaćen AW) u oba kontrolera + poštovanje
  `WSTRB(0)`. `ncc_accel_burst_tb` proširen sa tri provere (RLAST po beat-u, WSTRB,
  rani AW) — **prvo dokazano da padaju nad starom logikom, pa da prolaze nad novom.**

Ostali nalazi: WRAP burst look-ahead, `core_revision` + isključen IP keš, kapija za
blackbox preseljena u repo (`run_impl.tcl`), kapija protiv razilaženja dve kopije
izvora, `create_clock` pre `synth_design` (+ OOC režim), simulacione tvrdnje za
dimenzije, dokumentovan ugovor o taktu S00/S01, `.gitignore`, i usklađena dokumentacija.
Puni zapis u `BUGS.md`.

**Nove skripte u repou:** `run_impl.tcl` (pun tok sa kapijama), `fix_ip_package.tcl`
(post-package popravke, obavezno posle svakog Package IP-a), `ncc_core_ooc.xdc`,
`open_bd.tcl`. `run_synth_core.tcl` prepravljen (OOC + constraint pre sinteze).

### 2026-07-25 — Korak 7 ZAVRŠEN (block design) + popravljen bug u IP-u iz Koraka 6

- **Odluka o DMA (bila otvorena od 24.07.):** korisnik je tražio da se PRVO detaljno
  pročitaju svi kodovi pre odluke. To se isplatilo — čitanje generisanog
  `ncc_accel_slave_full_v1_0_S01_AXI.vhd` je otkrilo da **burst čitanje ne radi**, što je
  potpuno promenilo okvir odluke (CDMA čitanje rezultata bilo bi nemoguće).
  Odabrano: **popravka + CDMA u oba smera**, umesto ranije preporuke „CPU-direktno".
- **Nađen bug: S01 burst čitanje vraća prethodnu reč** na svakom beat-u posle prvog
  (7/8 pogrešno na `arlen=7`); write burst-ovi rade 8/8. Uzrok: generisani Xilinx šablon
  čita primer-RAM kombinaciono, a Korak 6 ga je zamenio registrovanim `dp_bram`-om i
  popravio poravnanje **samo za prvi beat**. Nije uhvaćeno jer `ncc_accel_tb` koristi
  isključivo `awlen=0`/`arlen=0`. Popravljeno look-ahead adresom; napisan
  `src/vhdl/tb/ncc_accel_burst_tb.vhd` (RED pre, GREEN posle); zlatni TB nepromenjen
  (`0x80000000 @ idx 956`). Puni zapis u `BUGS.md`.
- **Korekcija ciljnog čipa:** vault je tvrdio „Zybo Z7-10 = `xc7z010-clg225-2`" — te dve
  stvari nisu spojive. Provereno kroz Digilent board fajlove: **nijedna** Digilent ploča
  ne koristi `clg225`; svaka Zynq-7010 je `xc7z010clg400-1`. `clg225-2` iz ESL
  dokumentacije je bio Vitis HLS default, ne ploča. Part promenjen na `clg400-1`
  (isti čip, identičan kapacitet, speed grade `-1`).
- **Instalirani Digilent board files** (`zybo`, `zybo-z7-10`, `zybo-z7-20`) u
  `C:\AMDDesignTools\2025.2\Vivado\data\boards\board_files\` — pre toga ih nije bilo
  nijedan (0 `board.xml`), pa PS ne bi imao ispravan DDR/MIO/PS_CLK preset.
- **Block design izgrađen TCL skriptom u batch-u**, bez GUI-a: `create_bd.tcl`,
  `validate_bd_design` čist, wrapper elaborira. Fiksna adresna mapa po ESL `common.hpp`.
- **Tri greške u sopstvenom planu, nađene pri izvršavanju** (zapisane u planu da se ne
  ponove): (a) `M_AXI_GP0_ACLK`/`S_AXI_HP0_ACLK` moraju biti vezani u istom tasku u kome
  se AXI portovi uključuju, inače `validate_bd_design` pada; (b) **`exclude_bd_addr_seg`
  MORA ići posle svih `assign_bd_address`** — inače segment tiho nestane iz mape bez
  ERROR-a (DDR je tako „nestao" iz CDMA mape); (c) `report_utilization -hierarchical_depth`
  ne radi bez `-hierarchical`.
- **Timing na novom partu je otvoreno pitanje, ne rešeno:** samostalna sinteza `ncc_core`
  na `clg400-1` daje WNS **−0,660 ns**. Ali merenje je degenerisano (118 IOB naspram
  100/54 dostupnih). Kontrolni eksperiment na `clg225-2` reprodukuje Korak 5 egzaktno
  (+1,179 ns, 8,670 ns, ista raspodela) → tok je ispravan, merenje nije pouzdano.
  **`ncc_core.vhd` NIJE diran** — bilo bi prerano menjati verifikovano jezgro na osnovu
  takvog merenja. Odgovor daje Korak 8.
- Izvori konsolidovani: `src/vhdl/ip/` obrisan (duplikat), `ip_repo` je jedini merodavan.

### 2026-07-24 — Korak 6 ZAVRŠEN (AXI IP pakovanje)
- **Odluka arhitekture (potvrđena čitanjem celog PDF-a Vežbe 08-09, str. 229–302):**
  vežba razrađuje ISKLJUČIVO obrazac *slave + interne memorije* (matrix-multiply:
  AXI-Lite slave za registre + AXI-Full slave za interne memorije A/B/C). **Nema
  master interfejsa nigde**, ni integracije u block design. Zato NCC spakovan istim
  obrascem — kao čist slave sa internim memorijama, `ncc_core` NEPROMENJEN.
  Divergencija od ESL `i_bram` master modela dokumentovana (REG_IMG_ADDR/TMP_ADDR
  postali rezervisani).
- **Napisano/verifikovano (lokalni xsim, isti tok kao Korak 3–5):**
  `src/vhdl/ip/dp_bram.vhd` (true-dual-port RAM) i `mem_subsystem.vhd` (3× dp_bram
  + adresni dekoder: region=addr(16:15), word=addr(14:2)) — oba sa unit testovima,
  PASS.
- **Wizard (korisnik, GUI):** „Create a new AXI4 peripheral" → S00 Lite (16 reg) +
  S01 Full. **Zamka:** prvo generisao Verilog (projekat bio „Target language:
  Verilog") → prebačeno na VHDL, regenerisano. **Druga zamka:** wizard „Memory Size"
  staje na 1024 B → `C_S01_AXI_ADDR_WIDTH` ručno postavljen na 17 (128 KB); u
  paketu opseg S01 = 131072.
- **Modifikacije generisanih kontrolera** (`src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/hdl/`):
  S00 — `img_w/h`, `tmp_w/h` iz slv_reg0..3, 1-taktni `start` puls na CTRL(0x30)
  bit0, sticky `done` (jer je `ncc_core.done` puls), STATUS(0x34)=busy&done. S01 —
  ADDR 17-bit, `low` literal → (others=>'0'), RDATA iz `mem_rdata_i`, adresa na
  ciklusu prihvata (poravnanje sa 1-taktnim dp_bram čitanjem). Top — prepisana
  arhitektura na direktnu instancijaciju + `mem_subsystem` + `ncc_core` + konverzije
  integer↔slv.
- **Integracioni TB `ncc_accel_tb.vhd`** (glumi CPU/DMA preko AXI): upiše dimenzije
  (Lite), sliku 90×90 + šablon 25×15 (Full, jedan piksel/reč, realni `seg90.txt`/
  `crnitop.txt` iz Koraka 4), start, poll STATUS, čita 66×76 rezultata. **PASS:
  peak `0x80000000` @ idx 956 = (u=32, v=14)** — bit-identično golom `ncc_core`
  (Korak 4). Omotač potpuno transparentan.
- **Spakovano:** File Groups merge, Compatibility=Zynq, Addressing S01=128 KB
  (zamka: „128K" ne sme u „Range Dependency" nego Range=131072), Create archive →
  Package IP. Arhiva `ip_repo/ncc_accel_1_0/xilinx.com_user_ncc_accel_1.0.zip`.

### 2026-07-22 — Zvanična dokumentacija (Koraci 2 i 5) za profesora
- Zatečeno: kod je 21.07. otišao daleko ispred beleški — `ncc_core.vhd` prerađen
  (sekvencijalni delioci + protočna petlja), dodat `ncc_core_real_tb.vhd`, i
  napisan `(C) Korak 5 - Analiza sinteze.md`, ali `CLAUDE.md`, plan fajl i ova
  beleška su i dalje tvrdili da Korak 3 "nije finalan". Sinhronizovano na kraju
  ove sesije.
- **Sve brojke nezavisno re-verifikovane u ovoj sesiji**, nisu prepisane iz
  beleški: oba testbencha ponovo pokrenuta (prolaze), `synth_design` +
  `report_timing_summary` ponovo pokrenuti sa `create_clock`. Poklapaju se sa
  onim što je 21.07. zapisano.
- Napisana **PDF dokumentacija za profesora** (25 strana) po uzoru na ESL
  dokumentaciju: `02 Dokumentacija/PSDS_dokumentacija_y25-g10_Korak2-5.pdf`
  (+ `.html` izvor). Koraci 2 i 5 u jednom dokumentu, 16 tabela, 3 ručno crtana
  SVG dijagrama (ASMD sa 21 stanjem, protočnost unutrašnje petlje,
  datapath/controlpath). Mermaid nije upotrebljiv (nema interneta u headless
  renderu), pa su dijagrami pisani direktno u SVG-u.
- **Odluka korisnika:** dokumentovati dizajn KAKAV JESTE (finalnih 21 stanje), uz
  pododeljak "Evolucija dizajna" koji objašnjava odstupanja od prvobitnog dizajna
  — umesto da se čuva zastareli ASMD sa 9 stanja. Razlog: profesor pregleda kod I
  dokumentaciju zajedno, neslaganje bi bilo prvo što primeti.
- U dokument je namerno uključena i **jedna slabost**: 9 RAMB36 naspram
  referentnih 4×BRAM_18K, zbog preširoke `sat_t` reči (32 bita umesto 21).
  Bolje da profesor to pročita nego da pita.
- **Poređenje sa ESL/HLS referencom normalizovano** — sirovi brojevi nisu
  uporedivi (ESL meren na 30×30, naš na 25×15). Po taktu na piksel-operaciju:
  3.09 naspram 1.30. Izveden i potvrđen model latencije
  `T = 2·img_w·img_h + 2·N + res_w·res_h·(N+110)` (odstupanje od merenja 0.06%),
  pa ekstrapolacija na 90×90/30×30 daje 3.78 M taktova naspram 10.36 M → 2.74×.
  Ovo je gotov ulaz za Korak 8e.
- Naslovna strana: **bez ličnih imena**, samo oznaka grupe `y25-g10` — provereno
  da ni ESL PDF nema imena (počinje Sadržajem, metapodaci prazni), jedina oznaka
  je u imenu fajla.

### 2026-07-21 — Korak 3 finalizovan + Korak 4 + Korak 5 (sesija bez zapisa u ovoj beleški)
Rekonstruisano 2026-07-22 iz koda, git istorije i `(C) Korak 5 - Analiza sinteze.md`:
- `ncc_core.vhd` prerađen u finalnu verziju: dodat `seq_divider` (restoring delilac,
  W=18 i W=83) jer kombinaciona deljenja nisu zatvarala timing (WNS ≈ −46 ns), i
  unutrašnja MAC petlja pipeline-ovana (`S_L_YX_FILL/RUN/DRAIN`, 1 takt/piksel).
  FSM 11 → **21 stanje**. LUT 6383 → 1526, BRAM 16 → 9, WNS → +1.179 ns.
- Napisan `tb/ncc_core_real_tb.vhd` + izvučeni podaci `tb/seg90.txt`,
  `tb/crnitop.txt` → Korak 4 završen (peak 0x80000000 @ (32,14)).
- Napisan `02 Dokumentacija/(C) Korak 5 - Analiza sinteze.md` → Korak 5 završen.
- Napravljen git repo i prvi commit (`5759e33`, 21.07. 21:16).

### 2026-07-20 (nastavak 3) — Korak 3, prva verzija VHDL-a

- Korisnik odlučio (posle direktnog čitanja pravilnika) da Korak 3 ide kroz
  **ručni VHDL**, ne Vitis HLS kako je ranije "potvrđeno" — pravilnik je
  tool-agnostic, i Vezba 3-5 eksplicitno kaže da profesor to očekuje.
- Otkriveno (usput) da su Vivado 2025.2 I Vitis HLS zapravo INSTALIRANI na ovoj
  mašini, na `C:\AMDDesignTools\2025.2\` — ranija tvrdnja da nisu bila je
  greška (provera je tražila samo `C:\Xilinx`).
- Napisan `src/vhdl/ncc_pkg.vhd` + `ncc_core.vhd` (FSM+datapath, dvoprocesni
  stil) + `tb/ncc_core_tb.vhd`, TDD (testbench prvo, RED, pa GREEN) — isti
  golden test kao Korak 1 (4×4/2×2, 9 tačaka).
- Korisnik pitao da li je jednoprocesni stil OK — prepravljeno u pravi
  dvoprocesni stil (Vezba 3-5 preporuka), isti test i dalje prolazi.
- Korisnik pitao "koliko traje sinteza" — pokrenuta probna sinteza,
  **>10 min, netlist od 42045 primitiva** (puni nizovi `image_in`/`templ_in`/
  `result_out` na portu, svaki element poseban pin). Korisnik prekinuo
  (`Stop-Process` na vivado.exe), prepravljeno u adresirane BRAM-stil portove
  (adresa+podatak, sinhrono, kao pravi BRAM) — FSM 9→11 stanja.
- Korisnik otkrio (screenshot) da Vivado projekat ima "Target language:
  Verilog" — razjašnjeno da je to samo podešavanje za auto-generisane fajlove,
  ne primorava naše VHDL izvore.
- Korisnik pokrenuo pravu sintezu (svoj Vivado GUI): **0 BRAM, 48610 LUT
  (276% preko budžeta)** — uzrok: `sat_mem` čitana kombinaciono, 4 adrese
  istovremeno u `S_L_U`. Popravljeno (5 stanja `S_L_U_A..E`, sinhrono čitanje,
  izolovan `sat_ram_proc`) — korisnik ponovio sintezu, **i dalje 0 BRAM**.
  Pravi uzrok pronađen (`grep sat_mem`): JOŠ JEDNO kombinaciono čitanje u
  `S_LOAD_IMG_DATA` (SAT red iznad, tokom izgradnje SAT-a), previđeno u prvoj
  popravci. Popravljeno — potvrđeno SAMOSTALNOM sintezom (van korisnikovog
  projekta): **16 BRAM, 6383 LUT (36%), 9 DSP**, staje na pločicu sa velikom
  rezervom. Simulacija (isti golden test) nepromenjena kroz sve popravke.
- Korisnik razjasnio krajnji cilj: `ncc_core` treba da postane **funkcionalni
  IP blok povezan preko AXI protokola** sa DMA/BRAM/RAM u block integratoru —
  potvrđuje plan da AXI omotač ide u Korak 6, ne u Korak 3.
- Objašnjeno korisniku da je testbench šablon (2×2) sintetički, namerno ugrađen
  u 4×4 sliku da pokrije oba ekstrema (0 i 2³¹) — prava data (board2.txt) su
  korišćena samo u C testu (Korak 1), ne još u VHDL-u.
- **Korisnik eksplicitno rekao da ništa od ovoga nije finalno** — sledeća
  sesija treba da proveri stanje pre nastavka. (Bio je u pravu: sutradan je
  usledila prerada u finalnu verziju, videti zapis za 2026-07-21 iznad.)

### 2026-07-20 — Korak 1 ZAVRŠEN (TDD, prva sesija koja piše kod)
- Korisnik zatražio nastavak rada; prethodne beleške u vault-u pokazale tačno gde
  se stalo (Korak 1, sledeća sesija).
- **Toolchain instaliran na ovoj mašini** (nije postojao): MSYS2/mingw-w64 g++
  (`C:\Users\pc\msys64`, dodat u PATH korisnika) preko self-extracting arhive sa
  GitHub-a (msys2-installer nightly release). Korisnik izabrao ovu opciju eksplicitno
  (pitan preko AskUserQuestion) umesto pisanja koda bez lokalne verifikacije.
- **Xilinx open-source `ap_int.h`/`ap_fixed.h`** povučen sa
  https://github.com/Xilinx/HLS_arbitrary_Precision_Types u `src/hls/ap_headers/include/`
  — omogućava STVARNO kompajliranje sa pravim `ap_uint`/`ap_int`/`ap_ufixed`
  semantikom lokalno, bez punog Vitis HLS-a (koji ovde nije instaliran).
- Primenjen TDD (superpowers:test-driven-development skill): napisan
  `test_ncc_kernel.cpp` sa NEZAVISNIM golden oracle-om (čist int/`__int128`, bez
  ap_int) PRE kernela → potvrđen RED (link greška, funkcija ne postoji) → napisan
  `ncc_kernel.cpp`/`.hpp` → GREEN (svi testovi prošli) → prošireno sa graničnim
  slučajem (nulta varijansa) i punim opsegom 90×90/30×30 (3721 tačaka, sve tačne).
- **Otkrivena i ispravljena greška u ESL dokumentaciji (Tabela 2):** `diff_f`/
  `diff_t` i `sum_num` moraju biti SIGNED (`ap_int`, ne `ap_uint`/`sc_uint` kako
  dokument navodi) — piksel-minus-sredina i suma proizvoda mogu biti negativni.
  Broj bita (9, 27) ostaje isti, menja se samo signedness. Vredno pomena na
  odbrani/u dokumentaciji koraka 2.
- **Q1.31 podela urađena kao egzaktna celobrojna** (`(num_sq << 31) / den_prod`
  u širem `ap_uint<96>`), ne double množenje kao u originalnom `ncc.cpp` — bit-
  egzaktan izlaz. Napomena: `ncc2 > 1.0` safety clamp iz `ncc.cpp` matematički
  otpada u ovoj verziji (Cauchy-Schwarz garantuje `num_sq <= den_prod` egzaktno
  u celobrojnoj aritmetici, bez float zaokruživanja koje je taj clamp
  originalno pravdalo).
- Detalji, build komanda i puna lista fajlova:
  `01 Razvoj/(C) Plan implementacije (10 koraka).md` → Korak 1.
- Nije rađeno: unakrsna provera protiv stvarnog SystemC `ncc.cpp` izvršavanja
  (zahtevalo bi SystemC biblioteku instaliranu ovde, van obima ove sesije) —
  golden oracle u testu je nezavisna reimplementacija istog algoritma, ne
  pokretanje SystemC modela.

### 2026-07-14 (nastavak 2) — ESL/PEUSN dokumentacija pročitana, HLS odluka potvrđena
- Korisnik dostavio `ESL dokumentaccija pdf/ESL_dokumentacija_y25-g10_1-2.pdf` — zvanična
  dokumentacija SystemC/TLM virtuelne platforme sa PEUSN predmeta (prethodna faza ovog
  istog projekta). Pročitana u celosti i izdvojena u
  `00 Pregled/(C) ESL dokumentacija - izvod.md`.
- **HLS odluka POTVRĐENA eksplicitno** (ranije samo posredno nagoveštena iz Vezbe
  10-12): dokument doslovno navodi da je NCC jezgro već sintetizovano u **Vitis HLS
  2023.1** za **xc7z010-clg225-2 (Zynq-7010)**, sa latencijom 10.360.183 ciklusa
  (tačan izvor `K_CYC` konstante) i tačnim resursima (4 BRAM_18K/16 DSP48E/3455 FF/
  5269 LUT po instanci).
- **Korekcija ciljne ploče:** Zybo Z7-10, ne ZedBoard/Zynq-7020 (ispravljeno u
  CLAUDE.md i plan fajlu — ranija pretpostavka je bila zasnovana samo na Vezbi 1
  koja koristi ZedBoard kao generički tutorial primer).
- Dobijene tačne bitske širine (Tabela 2 u ESL dok.) za sve signale u NCC datapath-u —
  direktan `ap_uint`/`ap_int` plan za korak 1, upisano u plan fajl.
- Dobijene tačne referentne brojke za korak 8e: ukupno vreme obrade `board2.txt` =
  3.667s (2 NCC + optimizacije, 10.8× ubrzanje) — glavni throughput cilj za poređenje
  na realnoj ploči.
- Ova sesija i dalje NIJE pisala kod niti pokretala alate — čista priprema.

### 2026-07-14 (nastavak) — Sve vežbe pročitane i izdvojene

### 2026-07-14 (nastavak) — Sve vežbe pročitane i izdvojene
- Pročitano svih 8 laboratorijskih materijala iz `Vezbe pdf/` (paralelno, 8 fork
  agenata) i izdvojeno u `01 Razvoj/Vezbe/` — po jedan fajl po vežbi, sa konkretnim
  instrukcijama primenjenim na naš NCC projekat (ne generički sažeci).
- PDF-ovi kopirani u `06 Prilozi/Vezbe/` radi reference unutar vault-a.
- **Ključan zaokret:** čitanje Vezbe 10-12 (HLS) je pokazalo da korak 3 (RTL) verovatno
  treba da ide kroz **Vivado HLS**, ne ručni VHDL kako je prvobitno pretpostavljeno —
  `K_CYC` komentar u `ncc.cpp` je otisak HLS Performance Estimates izveštaja, znači je
  neko već pustio ovaj kernel kroz HLS u ranijoj fazi projekta. Detalji i puno
  obrazloženje: `01 Razvoj/(C) Vezbe - indeks i strateska odluka.md`. Plan i CLAUDE.md
  ažurirani da odražavaju ovo.
- Ova sesija NIJE pisala kod niti pokretala Vivado/Vitis — čisto priprema/dokumentacija
  za sledeću sesiju (po dogovoru sa korisnikom).
- Otvoreno: korak 7 (integracija u block design) nije dobro pokriven pročitanim
  vežbama (Vezba 8-9 staje na pakovanju IP-a) — treba dodatni izvor kad dođe na red.

### 2026-07-14 — Vault kreiran
- Napravljen ovaj Obsidian vault (`PSDS Vault/`), po uzoru na StefanOS/KJ OS Template
  strukturu, ali kao potpuno odvojen vault posvećen samo ovom projektu.
- Pregledan ceo `src/` (common, bram, ddr, dma, ncc, sys_bus, tb, vp, sc_main) i
  PDF pravilnika (`06 Prilozi/Bodovanje projekta.pdf`).
- Napisan pregled arhitekture (`00 Pregled/`) i plan po 10 koraka (`01 Razvoj/`).
- Zaključak: sistem je šahovski NCC template-matching akcelerator; SystemC/TLM model
  je gotov i već ima adresnu mapu/interfejs/timing kalibraciju koji liče na realan
  HW.
