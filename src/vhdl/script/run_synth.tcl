open_project [file normalize "[file dirname [info script]]/../result/ncc_core/ncc_core.xpr"]
set_property top ncc_core [current_fileset]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "*** SINTEZA ZAVRSENA ***"
open_run synth_1 -name synth_1
report_utilization -file [file normalize "[file dirname [info script]]/../result/ncc_core/utilization.rpt"]
