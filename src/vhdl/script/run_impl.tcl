# ============================================================================
# Korak 8: puna sinteza + implementacija integrisanog sistema ncc_system_wrapper,
# sa kapijama koje hvataju tihe otkaze na koje smo vec naleteli.
#
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/run_impl.tcl
# Opcioni override lokacije projekta:
#   set NCC_PROJ_DIR C:/kratka/putanja  (PRE source-ovanja)
#
# ZASTO KRATKA PUTANJA: Vivado run folderi lako probiju Windows limit od 248 B
# (ERROR [Common 17-680]). `src/vhdl/result/ncc_system` je dovoljno kratko;
# gradnja iz duboke temp putanje nije.
# ============================================================================

if {![info exists NCC_PROJ_DIR]} {
    set NCC_PROJ_DIR [file normalize [file join [file dirname [info script]] ../result/ncc_system]]
}
set NCC_SKIP_RTL_CHECK 1
source [file join [file dirname [info script]] create_bd.tcl]

puts "@@@ ================ SINTEZA ================"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "@@@ synth_1: [get_property STATUS [get_runs synth_1]] / [get_property PROGRESS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "SINTEZA PALA -- videti ncc_system.runs/synth_1/runme.log"
}

# --- KAPIJA 1: OOC sinteza IP-a NE SME dati blackbox ------------------------
# Sa pogresnim userFileType (npr. `vhdlSource2008` bez crtice) Vivado tiho
# prestane da vidi .vhd fajlove, sintetise ncc_accel kao PRAZNU KUTIJU, synth_1
# prodje 100%, a padne tek implementacija sa DRC INBB-3. Ova kapija to hvata
# odmah. Videti BUGS.md.
set bb 0
set scanned 0
foreach f [glob -nocomplain $NCC_PROJ_DIR/ncc_system.runs/ncc_system_ncc*_synth_1/*.vds] {
    incr scanned
    set fh [open $f r]; set txt [read $fh]; close $fh
    if {[string match "*blackbox instance*ncc_accel*" $txt]} {
        puts "@@@ KAPIJA PALA: [file tail $f] sadrzi 'blackbox instance ... ncc_accel'"
        incr bb
    }
}
if {$scanned == 0} { error "KAPIJA: nije nadjen nijedan OOC log ncc_accel-a" }
if {$bb > 0} {
    error "IP sintetisan kao BLACKBOX -- pokreni src/vhdl/script/fix_ip_package.tcl"
}
puts "@@@ KAPIJA 1 OK: nema blackbox-a (pregledano $scanned OOC logova)"

puts "@@@ ================ IMPLEMENTACIJA ================"
launch_runs impl_1 -to_step {phys_opt_design (Post-Route)} -jobs 4
wait_on_run impl_1
puts "@@@ impl_1: [get_property STATUS [get_runs impl_1]] / [get_property PROGRESS [get_runs impl_1]]"
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "IMPLEMENTACIJA PALA -- videti ncc_system.runs/impl_1/runme.log"
}

open_run impl_1
puts "@@@ ============ TAKT ============"
report_clocks
puts "@@@ ============ RESURSI (Korak 8a) ============"
report_utilization
report_utilization -hierarchical -hierarchical_depth 2
puts "@@@ ============ TIMING (Korak 8b) ============"
report_timing_summary -delay_type max -max_paths 1
report_timing -delay_type max -max_paths 1 -nworst 1 -significant_digits 3

# --- KAPIJA 2: timing mora da zatvori ---------------------------------------
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -delay_type max]]
puts "@@@ WNS = $wns ns"
if {$wns < 0} {
    puts "@@@ UPOZORENJE: timing NE zatvara (WNS = $wns ns)"
} else {
    puts "@@@ KAPIJA 2 OK: timing zatvara (WNS = $wns ns)"
}
puts "@@@ GOTOVO"
