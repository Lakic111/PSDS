# Korak 6 — Dizajn AXI omotača i pakovanje u IP jezgro

> **Status:** IMPLEMENTIRANO I VERIFIKOVANO (2026-07-24), **POPRAVLJENO 2026-08-26/27**.
> Integracioni TB `src/vhdl/tb/ncc_accel_tb.vhd` daje zlatni peak `0x80000000 @ (32,14)`
> kroz AXI, a isti rezultat je 2026-08-27 potvrđen **na pravoj ploči** (Korak 9, faza 3).
> Ovaj dokument je merodavan opis dizajna omotača.
>
> ⚠️ **Dva protokolarna bug-a nađena tek na hardveru** (preživeli Korake 6, 7 i 8):
> **oba AXI slave-a su visila kad `W` stigne pre `AW`**, što AXI izričito dozvoljava.
> `axi_wready` se dizao u stanju `Idle` i nikad spuštao, pa je W beat bio prihvaćen a
> nigde zabeležen; `BVALID` se nikad ne izda i master visi zauvek.
>
> - S00 (AXI-Lite) — commit `720d162`
> - S01 (AXI-Full, burstovi) — commit `4bac595`, uz dodatnu zamku: adresni proces je
>   pre-inkrementirao na goli `WVALID` umesto na stvarni handshake
>
> Oba su imala **polovičnu popravku iz Koraka 8** (`wr_beat`), koja je rešila samo
> posledicu po podatke, ne i zastoj. Novi TB-ovi `ncc_accel_wfirst_tb` i
> `ncc_accel_s01_burst_wfirst_tb` pokrivaju sve redoslede i **dokazano padaju na starom
> RTL-u**. Popravke su smanjile površinu (1.910 → **1.887 LUT** po instanci) i
> poboljšale tajming. Puni zapis: `BUGS.md`.
>
> ⚠️ `ncc_accel_burst_tb` iz Koraka 7 je **kodirao bug** — nikad nije čitao `s01_wready`,
> pa je prolazio samo zato što je `wready` bio trajno visok. Popravljen (`cb8b67a`).
> **Izvor obrasca:** `06 Prilozi/Vezbe/Vezba-8-9-IP-Packaging.pdf` (Glava 6),
> pročitan u celosti (str. 229–302). Beleške: `01 Razvoj/Vezbe/(C) Vezba 08-09 - IP Packaging.md`.
> **Cilj:** spakovati `src/vhdl/ncc_core.vhd` (+ `ncc_pkg.vhd`) u AXI IP jezgro
> za 10 bodova, po obrascu iz vežbe.

## 1. Odluka o arhitekturi (potvrđena protiv PDF-a i ESL modela)

Vežba 08-09 razrađuje **isključivo** obrazac *sve-slave + interne memorije*
(primer `axi_matrix_multiply`): AXI-Lite slave za registre + AXI-Full slave za
interne memorije `A/B/C`. CPU upiše ulaze, jezgro računa, CPU pročita izlaz.
**Nijedan master interfejs se ne razrađuje**, a integracija u block design
(Korak 7) nije pokrivena.

**Zato NCC pakujemo istim obrascem** — kao čist slave sa internim memorijama.
Preslikavanje je skoro 1:1 i, ključno, **`ncc_core` se NE dira**:

| Matrix-multiply (vežba) | NCC IP | Veza na `ncc_core` (nepromenjen) |
|---|---|---|
| AXI-Lite slave: `n,m,p,cmd,status` | AXI-Lite slave: `IMG_W/H`, `TMP_W/H`, `CTRL`, `STATUS` | `img_w/h`, `tmp_w/h`, `start`, `busy/done` |
| Memorija `A` (ulaz) | **Interna slika** (dp_bram) | port B → `img_addr_o`/`img_data_i` |
| Memorija `B` (ulaz) | **Interni šablon** (dp_bram) | port B → `templ_addr_o`/`templ_data_i` |
| Memorija `C` (izlaz) | **Interni result_map** (dp_bram) | port B → `result_addr_o`/`data_o`/`wr_o` |
| `matrix_mult` modul | `ncc_core` | — (integralna slika `sat_mem` ostaje privatna) |

