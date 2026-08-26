# ============================================================================
# Korak 7 -- block design ncc_system: Zynq PS + 2x ncc_accel + AXI CDMA.
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/create_bd.tcl
# Skripta je idempotentna (-force) -- brise i pravi projekat od nule.
# Dizajn: PSDS Vault/.../01 Razvoj/(C) Korak 7 - Dizajn integracije (block design).md
# ============================================================================

set REPO      [file normalize [file join [file dirname [info script]] ../../..]]
# Opcioni override: `set NCC_PROJ_DIR <put>` pre `source`-ovanja ove skripte gradi
# projekat na drugom mestu (npr. da se ne sudara sa otvorenim GUI-em, ili za CI).
if {[info exists NCC_PROJ_DIR]} {
    set PROJ_DIR $NCC_PROJ_DIR
} else {
    set PROJ_DIR [file join $REPO src/vhdl/result/ncc_system]
}
set IP_REPO   [file join $REPO src/vhdl_NCC_IP/ip_repo]
set PART      xc7z010clg400-1
# ORIGINALNI Zybo -- POTVRDJENO 2026-08-26 (ploca je u rukama, ima VGA konektor;
# Z7-10 nema VGA nego dva HDMI-ja). PS_CLK 50 MHz, DDR3 MT41K128M16 JT-125, 512 MB.
# Do 2026-08-26 je ovde stajao zybo-z7-10:part0:1.2 kao nepotvrdjena pretpostavka;
# sve brojke Koraka 7 i 8 su merene sa TIM presetom -- part xc7z010clg400-1 je isti,
# ali PS preset nije, pa se tajming i FCLK moraju PONOVO potvrditi (skripta ih stampa).
#
# VERZIJA JE 2.0. Segment verzije u board_part je <file_version> iz board.xml, a NE ime
# direktorijuma i NE schema_version. Vivado 2025.2 nosi zybo/B.3 (file_version 1.0) i
# zybo/B.4 (file_version 2.0), pa je 2.0 upravo revizija ploce B.4 -- novija od dve.
# Provereno `get_board_parts`, koji je jedini merodavan izvor:
#   digilentinc.com:zybo:part0:1.0
#   digilentinc.com:zybo:part0:2.0
#   digilentinc.com:zybo-z7-10:part0:1.2
#   digilentinc.com:zybo-z7-20:part0:1.2
# (Pokusaj sa ...:part0:B.4 pada sa ERROR [Board 49-71] board_part definition not found.)
# Preseti B.3 i B.4 imaju IDENTICNE PS_CLK (50 MHz), DDR partno (MT41K128M16 JT-125),
# UART1 i sva cetiri DDR_BOARD_DELAY / DQS_TO_CLK_DELAY; razlika je samo u broju
# deklarisanih board interfejsa, sto nas ne dotice (koristimo samo FIXED_IO + DDR).
set BOARD     digilentinc.com:zybo:part0:2.0
set BD_NAME   ncc_system

puts "### repo    = $REPO"
puts "### part    = $PART"
puts "### board   = $BOARD"

# --- projekat ---------------------------------------------------------------
create_project $BD_NAME $PROJ_DIR -part $PART -force
set_property board_part      $BOARD   [current_project]
set_property target_language VHDL     [current_project]
set_property ip_repo_paths   $IP_REPO [current_project]
update_ip_catalog -rebuild

# IP kes ISKLJUCEN. Kes je nas vec jednom prevario: ncc0 i ncc1 su ista
# konfiguracija pa dele jednu OOC sintezu, i kad je ta jedna dala praznu kutiju,
# druga instanca je tiho prekopirala smece (videti BUGS.md). Cena iskljucenja je
# jedna dodatna sinteza IP-a; dobitak je da netlist uvek odgovara izvoru.
config_ip_cache -disable_cache

