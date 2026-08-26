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

# Vitis pamti projekte i van radnog direktorijuma, pa brisanje ws-a nije dovoljno:
# `app create` ume da javi "project with given name already exists". Zato prvo
# pokusamo da uklonimo zatecenu aplikaciju, pa tek onda pravimo novu.
catch {app remove -name $APP}
if {[catch {app create -name $APP -platform ncc_plat -domain standalone_domain \
                       -template {Empty Application(C)}} e]} {
    puts "### app create: $e"
    # Ako ni posle `app remove` ne moze da je napravi, aplikacija zaista postoji i
    # koristimo je -- ali to mora biti VIDLJIVO, ne progutano.
    if {[lsearch -exact [app list] $APP] < 0} {
        error "APP NE POSTOJI a create je pao: $e"
    }
    puts "### koristim zatecenu aplikaciju $APP"
}

# Izvori: dodajemo sve iz src/vitis/app
foreach f [glob $REPO/src/vitis/app/*.c $REPO/src/vitis/app/*.h] {
    file copy -force $f $WS/$APP/src/
}

if {[catch {app config -name $APP build-config release} e]} {
    puts "### build-config release nije dostupan ($e) -- ostajem na podrazumevanom"
}
catch {app config -name $APP compiler-optimization {Optimize more (-O2)}}
app build -name $APP

set ELF ""
foreach cand [list $WS/$APP/build/$APP.elf $WS/$APP/Release/$APP.elf \
                   $WS/$APP/Debug/$APP.elf] {
    if {[file exists $cand]} { set ELF $cand; break }
}
if {$ELF eq ""} {
    puts "### trazeno na:"
    foreach cand [glob -nocomplain $WS/$APP/*] { puts "###   $cand" }
    error "BUILD PAO: nema .elf"
}
puts "@@@ BUILD OK: $ELF ([file size $ELF] B)"