Ono što je u `ncc_core_real_tb.vhd` bilo modelovano kao „spoljna" sinhrona
memorija, u IP-u postaje **interna** dvoportna memorija. Timing se čuva
(interni dp_bram = 1-taktno čitanje → protočna MAC petlja netaknuta).

### Divergencija od ESL modela (svesna, dokumentovati na odbrani)

ESL model (`src/ncc.hpp/.cpp`) ima NCC kao **master** (`i_bram`) nad **deljenim**
BRAM-om; otud `REG_IMG_ADDR`/`REG_TMP_ADDR` = baze u tom BRAM-u. Slave/interni
obrazac znači:

- `REG_IMG_ADDR`/`REG_TMP_ADDR` **gube prvobitni smisao** → zadržavaju se kao
  **rezervisani** (upis dozvoljen, ignoriše se) da bi softverska mapa iz
  `common.hpp` ostala poravnata i da bi se master lako mogao dodati kasnije.
- **Korak 7** postaje: Zynq PS + **AXI DMA → NCC (S01 slave)** upiše segment/šablon
  i pročita rezultat. To je standardan i **jednostavniji** obrazac od deljenog
  BRAM-a sa 2 NCC-a (nema arbitracije / 2-port zida).
- Svaki NCC drži svoju kopiju segmenta (bandwidth trošak zanemarljiv naspram
  ~24 ms računanja).

## 2. Struktura IP-a `ncc_accel`

```
ncc_accel_v1_0 (top / strukturni wrapper)
├── ncc_accel_v1_0_S00_AXI   ← AXI-Lite slave kontroler (kontrolni registri)   [auto-gen + izmena]
├── ncc_accel_v1_0_S01_AXI   ← AXI-Full slave kontroler (pristup memorijama)   [auto-gen + izmena]
├── mem_subsystem            ← 3× dp_bram + adresni dekoder                     [ručno]
│    ├── img_mem   (dp_bram, 8-bit × 8192)   port A↔S01 / port B↔ncc_core
│    ├── templ_mem (dp_bram, 8-bit × 1024)   port A↔S01 / port B↔ncc_core
│    └── result_mem(dp_bram, 32-bit × 8192)  port A↔S01(read) / port B↔ncc_core(write)
├── ncc_core                 ← jezgro iz Koraka 3–5                             [NEPROMENJEN]
└── ncc_pkg                  ← tipovi/konstante                                 [NEPROMENJEN]
```

Novi ručni fajlovi: `dp_bram.vhd` (generički true-dual-port RAM, numeric_std,
potpuno sinhroni — poštuje BRAM-inference pravilo iz Koraka 3), `mem_subsystem.vhd`.
Auto-generisani pa ručno dopunjeni: `..._S00_AXI.vhd`, `..._S01_AXI.vhd`,
`ncc_accel_v1_0.vhd`.

Jedan takt za sve (AXI-Lite, AXI-Full, `ncc_core`) — PL clock 100 MHz
(`ncc_core` je za to i projektovan). `ncc_core.rst` (active-high) = `not aresetn`.

## 3. AXI-Lite slave (S00_AXI) — kontrolni registri

Bazna adresa se dodeljuje u Koraku 7 (Zynq mapa; ESL predlog `0x5000_0000`).
Broj registara u wizardu: **16** (pokriva `0x00`–`0x3C`).

| Offset | Registar | Smer | Opis / veza |
|---|---|---|---|
| 0x00 | IMG_W | RW | → `ncc_core.img_w` |
| 0x04 | IMG_H | RW | → `ncc_core.img_h` |
| 0x08 | TMP_W | RW | → `ncc_core.tmp_w` |
| 0x0C | TMP_H | RW | → `ncc_core.tmp_h` |
| 0x10 | IMG_ADDR | RW | **rezervisan** (ESL kompatibilnost, ignoriše se) |
| 0x14 | TMP_ADDR | RW | **rezervisan** |
| 0x30 | CTRL | W | bit0=1 → generiši 1-taktni `start` puls + obriši `done` |
| 0x34 | STATUS | R | bit0 = `done_sticky` (1=gotovo), bit1 = `busy` |

