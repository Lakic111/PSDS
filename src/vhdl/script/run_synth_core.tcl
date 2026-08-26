# Samostalna (out-of-context) sinteza + implementacija golog ncc_core.
# Daje par metriku za Korak 5 na aktuelnom partu, nezavisno od integrisanog sistema.
#
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/run_synth_core.tcl
#
# Period takta je parametar (podrazumevano 10,0 ns = 100 MHz):
#   vivado.bat -mode batch -source src/vhdl/script/run_synth_core.tcl -tclargs 11.0
#
# NAPOMENE (prve tri iz code review-a Koraka 8, cetvrta iz Koraka 8 Task 5):
#  1) Ograničenje takta se cita PRE synth_design (ncc_core_ooc.xdc). Ranije je
#     `create_clock` isao POSLE sinteze, pa se jezgro sintetisalo neograniceno a
#     WNS meren nad netlistom od koga 100 MHz nikad nije ni trazeno.
#  2) `-mode out_of_context` -- bez toga se svih 118 portova mapira na IOB-ove,
#     a paket ih ima 100 (clg400) odnosno 54 (clg225); procjena rutiranja se onda
#     pravi nad nemogucim razmestajem.
#  3) Izvor je ip_repo (merodavna kopija koju sinteza stvarno koristi).
#  4) MERODAVNE su post-route brojke, ne post-sintezne. Uz to, slack se NE SME
#     aritmeticki prevoditi izmedju ogranicenja takta -- alat optimizuje DO cilja
#     i staje kad ga ispuni, pa je putanja na labavijem ogranicenju duza. Fmax se
#     navodi na osnovu merenja na ogranicenju koje se tvrdi. Videti BUGS.md.

set REPO [file normalize [file join [file dirname [info script]] ../../..]]
set PART xc7z010clg400-1
set IP   [file join $REPO src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0]

# Period: prvi -tclargs argument, pa promenljiva NCC_PERIOD, pa podrazumevano 10,0.
# `argv` ne postoji ako je Vivado pokrenut bez -tclargs, pa se prvo proverava
# postojanje -- inace `llength $argv` pada sa "can't read argv".
if {[info exists argv] && [llength $argv] > 0} {
    set NCC_PERIOD [lindex $argv 0]
} elseif {![info exists NCC_PERIOD]} {
    set NCC_PERIOD 10.0
}
puts "### period takta = $NCC_PERIOD ns ([format %.3f [expr {1000.0/$NCC_PERIOD}]] MHz)"

read_vhdl -vhdl2008 [list \
    [file join $IP src/ncc_pkg.vhd] \
    [file join $IP src/ncc_core.vhd] ]
read_xdc [file join $REPO src/vhdl/script/ncc_core_ooc.xdc]

synth_design -mode out_of_context -top ncc_core -part $PART
puts "### ==== POST-SYNTH (informativno) ===="
report_timing_summary -delay_type max -max_paths 1

opt_design
place_design
phys_opt_design
route_design
phys_opt_design

puts "### ==== POST-ROUTE (merodavno za Korak 5b) ===="
report_timing_summary -delay_type max -max_paths 1
report_timing -delay_type max -max_paths 1 -nworst 1 -significant_digits 3

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -delay_type max]]
puts "### WNS @ ${NCC_PERIOD} ns = $wns ns"
if {$wns >= 0} {
    puts "### Fmax na ovom ogranicenju = [format %.2f [expr {1000.0/($NCC_PERIOD-$wns)}]] MHz"
    puts "### timing ZATVARA"
} else {
    puts "### timing NE ZATVARA na ${NCC_PERIOD} ns (manjak [expr {-$wns}] ns)"
}
puts "### NAPOMENA: ovaj Fmax vazi za ogranicenje od ${NCC_PERIOD} ns. Za drugo"
puts "### ogranicenje pokreni ponovo -- slack se ne prevodi aritmeticki."

puts "### ==== RESURSI (Korak 5a) ===="
report_utilization
puts "### GOTOVO"
