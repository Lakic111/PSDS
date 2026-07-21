# Vezba 1 — Vivado: osnove alata

Izvor: `06 Prilozi/Vezbe/Vezba-1-Vivado-alat-za-projektovanje-i-verifikaciju-FPGA-baziranih-sistema.pdf`

## Šta ova vežba pokriva

Kompletan tok rada u Vivado Design Suite (2016.2) na trivijalnom primeru (dvoulazno
I kolo): kreiranje RTL projekta, dodavanje VHDL dizajn/testbenč/constraints fajlova,
funkcionalna simulacija, sinteza, implementacija, generisanje bitstream-a, i
programiranje/testiranje na ZedBoard (Zynq-7000, `xc7z020clg484-1`) razvojnoj ploči.
Ovo je osnovni skelet toka koji ćemo ponoviti (uz mnogo veću složenost) za
NCC_Akcelerator.

## Konkretni koraci (za primenu na NCC_Akcelerator projekat)

1. **Kreiranje projekta:** `Create New Project` → ime bez razmaka u putanji (npr.
   `ncc_core`) → tip **RTL Project** (ne Post-synthesis, ne I/O Planning) → ne
   čekirati "Do not specify sources at this time" (želimo odmah da dodajemo fajlove).
2. **Add Sources** korak čarobnjaka — može se preskočiti (Next) i uraditi kasnije
   preko komande `Add Sources` u `Project Manager` grupi.
3. **Add Existing IP** — za sada prazno (nemamo gotova IP jezgra); kasnije (Vezba
   8-9) ovde ide naš spakovan `ncc_core` IP kad ga budemo dodavali u block design.
4. **Default Part** — **kartica Boards**, izabrati konkretan razvojni sistem (u
   vežbi: ZedBoard). Ako ciljna ploča iz kursa nije ZedBoard, treba proveriti tačan
   part/board u uputstvu za predmet PEUSN i ovde upisati taj part broj (npr.
   `xc7z020clg484-1` je ZedBoard part).
5. **Dodavanje VHDL izvornog fajla:** `Add Sources` → `Add or create design
   sources` → `Create File` → File type VHDL, ime fajla (npr. `ncc_core`) → u
   `Define Module` prozoru definisati port mapu (ime, smer `in`/`out`, i za
   magistrale čekirati `Bus` + upisati MSB/LSB). **Ovo je mesto gde se unosi
   interfejs iz `common.hpp` registarske mape** — portovi za AXI-Lite (adresa,
   podaci, we/re) i BRAM master port.
6. **Editovanje entiteta:** arhitekturno telo se mora ručno popuniti — Vivado samo
   generiše praznu `entity`/`architecture` deklaraciju iz port mape. `Ctrl+S`
   obavezno posle svake izmene da bi alat registrovao promenu.
7. **Testbench fajl:** `Add Sources` → `Add or create simulation sources` →
   `Create File` → konvencija imenovanja: `<entitet>_tb` (npr. `ncc_core_tb`).
   Testbench NEMA portove (prazna port mapa u `Define Module`). Isti testbench
   fajl se koristi za SVE nivoe simulacije (behavioral, post-synthesis,
   post-implementation) — ne treba pisati poseban testbench za svaki nivo.
   Instanciranje DUT-a u testbenču: `DUT: entity work.<entitet>(<arhitektura>)
   port map (...)`.
8. **Funkcionalna (behavioralna) simulacija:** `Run Simulation` → `Run Behavioral
   Simulation`. Podrazumevano vreme simulacije 1000 ns — menja se u `Simulation
   Settings` → polje `xsim.simulate.runtime`. **Za NCC ovo vreme treba znatno
   povećati** (naš SystemC model pokazuje da pun NCC poziv troši ~10M+ ciklusa ×
   10 ns ≈ >100 ms simuliranog vremena — u xsim terminima to je ogroman broj ns,
   proveriti da runtime pokriva bar jedan pun ciklus obrade).
9. **Constraints fajl (XDC):** `Add Sources` → `Add or create constraints` →
   `Create File`, tip **XDC**. Dve vrste ograničenja:
   - **Vremenska** (min. učestanost klok signala) — za NCC_Akcelerator ovo je
     KLJUČNO za korak 5b/8b bodovanja (kritična putanja / max frekvencija);
     bez ovoga se ne dobija smislen timing izveštaj.
   - **Prostorna** (`set_property PACKAGE_PIN <pin> [get_ports <port>]` +
     `set_property IOSTANDARD <standard> [get_ports <port>]`) — mapiranje
     portova na fizičke pinove ploče (prekidači/LED-ovi u primeru; za nas —
     GPIO/AXI signali ka Zynq PS ako testiramo van block design-a, ili se ovo
     uglavnom preskače kad je IP unutar block design-a jer PS radi mapiranje).