**Kontrolna logika (dodaje se u auto-gen AXI-Lite kontroler):**
- `IMG_W/H`, `TMP_W/H`: obični latch registri (auto-gen `slv_reg0..3`), žice na `ncc_core`.
- **`start` puls:** na detekciju upisa u `CTRL` sa bit0=1 → `start <= '1'` tačno 1 takt.
  (Nužno jer bi zadržan `start='1'` re-startovao jezgro pri povratku u `S_IDLE`.)
- **`done_sticky`:** `<= '0'` na `start`/reset, `<= '1'` na `ncc_core.done='1'`.
  (`ncc_core.done` je 1-taktni puls — vidi `ncc_core.vhd:257,467`.) Ovo je tačno
  ESL `hw_status` semantika.
- **STATUS read mux:** za adresu `0x34` vrati `(busy & done_sticky)` umesto `slv_reg13`.

## 4. AXI-Full slave (S01_AXI) — memorijska mapa

Data width 32. **Memory Size = 128 KB** (`C_S01_AXI_ADDR_WIDTH = 17`).
Tri regiona, dekodovanje na `araddr/awaddr(16 downto 15)`:

| Region   | Bitovi 16:15 | Byte opseg      | Sadržaj                | Širina × dubina |
| -------- | ------------ | --------------- | ---------------------- | --------------- |
| Slika    | 00           | 0x00000–0x07FFF | pikseli segmenta       | 8-bit × 8192    |
| Šablon   | 01           | 0x08000–0x0FFFF | pikseli šablona        | 8-bit × 1024    |
| Rezultat | 10           | 0x10000–0x17FFF | NCC² Q1.31 po poziciji | 32-bit × 8192   |

Indeks reči unutar regiona = `addr(14 downto 2)` (13-bit, do 8192).

**Jedan element po 32-bitnoj reči** (isti obrazac kao matrice `A/B` u vežbi,
`WIDTH=8`): CPU/DMA piše svaki piksel kao 32-bitnu reč (donjih 8 bita = piksel),
read-back nula-proširen na 32. Cena: 4× DMA saobraćaja za sliku (~32 KB umesto
8 KB za segment) — zanemarljivo naspram računanja; **`ncc_core` se ne dira**
(alternativa — pakovanje 4 piksela/reč — zahtevala bi promenu adresiranja u jezgru).
Rezultat je prirodno 32-bitni.

Auto-gen AXI-Full kontroler se dopunjava (kao u vežbi): portovi `mem_addr_o`,
`mem_data_o`, `mem_wr_o` + read-back `img_axi_data_i`, `templ_axi_data_i`,
`result_axi_data_i`; burst adresa/podatak se vežu na `mem_subsystem`.

## 5. Memorijski podsistem (`mem_subsystem`)

- **`img_mem`**: dp_bram 8×8192. Port A ↔ S01 (upis/čitanje CPU/DMA). Port B ↔
  `ncc_core.img_addr_o`/`img_data_i` (čitanje, 1-taktno).
- **`templ_mem`**: dp_bram 8×1024. Port A ↔ S01. Port B ↔ `ncc_core.templ_*`.
- **`result_mem`**: dp_bram 32×8192. Port A ↔ S01 (samo čitanje, CPU). Port B ↔
  `ncc_core.result_addr_o/data_o/wr_o` (upis).
- **Adresni dekoder**: `case addr(16 downto 15)` → `en`/`wr` po regionu; read mux
  bira `*_axi_data_i` za S01 čitanje (image/templ nula-prošireni na 32).

Nema konflikta portova: dok jezgro računa (`busy`), CPU čeka na `done` i ne
pristupa memorijama; DMA upis/čitanje se dešava pre `start` / posle `done`.
`sat_mem` ostaje potpuno privatna unutar `ncc_core`.

## 6. Verifikacija (testbench pre pakovanja)

`ncc_accel_tb` po obrascu `axi_matrix_mult_tb` (str. 284–292), TB glumi AXI master:
1. Reset AXI-Lite + AXI-Full (10 taktova).
2. AXI-Lite pojedinačni upisi: IMG_W=90, IMG_H=90, TMP_W=25, TMP_H=15.
3. AXI-Full **burst upis**: pikseli slike u region slike, pikseli šablona u region
   šablona (jedan piksel/reč). **Ponovo iskoristiti `tb/seg90.txt` + `tb/crnitop.txt`**
   iz Koraka 4 (isti realni podaci).
