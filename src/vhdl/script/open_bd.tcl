# Otvara postojeci ncc_system projekat i odmah prikaze block design.
# Pokretanje (GUI):
#   vivado.bat -source src/vhdl/script/open_bd.tcl
# Ako projekat ne postoji, prvo: vivado.bat -mode batch -source src/vhdl/script/create_bd.tcl
set REPO [file normalize [file join [file dirname [info script]] ../../..]]
set XPR  [file join $REPO src/vhdl/result/ncc_system/ncc_system.xpr]

if {![file exists $XPR]} {
    error "Projekat ne postoji: $XPR\nPokreni prvo: vivado.bat -mode batch -source src/vhdl/script/create_bd.tcl"
}
open_project $XPR
open_bd_design [get_files ncc_system.bd]
puts "### block design ncc_system otvoren"