if {[get_ipdefs -quiet xilinx.com:user:ncc_accel:1.0] eq ""} {
    error "ncc_accel 1.0 nije u katalogu -- proveri ip_repo_paths: $IP_REPO"
}
puts "### ncc_accel u katalogu: OK"

# --- kapija: dve kopije izvora ne smeju da se raziđu ------------------------
# ncc_core.vhd i ncc_pkg.vhd postoje i u src/vhdl (izvori Koraka 3-5, na koje se
# poziva predata dokumentacija) i u ip_repo (ono sto sinteza stvarno koristi).
# Ako se raziđu, simulacija i sinteza vrte RAZLICIT RTL a niko ne primeti.
# Izmena mora u OBE; ova kapija to iznudjuje.
foreach f {ncc_core.vhd ncc_pkg.vhd} {
    set pa [file join $REPO src/vhdl $f]
    set pb [file join $IP_REPO ncc_accel_1_0/src $f]
    set fa [open $pa r]; set ca [read $fa]; close $fa
    set fb [open $pb r]; set cb [read $fb]; close $fb
    if {$ca ne $cb} {
        error "IZVORI SE RAZILAZE: $f\n  $pa\n  $pb\nKopiraj izmenu u obe (ip_repo je merodavan za sintezu)."
    }
}
puts "### izvori sinhronizovani: ncc_core.vhd, ncc_pkg.vhd"

# --- block design ----------------------------------------------------------
create_bd_design $BD_NAME

# Zynq PS: board preset daje tacan DDR/MIO/PS_CLK; FIXED_IO i DDR izlaze na pinove.
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
    -config {make_external "FIXED_IO, DDR" apply_board_preset "1" \
             Master "Disable" Slave "Disable"} \
    [get_bd_cells processing_system7_0]

# PL takt 100 MHz.
#
# S_AXI_HP0 SUZEN NA 32 BITA (Korak 8b). HP portovi su nativno 64-bitni jer su
# pravljeni za sirok DDR saobracaj -- ali kod nas je SVE ostalo 32-bitno (CDMA
# C_M_AXI_DATA_WIDTH=32, ncc S01, PS GP0). axi_interconnect postavlja sirinu
# krosbara prema najsirem portu, pa je zbog HP0 gradio 64-bitni krosbar i lepio
# konvertor sirine (`auto_ds`) na SVAKI 32-bitni port -- za konverziju koju
# nijedan blok ne trazi. Kritična putanja je isla bas kroz jedan takav konvertor
# (m00_couplers/auto_ds, 10,710 ns od cega 10,130 ns rutiranja).
#
# TAKT: trazeno 95 MHz -> PS PLL daje 1000/11 = 90,909 MHz.
# 100 MHz NE zatvara: izmereno WNS -0,233 ns sa konvertorima i -0,232 ns bez njih,
# tj. uklanjanje konvertora nije pomoglo timingu (donelo je samo povrsinu).
# Vezujuca putanja je NASA: state_reg -> img_mem/ADDRBWRADDR, tj. kombinaciono
# racunanje adrese (v+y)*img_w + (u+x) do adresnog ulaza BRAM-a, ~62% rutiranje.
# Fmax integrisanog sistema ~97,7 MHz. Odstupanje 90,909 od 100 MHz je 9,1%,
# rubrika Koraka 8e dozvoljava 20%.
# Ako se ikad zatrazi punih 100 MHz: sledeca poluga je INKREMENTALNO racunanje
# adrese u ncc_core (adresa u registru + korak, umesto mnozenja svaki takt) --
# izbacuje mnozac iz unutrasnje petlje. To je treci zahvat u verifikovano jezgro.
set_property -dict [list \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {95} \
    CONFIG.PCW_USE_M_AXI_GP0            {1}  \
    CONFIG.PCW_USE_S_AXI_HP0            {1}  \
    CONFIG.PCW_S_AXI_HP0_DATA_WIDTH     {32} \
] [get_bd_cells processing_system7_0]

