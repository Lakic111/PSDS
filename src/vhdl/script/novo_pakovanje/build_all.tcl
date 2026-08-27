# ============================================================================
# GLAVNA SKRIPTA -- ceo tok od izvora do isporuke, bez ijednog klika.
#
#   package IP -> block design -> sinteza -> implementacija -> bitstream -> XSA
#                                                                  -> release/
#
# Pokretanje (iz src/script/):
#   vivado.bat -mode batch -source build_all.tcl
#
# Opcije (postaviti PRE pokretanja, kroz -tclargs ili rucno u Tcl-u):
#   set NCC_SKIP_PACKAGE 1   preskoci pakovanje IP-a (koristi zateceni ip_repo)
#   set NCC_FCLK       100   trazeni PL takt u MHz (podrazumevano 95 -> 90,909)
#
# Struktura po Vezbi 13, tabela 8.1:
#   release/  finalni artefakti     result/  radni Vivado projekat (generisano)
#   ip_repo/  spakovan IP           src/{vhdl,tb,xdc,c,script}
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR ../..]]
set RELEASE    [file join $ROOT release]

file mkdir $RELEASE
file mkdir [file join $ROOT result]

set t_start [clock seconds]
puts "@@@ ======================================================"
puts "@@@ PSDS -- pun tok gradnje"
puts "@@@ koren: $ROOT"
puts "@@@ ======================================================"

# --- 1) pakovanje IP-a -----------------------------------------------------
# Preskace se samo ako se izricito trazi; podrazumevano se IP pravi iz izvora,
# jer je to jedini nacin da isporuka bude reproducibilna.
if {[info exists NCC_SKIP_PACKAGE] && $NCC_SKIP_PACKAGE} {
    puts "@@@ [1/3] pakovanje IP-a PRESKOCENO (NCC_SKIP_PACKAGE = 1)"
    if {![file exists [file join $ROOT ip_repo/ncc_accel_1_0/component.xml]]} {
        error "preskaces pakovanje, a ip_repo je prazan -- pusti bez NCC_SKIP_PACKAGE"
    }
} else {
    puts "@@@ [1/3] pakovanje IP-a ..."
    source [file join $SCRIPT_DIR package_ip.tcl]
    # package_ip.tcl zatvara svoj projekat; ovde krecemo cisti.
}

# --- 2) block design + sinteza + implementacija + bitstream + XSA ----------
# run_impl.tcl sam sourcuje create_bd.tcl i nosi cetiri kapije:
#   1 IP nije blackbox   2 timing zatvara   3 bitstream   4 XSA sadrzi .bit
puts "@@@ [2/3] block design, sinteza, implementacija, bitstream, XSA ..."
source [file join $SCRIPT_DIR run_impl.tcl]

# --- 3) kopiranje u release ------------------------------------------------
puts "@@@ [3/3] kopiranje u release/ ..."
set PROJ [file join $ROOT result/ncc_system]
set artefakti [list \
    [list [file join $PROJ ncc_system.runs/impl_1/ncc_system_wrapper.bit] ncc_system.bit] \
    [list [file join $PROJ ncc_system_wrapper.xsa]                        ncc_system.xsa] \
]

foreach a $artefakti {
    lassign $a izvor ime
    if {![file exists $izvor]} { error "RELEASE: nema $izvor" }
    file copy -force $izvor [file join $RELEASE $ime]
    puts "@@@   release/$ime ([file size $izvor] B)"
}

set dt [expr {[clock seconds] - $t_start}]
puts "@@@ ======================================================"
puts "@@@ GOTOVO za [expr {$dt/60}] min [expr {$dt%60}] s"
puts "@@@ Sledece: softver -- xsct src/script/build_app.tcl"
puts "@@@          pa na plocu -- xsct src/script/run_app.tcl"
puts "@@@ ======================================================"
