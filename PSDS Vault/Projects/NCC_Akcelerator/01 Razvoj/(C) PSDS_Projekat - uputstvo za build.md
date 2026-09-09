# PSDS — NCC akcelerator za prepoznavanje šahovskih figura

Hardverski akcelerator za normalizovanu unakrsnu korelaciju (NCC), na Zynq-7010
(Digilent Zybo). Sa slike šahovske table 720×720 prepoznaje figure i ispisuje poziciju
u FEN notaciji.

Struktura direktorijuma prati **Vježbu 13, tabela 8.1**.

---

## Struktura

```
PSDS_Projekat/
├── release/          finalni artefakti: ncc_system.bit, ncc_system.xsa
├── result/           radni Vivado projekat i međurezultati (SVE generisano)
├── ip_repo/          spakovan IP ncc_accel (izlaz package_ip.tcl)
└── src/
    ├── vhdl/         RTL izvori (7 fajlova)
    ├── tb/           testbenchovi (8) + realni podaci (seg90.txt, crnitop.txt)
    ├── xdc/          vremenska ograničenja (ncc_core_ooc.xdc)
    ├── c/            bare-metal aplikacija za Cortex-A9
    └── script/       sve TCL skripte
```

`result/` i `release/` se **u potpunosti regenerišu** iz `src/`. Mogu se obrisati.

---

## Kako se gradi

Sve iz `src/script/`. Vivado je na `C:\AMDDesignTools\2025.2\`.

### Cio tok, jednom komandom

```
cd src\script
vivado.bat -mode batch -source build_all.tcl
```

Radi redom: **pakuje IP → pravi block design → sinteza → implementacija → bitstream →
XSA → kopira u `release/`**. Traje oko 45 minuta.

Opcije (postaviti prije pokretanja):

| Promjenljiva | Zadano | Značenje |
|---|---|---|
| `NCC_SKIP_PACKAGE` | 0 | 1 = preskoči pakovanje, koristi zatečeni `ip_repo/` |
| `NCC_FCLK` | 95 | traženi PL takt u MHz (95 → PLL daje 90,909) |

### Softver i pokretanje na ploči

```
xsct.bat build_app.tcl      gradi Vitis platformu iz XSA i aplikaciju
xsct.bat run_app.tcl        programira PL, spušta .elf, pokreće
```

⚠️ `xsct.bat` je u `Vitis\bin`, **ne** u `Vivado\bin`.

UART se čita bez ijednog dodatnog programa:

```
powershell -File uart_log.ps1 -Port COM6 -Seconds 120 -Out uart.txt
```

### Verifikacija

```
vivado.bat -mode batch -source run_sim.tcl                 svi testbenchovi
vivado.bat -mode batch -source run_sim.tcl -tclargs ncc_core_tb   samo jedan
```

Skripta **pada** ako neki testbench prijavi `FAIL` — ne samo što ga pokrene.

---

## Skripte

| Skripta | Šta radi |
|---|---|
| `build_all.tcl` | cio lanac od izvora do `release/` |
| `package_ip.tcl` | pakuje `ncc_accel` iz izvora; **sam zove `fix_ip_package.tcl`** |
| `fix_ip_package.tcl` | popravlja ono što Package IP wizard pokvari |
| `create_bd.tcl` | block design `ncc_system` |
| `run_impl.tcl` | sinteza → implementacija → bitstream → XSA, sa četiri kapije |
| `run_sim.tcl` | svi testbenchovi, sa provjerom rezultata |
| `run_synth_core.tcl` | OOC sinteza golog jezgra (mjerenje Fmax) |
| `open_bd.tcl` | otvara block design u GUI-u |
| `build_app.tcl`, `run_app.tcl` | Vitis strana |
| `uart_log.ps1` | snimanje UART-a |

---

## Tri stvari koje treba znati prije nego se nešto mijenja

**1. `package_ip.tcl` MORA zvati `fix_ip_package.tcl`.** Wizard vraća tip fajla na
`vhdlSource` (umjesto `vhdlSource-2008`) i `C_S01_AXI_ADDR_WIDTH` na 10 (umjesto 17).
Oba su **tiha**: sa pogrešnim tipom IP se sintetiše kao **prazna kutija bez ijedne
greške** — sinteza prođe 100 %, a padne tek implementacija.

**2. `run_impl.tcl` nosi četiri kapije** i pada glasno umjesto da proizvede loš rezultat:

| Kapija | Provjerava |
|---|---|
| 1 | IP nije sintetisan kao blackbox |
| 2 | timing zatvara (WNS ≥ 0) |
| 3 | bitstream se ne pravi ako timing ne zatvara |
| 4 | XSA stvarno sadrži `.bit` |

**3. Prenosi u aplikaciji idu procesorom, ne DMA-om.** `#define NCC_USE_CDMA 0` u
`src/c/ncc_hw.c`. Burstovi duži od dva beata zaglavljuju `axi_interconnect_0`
(izmjereno preko JTAG-a). Košta oko 9 % vremena. DMA **ostaje u block designu**;
povratak je promjena te nule u jedinicu.

---

## Izmjereni rezultati

Post-route, `xc7z010clg400-1`, takt 90,909 MHz:

| | |
|---|---|
| Slice LUT | 6.225 / 17.600 = **35,4 %** |
| Slice registri | 5.020 / 35.200 = 14,3 % |
| Block RAM | 39 / 60 = **65,0 %** |
| DSP48E1 | 18 / 80 = 22,5 % |
| WNS | **+0,268 ns** na 11,0 ns |

Na ploči, cijela tabla: **32/32 polja**, FEN znak po znak tačan, **1.782 ms**
(računanje 87,3 %, prenosi 10,5 %). Referentno ESL rješenje traje 3,667 s —
**2,06× sporije**.

Sistem zatvara i **100 MHz** (WNS +0,032 ns), ali je radna tačka ostavljena na
90,909 MHz jer su sve brojke mjerene na njoj.
