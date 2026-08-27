# ============================================================================
# Pakuje ncc_accel u AXI IP jezgro, iz izvora, bez ijednog klika.
#
# Pokretanje (iz src/script/):
#   vivado.bat -mode batch -source package_ip.tcl
#
# Izlaz: ../../ip_repo/ncc_accel_1_0/  (katalog IP-a, spreman za create_bd.tcl)
#
# ⚠️ NA KRAJU OBAVEZNO POZIVA fix_ip_package.tcl. Package IP wizard vraca dve
#    stvari na pogresne vrednosti i obe su TIHE:
#      1. tip fajla `vhdlSource` umesto `vhdlSource-2008` -- alat tada prestane
#         da prepoznaje izvore kao VHDL i sintetise IP kao PRAZNU KUTIJU, bez
#         ijedne greske; sinteza prodje 100%, pada tek implementacija;
#      2. C_S01_AXI_ADDR_WIDTH = 10 umesto 17 -- S01 dekodira 1 KB umesto 128 KB
#         i sva tri regiona (slika/sablon/rezultat) se preklapaju.
#    Videti BUGS.md u starom repou. Bez te popravke IP je neupotrebljiv.
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR ../..]]
set SRC        [file join $ROOT src/vhdl]
set IP_ROOT    [file join $ROOT ip_repo/ncc_accel_1_0]
set TMP_PROJ   [file join $ROOT result/_package_ip]

set PART       xc7z010clg400-1
set VENDOR     xilinx.com
set LIBRARY    user
set IP_NAME    ncc_accel
set IP_VER     1.0

# --- izvorni fajlovi, redosled je bitan za elaboraciju ---------------------
set VHDL_FILES [list \
    [file join $SRC ncc_pkg.vhd] \
    [file join $SRC dp_bram.vhd] \
    [file join $SRC mem_subsystem.vhd] \
    [file join $SRC ncc_core.vhd] \
    [file join $SRC ncc_accel_slave_lite_v1_0_S00_AXI.vhd] \
    [file join $SRC ncc_accel_slave_full_v1_0_S01_AXI.vhd] \
    [file join $SRC ncc_accel.vhd] \
]

foreach f $VHDL_FILES {
    if {![file exists $f]} { error "nema izvornog fajla: $f" }
}

# --- privremen projekat samo za pakovanje ---------------------------------
file delete -force $TMP_PROJ
file mkdir $TMP_PROJ
create_project package_ip $TMP_PROJ -part $PART -force

add_files -norecurse $VHDL_FILES
# VHDL-2008 je obavezan: ncc_core koristi `process (all)`.
set_property file_type {VHDL 2008} [get_files *.vhd]
set_property top ncc_accel [current_fileset]
update_compile_order -fileset sources_1

# --- kapija: RTL mora da elaborira pre pakovanja ---------------------------
# Pakovanje neispravnog RTL-a daje IP koji pukne tek u sistemskoj sintezi.
if {[catch {synth_design -rtl -top ncc_accel -part $PART} e]} {
    error "ELABORACIJA PALA -- ne pakujem neispravan RTL:\n$e"
}
puts "@@@ KAPIJA: RTL elaborira"
close_design

# --- pakovanje -------------------------------------------------------------
file delete -force $IP_ROOT
file mkdir $IP_ROOT

ipx::package_project -root_dir $IP_ROOT -vendor $VENDOR -library $LIBRARY \
                     -taxonomy /UserIP -import_files -force

set core [ipx::current_core]
set_property vendor              $VENDOR   $core
set_property library             $LIBRARY  $core
set_property name                $IP_NAME  $core
set_property version             $IP_VER   $core
set_property display_name        "NCC akcelerator"                       $core
set_property description         "Normalized Cross-Correlation, AXI-Lite kontrola + AXI-Full memorije" $core
set_property vendor_display_name "PSDS"    $core
set_property supported_families  {zynq Production} $core

ipx::create_xgui_files  $core
ipx::update_checksums   $core
ipx::save_core          $core
puts "@@@ IP spakovan: $IP_ROOT"

close_project

# --- OBAVEZNO: popravke posle wizarda --------------------------------------
# Bez ovoga IP je tiho neupotrebljiv (videti zaglavlje).
set NCC_IP_ROOT $IP_ROOT
source [file join $SCRIPT_DIR fix_ip_package.tcl]

# --- .zip arhiva IP-a ------------------------------------------------------
set ZIP [file join $IP_ROOT ${VENDOR}_${LIBRARY}_${IP_NAME}_${IP_VER}.zip]
if {[catch {
        ipx::open_ipxact_file [file join $IP_ROOT component.xml]
        ipx::archive_core $ZIP [ipx::current_core]
        ipx::unload_core [ipx::current_core]
    } e]} {
    puts "@@@ NAPOMENA: .zip arhiva nije napravljena ($e) -- katalog je ipak ispravan"
} else {
    puts "@@@ .zip arhiva: $ZIP ([file size $ZIP] B)"
}

# --- zavrsna provera -------------------------------------------------------
set XML [file join $IP_ROOT component.xml]
if {![file exists $XML]} { error "PAKOVANJE PALO: nema $XML" }
puts "@@@ PACKAGE_IP GOTOVO: $XML ([file size $XML] B)"