# Provera da je preset stvarno primenjen (a ne Vivado default).
set ps [get_bd_cells processing_system7_0]
puts "### PS preset: PS_CLK=[get_property CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ $ps]\
 DDR=[get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps]\
 FCLK0=[get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ $ps]"

# Napomena: CRITICAL WARNING [PSU-1..4] o negativnom PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_*
# dolazi IZ Digilent board preseta (izmerene duzine vodova na ploci) -- ocekivano,
# ne popravlja se. Videti dizajn 7.3.

# --- reset -----------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 proc_sys_reset_0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] \
               [get_bd_pins proc_sys_reset_0/ext_reset_in]

# Takt na PS AXI portove odmah -- inace validate_bd_design javlja
# ERROR [BD 41-758] (M_AXI_GP0_ACLK / S_AXI_HP0_ACLK bez izvora takta).
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK] \
               [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]

# --- 2x ncc_accel ----------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:user:ncc_accel:1.0 ncc0
create_bd_cell -type ip -vlnv xilinx.com:user:ncc_accel:1.0 ncc1

# --- AXI Interconnect: 2 mastera (PS GP0 + CDMA) -> 6 slave-ova ------------
# Jedan interkonekt a ne dva: AXI slave interfejs moze biti povezan na SAMO
# jedan interkonekt, a ncc.S01 mora biti dostupan i PS-u i CDMA-u.
#
# ZASTO axi_interconnect a NE smartconnect: smartconnect uvek gradi pun krosbar sa
# entry/exit pipeline-om po svakom portu -> u konfiguraciji 2x6 je trosio 8673 LUT
# (65% celog budzeta) i 10609 FF, sto je diglo zauzece na 75.8% i oborilo timing
# (WNS -3.608 ns, rutiranje 6.048 ns u kritičnoj putanji).
# STRATEGY=1 (Minimize Area) daje deljenu magistralu sa arbitracijom umesto krosbara.
# Za nas saobracaj je to dovoljno: masteri se serijalizuju u softveru (CPU ceka
# XAxiCdma_IsBusy), a ~146 KB po polju = ~366 us naspram ~48 ms racunanja.
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_interconnect_0
set_property -dict [list \
    CONFIG.NUM_SI   {2} \
    CONFIG.NUM_MI   {6} \
    CONFIG.STRATEGY {1} \
] [get_bd_cells axi_interconnect_0]
puts "### interkonekt: axi_interconnect 2.1, NUM_SI=2 NUM_MI=6 STRATEGY=[get_property CONFIG.STRATEGY [get_bd_cells axi_interconnect_0]] (1=Minimize Area)"

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] \
                    [get_bd_intf_pins axi_interconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M00_AXI] \
                    [get_bd_intf_pins ncc0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M01_AXI] \
                    [get_bd_intf_pins ncc0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M02_AXI] \
                    [get_bd_intf_pins ncc1/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M03_AXI] \
                    [get_bd_intf_pins ncc1/S01_AXI]

# --- AXI CDMA (mem-na-mem): podatkovni put DDR <-> ncc.S01 -----------------
# Simple mode (bez scatter-gather), bez DRE (svi pristupi su 4B-poravnati).
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_cdma:4.1 axi_cdma_0
set_property -dict [list \
    CONFIG.C_INCLUDE_SG          {0}   \
    CONFIG.C_INCLUDE_DRE         {0}   \
    CONFIG.C_M_AXI_DATA_WIDTH    {32}  \
    CONFIG.C_M_AXI_MAX_BURST_LEN {256} \
] [get_bd_cells axi_cdma_0]

puts "### CDMA config: SG=[get_property CONFIG.C_INCLUDE_SG [get_bd_cells axi_cdma_0]]\
 DRE=[get_property CONFIG.C_INCLUDE_DRE [get_bd_cells axi_cdma_0]]\
 DW=[get_property CONFIG.C_M_AXI_DATA_WIDTH [get_bd_cells axi_cdma_0]]\
 BURST=[get_property CONFIG.C_M_AXI_MAX_BURST_LEN [get_bd_cells axi_cdma_0]]"

