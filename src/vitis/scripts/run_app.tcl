# Programira PL, inicijalizuje PS, spusta .elf i pusta ga.
set REPO C:/Users/pc/Desktop/PSDS
set WS   $REPO/src/vitis/ws
set APP  ncc_app
set BIT  $REPO/src/vhdl/result/ncc_system/ncc_system.runs/impl_1/ncc_system_wrapper.bit

set ELF $WS/$APP/build/$APP.elf
if {![file exists $ELF]} { set ELF $WS/$APP/Release/$APP.elf }
if {![file exists $ELF]} { error "nema .elf -- pusti build_app.tcl" }

connect
targets -set -filter {name =~ "xc7z010"}
fpga -file $BIT
targets -set -filter {name =~ "*Cortex-A9 MPCore #0*"}
rst -processor
# ps7_init.tcl dolazi iz platforme; inicijalizuje DDR i takt.
source $WS/ncc_plat/hw/ps7_init.tcl
ps7_init
ps7_post_config
dow $ELF
con
puts "@@@ POKRENUT -- prati UART na 115200 8N1"
