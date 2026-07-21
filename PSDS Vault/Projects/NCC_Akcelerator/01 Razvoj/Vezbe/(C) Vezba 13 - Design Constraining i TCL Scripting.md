# Vezba 13 — Design Constraining and TCL Scripting

Izvor: `06 Prilozi/Vezbe/Vezba-13-Design-Constraining-and-Tcl-Scripting.pdf` (poglavlja 8 i 9 skripte, ~str. 419-515)

## Šta ova vežba pokriva

Dve celine:
1. **TCL jezik + automatizacija Vivado toka** (poglavlje 8) — osnove TCL-a (set, expr, if/switch, while/for, proc, liste, asocijativni nizovi) i kako se ceo Vivado tok (kreiranje projekta → dodavanje fajlova → sinteza → implementacija → bitstream → kopiranje u release) piše kao jedna TCL skripta umesto ručnog klikanja kroz GUI.
2. **Analiza dizajna + tajming ograničenja** (poglavlje 9) — TCL komande za pretragu Vivado baze podataka (`get_cells/get_nets/get_ports/get_pins`, `get_property/set_property`), statička vremenska analiza (STA: setup/hold check, slack), i XDC ograničenja (`create_clock`, `set_input_delay/set_output_delay`, izuzeci: multicycle/false path/min-max delay, fizička ograničenja).

Ovo direktno pokriva **korak 10** (TCL skripta) i deo **koraka 5b/8b** (kritična putanja/Fmax — XDC constraints + STA izveštaj su alat kojim se to meri) iz bodovanja.

## Preporučena struktura direktorijuma projekta (iz vežbe, tabela 8.1)

```
<projekat>/
├── release/        ← finalni .bit/.xsa fajlovi za krajnjeg korisnika
├── result/         ← radni Vivado projekat (sve auto-generisano)
└── src/
    ├── c/          ← C fajlovi (HLS algoritam ili drajver IP-a)
    ├── script/      ← sve TCL skripte
    ├── vhdl/        ← RTL izvorni fajlovi
    ├── tb/          ← VHDL testbench (verifikacija)
    └── xdc/         ← XDC fajlovi sa ograničenjima
```

Direktno primenljivo na naš projekat: `NCC_Akcelerator/{release,result}` + `src/{vhdl,tb,xdc,script}`.

## Skeleton glavne TCL skripte (build.tcl) — po uzoru na primer iz vežbe

```tcl
# KORAK#1: Projekat
set projName    ncc_core
set resultDir    ../../result/$projName
set releaseDir   ../../release/$projName
file mkdir $resultDir
file mkdir $releaseDir

create_project $projName $resultDir -part xc7z020clg484-1 -force
# (zamena za realnu Zynq ploču - proveriti tačan part broj korišćene ploče)

# KORAK#2: Izvorni fajlovi
add_files -norecurse ../vhdl/ncc_pkg.vhd
add_files -norecurse ../vhdl/ncc_datapath.vhd
add_files -norecurse ../vhdl/ncc_controlpath.vhd
add_files -norecurse ../vhdl/ncc_core.vhd
add_files -norecurse ../vhdl/axi_ncc_core_v1_0_S00_AXI.vhd   ; # AXI-Lite kontrolni regovi
add_files -norecurse ../vhdl/axi_ncc_core_v1_0.vhd            ; # top wrapper

add_files -fileset constrs_1 ../xdc/ncc_core.xdc
update_compile_order -fileset sources_1

# KORAK#3: Sinteza
launch_runs synth_1
wait_on_run synth_1
puts "*** Sinteza zavrsena! ***"

# KORAK#4: Implementacija + bitstream
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
puts "*** Implementacija zavrsena! ***"

# KORAK#5: Kopiranje rezultata
file copy -force $resultDir/$projName.runs/impl_1/axi_ncc_core_v1_0.bit \
    $releaseDir/$projName.bit
```

**Napomena:** ovo je skeleton za samostalni IP (korak 6). Za korak 10 (paketovanje IP-a + block design + Zynq integracija + export .xsa) treba dodati:

```tcl
# Pakovanje IP-a (posle sinteze/verifikacije RTL-a)
ipx::package_project -root_dir ../../ip_repo/ncc_core -vendor user.org -library user -taxonomy /UserIP
ipx::save_core [ipx::current_core]

# Block design (Zynq PS + BRAM ctrl + DMA + 2x ncc_core)
create_bd_design "system"
startgroup
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1"}  [get_bd_cells processing_system7_0]
endgroup

create_bd_cell -type ip -vlnv user.org:user:ncc_core:1.0 ncc_core_0
create_bd_cell -type ip -vlnv user.org:user:ncc_core:1.0 ncc_core_1
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl bram_ctrl_0
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen blk_mem_gen_0
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma axi_dma_0

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Master "/processing_system7_0/M_AXI_GP0" Clk "Auto"} [get_bd_intf_pins ncc_core_0/S_AXI]
# ... (poveži preostale AXI interfejse istim automation rule-om)

save_bd_design
validate_bd_design

make_wrapper -files [get_files system.bd] -top
add_files -norecurse ./system_wrapper.vhd

# Sinteza + implementacija celog sistema
launch_runs synth_1
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# Export .xsa za Vitis
write_hw_platform -fixed -include_bit -force -file $releaseDir/system.xsa
```