# CDMA kontrolni registri = 5. slave; CDMA master = 2. master; DDR = 6. slave.
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M04_AXI] \
                    [get_bd_intf_pins axi_cdma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins axi_cdma_0/M_AXI] \
                    [get_bd_intf_pins axi_interconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_0/M05_AXI] \
                    [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

# --- jedan takt, jedan reset na sve ----------------------------------------
# (PS M_AXI_GP0_ACLK i S_AXI_HP0_ACLK su vezani gore, u sekciji reseta.)
set CLK  [get_bd_pins processing_system7_0/FCLK_CLK0]
set RSTN [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

# axi_interconnect (za razliku od smartconnect-a) ima ACLK/ARESETN za jezgro PLUS
# poseban par po SVAKOM portu: S00/S01 i M00..M05.
set ic_clks {}
set ic_rsts {}
foreach p {S00 S01 M00 M01 M02 M03 M04 M05} {
    lappend ic_clks [get_bd_pins axi_interconnect_0/${p}_ACLK]
    lappend ic_rsts [get_bd_pins axi_interconnect_0/${p}_ARESETN]
}

connect_bd_net $CLK \
    [get_bd_pins axi_interconnect_0/ACLK] {*}$ic_clks \
    [get_bd_pins ncc0/s00_axi_aclk] [get_bd_pins ncc0/s01_axi_aclk] \
    [get_bd_pins ncc1/s00_axi_aclk] [get_bd_pins ncc1/s01_axi_aclk] \
    [get_bd_pins axi_cdma_0/m_axi_aclk] [get_bd_pins axi_cdma_0/s_axi_lite_aclk]

# Jezgro interkonekta ide na interconnect_aresetn (konvencija), portovi na peripheral_aresetn.
connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins axi_interconnect_0/ARESETN]

connect_bd_net $RSTN {*}$ic_rsts \
    [get_bd_pins ncc0/s00_axi_aresetn] [get_bd_pins ncc0/s01_axi_aresetn] \
    [get_bd_pins ncc1/s00_axi_aresetn] [get_bd_pins ncc1/s01_axi_aresetn] \
    [get_bd_pins axi_cdma_0/s_axi_lite_aresetn]

# --- fiksna adresna mapa (PS master) --------------------------------------
# Poklapa se sa ESL common.hpp: ADDR_NCC=0x50000000, ADDR_NCC1=0x51000000.
# S00 opseg je 4K (Vivado minimum za AXI segment); IP dekodira samo donjih 6 bita.
set PSDATA [get_bd_addr_spaces processing_system7_0/Data]
assign_bd_address -offset 0x50000000 -range 4K   -target_address_space $PSDATA \
    [get_bd_addr_segs ncc0/S00_AXI/S00_AXI_reg] -force
assign_bd_address -offset 0x50020000 -range 128K -target_address_space $PSDATA \
    [get_bd_addr_segs ncc0/S01_AXI/S01_AXI_mem] -force
assign_bd_address -offset 0x51000000 -range 4K   -target_address_space $PSDATA \
    [get_bd_addr_segs ncc1/S00_AXI/S00_AXI_reg] -force
assign_bd_address -offset 0x51020000 -range 128K -target_address_space $PSDATA \
    [get_bd_addr_segs ncc1/S01_AXI/S01_AXI_mem] -force
assign_bd_address -offset 0x60000000 -range 64K  -target_address_space $PSDATA \
    [get_bd_addr_segs axi_cdma_0/S_AXI_LITE/Reg] -force

# --- adresna mapa: CDMA master --------------------------------------------
# CDMA vidi DDR (izvor/odrediste) i memorije oba NCC-a. NE vidi kontrolne
# registre -- ne treba mu, a suzavanje mape smanjuje sansu za slucajan upis.
# DDR opseg se NE kuca: dolazi iz PS board preseta (1 G Z7-10 / 512 M Zybo).
# VAZNO: svi assign-ovi idu PRE svih exclude-ova.
set CDMADATA [get_bd_addr_spaces axi_cdma_0/Data]
set DDRSEG   [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]
puts "### DDR segment: $DDRSEG (range [get_property RANGE $DDRSEG])"
assign_bd_address -target_address_space $CDMADATA $DDRSEG -force
assign_bd_address -offset 0x50020000 -range 128K -target_address_space $CDMADATA \
    [get_bd_addr_segs ncc0/S01_AXI/S01_AXI_mem] -force
assign_bd_address -offset 0x51020000 -range 128K -target_address_space $CDMADATA \
    [get_bd_addr_segs ncc1/S01_AXI/S01_AXI_mem] -force

# --- exclude-ovi (posle svih assign-ova) ----------------------------------
# PS ne rutira ka svom DDR-u kroz PL -- ima direktan put kroz PS.
if {[catch {exclude_bd_addr_seg -target_address_space $PSDATA $DDRSEG} e]} {
    puts "### NOTE: PS->DDR exclude: $e"
}
foreach seg {ncc0/S00_AXI/S00_AXI_reg ncc1/S00_AXI/S00_AXI_reg axi_cdma_0/S_AXI_LITE/Reg} {
    if {[catch {exclude_bd_addr_seg -target_address_space $CDMADATA \
                    [get_bd_addr_segs $seg]} e]} {
        puts "### NOTE: CDMA->$seg exclude: $e"
    }
}

puts "### adresna mapa (PS master):"
foreach s [get_bd_addr_segs -of_objects $PSDATA] {
    puts [format "###   %-56s %s  %s" $s \
        [get_property OFFSET $s] [get_property RANGE $s]]
}
puts "### adresna mapa (CDMA master):"
foreach s [get_bd_addr_segs -of_objects $CDMADATA] {
    puts [format "###   %-56s %s  %s" $s \
        [get_property OFFSET $s] [get_property RANGE $s]]
}

# --- validacija ------------------------------------------------------------
save_bd_design
validate_bd_design
puts "### TASK 7 OK: ceo BD (PS + reset + 2x ncc_accel + AXI Interconnect + CDMA) validiran"

# --- wrapper + top ---------------------------------------------------------
set BD_FILE [get_files ${BD_NAME}.bd]
generate_target all $BD_FILE
make_wrapper -files $BD_FILE -top -import
set_property top ${BD_NAME}_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "### top modul: [get_property top [current_fileset]]"

# Implementaciona strategija: BEZ phys_opt timing NE zatvara. Merenje (Korak 8b):
# standardna strategija dala WNS -0,714 ns, ova -0,233 ns na istom RTL-u -- dakle
# phys_opt donosi 0,481 ns, vise nego drugi RTL presek. Deo je build ugovora, ne
# opcija: Korak 10 mora ovo da ponovi da bi dizajn zatvorio.
set_property strategy Performance_ExplorePostRoutePhysOpt      [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true             [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true  [get_runs impl_1]
puts "### impl strategija: [get_property strategy [get_runs impl_1]]"

# Elaboracija: uhvati sintaksne/hijerarhijske greske bez pune sinteze.
# Preskace se ako sledi puna sinteza (`set NCC_SKIP_RTL_CHECK 1` pre source-ovanja).
if {![info exists NCC_SKIP_RTL_CHECK]} {
    synth_design -rtl -name rtl_check -top ${BD_NAME}_wrapper
    puts "### TASK 8 OK: wrapper generisan, RTL elaboracija prosla"
} else {
    puts "### RTL elaboracija preskocena (NCC_SKIP_RTL_CHECK)"
}