10. **Sinteza:** `Run Synthesis` (Synthesis grupa). Rezultat: gate-level netlist.
    Nakon završetka — proveriti `Reports` tab (`Vivado Synthesis Report`,
    `Utilization Report`) i `Project Summary` → Synthesis tab → "No errors or
    warnings". **Ovo je prvi trenutak da se vidi realno zauzeće resursa** (korak
    5a bodovanja, "Post-Synthesis" utilization).
11. **Implementacija:** `Run Implementation` (translacija + mapiranje +
    raspoređivanje/povezivanje u jednom koraku). Nakon završetka proveriti
    `Utilization – Post-Implementation` i `Timing` panel (`Worst Negative Slack`,
    itd.) u `Project Summary`.
12. **Bitstream:** `Program and Debug` grupa → `Generate Bitstream`.
13. **Programiranje ploče:** `Open Hardware Manager` → `Open Target` → `Open New
    Target` → `Local Server` (ploča na istom računaru preko USB/JTAG) → alat sam
    detektuje uređaje na JTAG lancu (u primeru: `arm_dap_0` ARM procesor +
    `xc7z20_1` FPGA logika — **ovo potvrđuje da je ciljna arhitektura Zynq, PS+PL
    na istom JTAG lancu**, tačno kao u našoj adresnoj mapi). Klik desnim na FPGA
    uređaj → `Program Device...` → izabrati `.bit` fajl → `Program`.
14. **Hardversko testiranje:** posle programiranja, testira se fizičkim ulazima
    (prekidači/dugmad) i posmatranjem izlaza (LED). Za NCC_Akcelerator ovaj korak
    se u praksi radi preko **Vitis bare-metal aplikacije** (korak 9 bodovanja), ne
    ručnim prekidačima — ali princip veze (JTAG, Hardware Manager, Program
    Device) ostaje isti i za inicijalno programiranje PL dela pre nego što PS
    boot-uje.

## Bitne stvari / zamke na koje paziti

- **Putanja projekta ne sme sadržati razmake** (`space` karaktere) — bitno jer je
  trenutni Windows folder `C:\Users\pc\Desktop\PSDS` bez razmaka, OK je, ali paziti
  ako se projekat pravi dublje u nekom folderu sa razmakom u imenu.
- Svaki fajl (VHDL, testbench, XDC) mora se **eksplicitno snimiti (Ctrl+S)** da bi
  Vivado registrovao izmenu — lako se zaboravi posle copy-paste koda.
- **Tačnost raste, brzina opada** kroz 5 nivoa simulacije: Behavioral (najbrža,
  nulta kašnjenja) → Post-Synthesis Functional → Post-Synthesis Timing →
  Post-Implementation Functional → **Post-Implementation Timing** (najsporija,
  najtačnija — realno ponašanje na FPGA-u). Za NCC (skup proračun) treba planirati
  da post-implementation timing simulacija može trajati 10-100× duže od
  behavioralne — ne pokretati je nasumično na punom 90×90/30×30 slučaju bez
  potrebe.
- **Statička vremenska analiza (STA)** je preporučeni način provere brzine rada za
  sinhroni sekvencijalni dizajn (naš slučaj) — **brža je i dovoljna** naspram pune
  vremenske simulacije za potvrdu da dizajn zadovoljava traženu frekvenciju.
  Vremenska simulacija ostaje neophodna samo za proveru glič-ova (posebno ako ima
  lečeva — kod nas verovatno nema, projektujemo sinhrono).
- Redosled generisanih izveštaja (`Reports` tab) prati redosled koraka — koristiti
  ih direktno za dokumentaciju u koraku 5/8 bodovanja, ne prepisivati ručno.
- Local Server (JTAG preko USB na isti računar) vs Remote Server (ploča na mreži)
  — bitno znati koju opciju izabrati u laboratoriji/kod kuće.

## Mapiranje na korake iz bodovanja (06 Prilozi/Bodovanje projekta.pdf)

- **Korak 3** (RTL modeling) — tačke 5-8 iznad (kreiranje VHDL fajla, definisanje
  entiteta/arhitekture, port mapa = interfejs iz koraka 2c).
- **Korak 4** (simulacija/verifikacija) — tačke 7-8 (testbench + behavioralna
  simulacija); kasnije i post-synthesis/post-implementation simulacije kao dodatna
  provera.
- **Korak 5** (analiza posle sinteze/implementacije) — tačke 10-11 (utilization
  reports, timing summary/STA) — ovo su direktno resursi i kritična putanja/Fmax
  traženi u 5a/5b.
- **Korak 9** (bitstream + testiranje na ploči) — tačke 12-14, uz napomenu da će
  se stvarno testiranje raditi kroz Vitis bare-metal aplikaciju umesto ručnih
  prekidača.
- **Korak 10** (TCL automatizacija) — sve navedene GUI akcije imaju svoj Tcl
  ekvivalent koji se automatski ispisuje u `Tcl Console` tokom rada — to je
  osnova za TCL skriptu iz koraka 10 (videti Vezbu 13).
