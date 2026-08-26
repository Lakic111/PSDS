# Gradi Vitis platformu iz XSA i bare-metal aplikaciju. Batch, bez GUI-a.
set REPO C:/Users/pc/Desktop/PSDS
set XSA  $REPO/src/vhdl/result/ncc_system/ncc_system_wrapper.xsa
set WS   $REPO/src/vitis/ws
set APP  ncc_app

if {![file exists $XSA]} { error "nema XSA: $XSA -- pusti run_impl.tcl" }
file mkdir $WS
setws $WS

# Platforma iz XSA, standalone domen na ps7_cortexa9_0.
if {[catch {platform create -name ncc_plat -hw $XSA -os standalone -proc ps7_cortexa9_0 -out $WS} e]} {
    puts "### platform create: $e (verovatno vec postoji, nastavljam)"
}
platform active ncc_plat
platform generate

if {[catch {app create -name $APP -platform ncc_plat -domain standalone_domain -template {Empty Application(C)}} e]} {
    puts "### app create: $e (verovatno vec postoji, nastavljam)"
}

# Izvori: dodajemo sve iz src/vitis/app
foreach f [glob $REPO/src/vitis/app/*.c $REPO/src/vitis/app/*.h] {
    file copy -force $f $WS/$APP/src/
}

app config -name $APP build-config release
app config -name $APP compiler-optimization {Optimize more (-O2)}
app build -name $APP

set ELF $WS/$APP/build/$APP.elf
if {![file exists $ELF]} { set ELF $WS/$APP/Release/$APP.elf }
if {![file exists $ELF]} { error "BUILD PAO: nema .elf" }
puts "@@@ BUILD OK: $ELF ([file size $ELF] B)"
