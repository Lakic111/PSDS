# Kreira Vivado projekat za ncc_core (Korak 3/4) sa svim izvorima i
# simulacionim testbench-om vec dodatim. Pokrenuti iz Vivado Tcl konzole:
#   source {C:/Users/pc/Desktop/PSDS/src/vhdl/script/create_project.tcl}
# ili iz komandne linije: vivado -mode batch -source create_project.tcl

set projName ncc_core
set scriptDir [file dirname [info script]]
set vhdlDir   [file normalize "$scriptDir/.."]
set resultDir [file normalize "$vhdlDir/result/$projName"]

create_project $projName $resultDir -part xc7z010clg225-2 -force

add_files -norecurse [list "$vhdlDir/ncc_pkg.vhd" "$vhdlDir/ncc_core.vhd"]
add_files -fileset sim_1 -norecurse "$vhdlDir/tb/ncc_core_tb.vhd"

set_property file_type {VHDL 2008} [get_files "$vhdlDir/ncc_pkg.vhd"]
set_property file_type {VHDL 2008} [get_files "$vhdlDir/ncc_core.vhd"]
set_property file_type {VHDL 2008} [get_files "$vhdlDir/tb/ncc_core_tb.vhd"]

set_property top ncc_core_tb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "*** Projekat kreiran: $resultDir ***"
puts "*** Pokreni simulaciju: launch_simulation (ili dugme u GUI-ju) ***"