4. AXI-Lite upis CTRL=1 (start), pa CTRL=0.
5. Petlja: AXI-Lite čitanje STATUS dok bit0≠1.
6. AXI-Full **burst čitanje** regiona rezultata; naći maksimum.
   **Očekivano (zlatna vrednost iz Koraka 4): peak `0x80000000` @ (u=32, v=14).**

Ako se poklopi → omotač je transparentan (jezgro daje isti rezultat kroz AXI).
Opciono i sintetički 4×4/2×2 slučaj iz `ncc_core_tb` kroz isti AXI put.

## 7. Koraci pakovanja (Package IP wizard) — konkretne vrednosti

1. Nov Vivado projekat `ncc_accel`, part `xc7z010clg225-2`.
2. `Tools → Create and Package IP → Create a new AXI4 peripheral`.
3. Peripheral Details: Name `ncc_accel`, ver `1.0`, opis „NCC template-matching accelerator".
4. Add Interfaces:
   - `S00_AXI`: Lite, **Slave**, Data Width 32, **Number of Registers = 16**.
   - `S01_AXI`: Full, **Slave**, Data Width 32, **Memory Size = 131072** (128 KB).
5. Create Peripheral → **Edit IP**.
6. Dodati sorse: `ncc_pkg.vhd`, `ncc_core.vhd`, `dp_bram.vhd`, `mem_subsystem.vhd`
   (+ `utils_pkg` sa `log2c` ako zatreba za dp_bram generike).
7. Izmeniti auto-gen: `S00_AXI` (kontrolna logika §3), `S01_AXI` (mem interfejs §4),
   top wrapper (instancirati sve, povezati §2).
8. Pokrenuti `ncc_accel_tb` (§6) — mora proći pre pakovanja.
9. Package IP koraci:
   - Identification: Vendor, Categories `AXI_Peripheral` + (npr. `Image_Processing`).
   - Compatibility: **Zynq**.
   - File Groups: **„Merge changes from File Groups Wizard"** da uđu ručni fajlovi.
   - Customization Parameters: AXI parametri → Hidden; (opciono izložiti MAX dimenzije).
   - Review and Package: **uključiti „Create archive of IP"** (podrazumevano isključeno!).
10. Package IP → `.zip` + IP u katalogu. Provera: instancirati IP iz kataloga.

## 8. Resursni uticaj (procena)

Dodaje se uz postojećih 9 RAMB36 (Korak 5): `img_mem` (8×8192 ≈ 1–2 RAMB36),
`templ_mem` (8×1024, mali), `result_mem` (32×8192 ≈ 8 RAMB36) → ukupno grubo
**~18–19 RAMB36 (~30%)** na xc7z010 (60 RAMB36). Staje sa rezervom. Plus AXI
kontroleri (LUT/FF, red veličine par stotina). Ako zatreba, sužavanje `sat_t`
(IDEJE.md) i `result_mem` na realnu dubinu (≤4096) spušta BRAM.

## 9. Šta se NE dira

- **`ncc_core.vhd` i `ncc_pkg.vhd`** ostaju bit-identični (verifikovani, Koraci 4–5).
  Ako se ipak menjaju, oba testbencha iz Koraka 4 moraju ponovo proći.
- `src/` SystemC model — samo referenca.

## 10. Otvorene stavke / rizici

- **`utils_pkg`/`log2c`**: proveriti da li nam treba (za dp_bram generičke širine
  adrese) ili je jednostavnije fiksirati dubine. Verovatno mali helper.
- **Softverska mapa za Korak 9**: kontrola je sada na S00 bazi, podaci/rezultati na
  S01 bazi (dve bazne adrese) — različito od jedinstvene `ADDR_NCC` u `common.hpp`.
  Zabeležiti za bare-metal port.
- **`dp_bram` BRAM-inference**: sva čitanja/pisanja svake memorije u jednom
  sinhronom procesu (pouka iz Koraka 3) — inače LUT-RAM umesto BRAM.
- **AXI-Full burst granice**: proveriti da adresni dekoder ispravno inkrementira
  kroz region pri INCR burst-u (auto-gen logika to radi; samo povezati `mem_addr`).