(Ovaj drugi blok je nacrt — tačna imena portova/pinova AXI interfejsa treba proveriti nakon što IP wizard generiše `component.xml`, jer se automation rule oslanja na tačna imena `S_AXI`/`m_axi_*` iz paketovanog IP-a.)

## Timing constraints (XDC) — 100 MHz takt

Iz `ncc.cpp` (K_CYC kalibracija) pretpostavka je 100 MHz (10 ns period, `wait(ciklusi * 10, SC_NS)`). U XDC fajlu (`ncc_core.xdc`):

```tcl
create_clock -period 10.000 -name s00_axi_aclk -waveform {0.000 5.000} [get_ports s00_axi_aclk]
```

Za BRAM AXI master port (ako je zaseban klok domen — u našem slučaju isti takt, pa nije neophodno, ali ako se doda AXI DMA na drugom klok domenu treba i drugi `create_clock` + `set_false_path`/CDC handling).

Ako neki portovi (npr. debug/status LED) idu do stvarnih nožica ploče: `set_property PACKAGE_PIN ...` + `set_property IOSTANDARD LVCMOS33 ...` (proveriti tačan standard sa master XDC fajla ploče — obično se preuzima gotov "board XDC" i samo se preimenuju portovi).

## Statička vremenska analiza (STA) — ključni pojmovi za dokumentaciju (korak 5b/8b)

- **Setup check**: `Slack_setup = T_DRT - T_DAT` — mora biti ≥ 0 na svakoj putanji da bi dizajn radio na deklarisanoj frekvenciji. Ako Vivado prijavi negativan slack na 100 MHz constraint-u → **stvarni Fmax je niži od 100 MHz** i to treba prijaviti u dokumentaciji (korak 5b), a ne "popraviti" spuštanjem zahtevane frekvencije bez napomene.
- **Hold check**: `Slack_hold = T_DAT - T_DRT` — ne zavisi od periode takta, obično se automatski zadovoljava na FPGA (fixed silicon), retko problem osim kod ručnog rasporeda (CDC sinhronizatori).
- Izveštaj: `Report → Timing Summary Report`, sekcije `Design Timing Summary` (WNS = Worst Negative Slack — **ovo je ključan broj za izveštaj**: ako je WNS ≥ 0, sistem zadovoljava 100 MHz; ako je negativan, `Fmax = 1 / (perioda - WNS)` daje realno dostižnu frekvenciju).
- `report_timing_summary` TCL komanda generiše ovaj izveštaj i iz TCL skripte (korisno da build.tcl na kraju sam ispiše WNS u konzolu/log, umesto ručnog otvaranja GUI-ja).

```tcl
report_timing_summary -file $resultDir/timing_summary.rpt
```

## Korisne TCL komande za analizu/debug dizajna (poglavlje 9.1)

- `get_cells`, `get_nets`, `get_ports`, `get_pins` — selekcija objekata iz netliste (rade i `-hierarchical`, `-filter {...}`, `-of_objects [...]`).
- `report_property -all [get_cells X]` — sve osobine objekta (korisno za debug posle sinteze — npr. proveriti da li je `matrix_mult`/`ncc_core` blok mapiran kako se očekuje).
- `get_property`/`set_property` — čitanje/pisanje osobina (npr. `MARK_DEBUG 1` na signal pre sinteze da ostane vidljiv za ILA debug).

## Izuzeci vredni pažnje za NCC dizajn

- **Multicycle path** (`set_multicycle_path`): ako `solve_single_point` akumulacija (MAC petlja) traje više ciklusa po prirodi FSM-a, to se rešava kroz sam FSM dizajn (ne treba multicycle exception — FSM već čeka N ciklusa kroz stanja). Multicycle bi bio relevantan samo ako se neki deo datapath-a namerno "razvuče" preko više taktova radi timing closure-a (npr. deljenje/skaliranje NCC² rezultata u Q1.31).
- **False path**: ako postoji CDC (npr. AXI-Lite kontrolni registri na jednom klok domenu, DMA/BRAM na drugom) — malo verovatno u našem slučaju pošto je sve na istom PL taktu, ali proveriti kad se doda pravi Zynq PS GP port klok.

## Fizička ograničenja — relevantnost za nas

Skoro sva (I/O standard, PACKAGE_PIN, DRIVE, SLEW) se odnose na **top-level portove koji idu do fizičkih nožica ploče**. Kod nas, `ncc_core` IP nema direktne I/O portove ka ploči (sve ide preko AXI unutar PL-a) — ova ograničenja postaju relevantna tek na nivou **celog Zynq sistema** (npr. ako se dodaju debug LED-ovi ili UART), ne na nivou samog IP jezgra. Za sam IP jezgro dovoljna su timing ograničenja (`create_clock`).

## Mapiranje na korake iz bodovanja

- **Korak 5b/8b** (kritična putanja/Fmax): koristiti `report_timing_summary`, pratiti WNS, porediti sa 100 MHz pretpostavkom iz SystemC modela.
- **Korak 10** (TCL skripta, 10 bodova): `build.tcl` skeleton iznad (package IP → block design → synth → impl → `write_hw_platform` za .xsa) je direktan predložak.
