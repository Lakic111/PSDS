# ============================================================================
# Post-package popravke IP-a ncc_accel. MORA se pokrenuti posle svakog Package IP-a,
# jer wizard vraca oba problema ispod.
#
# Pokretanje (iz korena repoa):
#   vivado.bat -mode batch -source src/vhdl/script/fix_ip_package.tcl
# Idempotentno. Zamenjuje stariji fix_ip_vhdl2008.tcl (koji je pokrivao samo #1).
#
# --- POPRAVKA 1: VHDL-2008 tip fajlova ---
# `ncc_core.vhd:237` koristi `process (all)` (VHDL-2008). Wizard pakuje sve kao
# `vhdlSource` (VHDL-93), pa IP NE MOZE da se sintetise:
#   ERROR [Synth 8-2757] this construct is only supported in VHDL 1076-2008
#
# ZAMKA: tacna vrednost je `vhdlSource-2008` SA CRTICOM. Sa `vhdlSource2008` Vivado
# NE javlja gresku -- prosto prestane da vidi fajlove kao VHDL, pa OOC sinteza napravi
# `ncc_accel` kao BLACKBOX bez ijedne greske, a padne tek implementacija (DRC INBB-3).
# Referenca za pravopis: data/ip/xilinx/dds_compiler_v6_0/component.xml.
#
# --- POPRAVKA 2: C_S01_AXI_ADDR_WIDTH ---
# Wizard "Memory Size" staje na 1024 B, pa je spakovao ADDR_WIDTH = 10. U Koraku 6 je
# VHDL default rucno postavljen na 17, ali NE i parametar u paketu -> instanca iz
# kataloga dobija 10 i S01 dekodira samo 1 KB umesto 128 KB. Simulacija to ne vidi jer
# instancira entitet direktno (VHDL default 17).
# Simptom u sintezi: ERROR [Synth 8-11324] array index 16 out of range (S01_AXI.vhd).
# NB: `mem_addr_o` je fiksno 17-bitni port ka mem_subsystem-u, pa je 17 jedina ispravna
# vrednost -- zato u S01_AXI.vhd postoji i staticki assert koji to proverava.
# ============================================================================

set REPO [file normalize [file join [file dirname [info script]] ../../..]]
set IPX  [file join $REPO src/vhdl_NCC_IP/ip_repo/ncc_accel_1_0/component.xml]
set VHDL_TYPE  vhdlSource-2008
set S01_WIDTH  17

if {![file exists $IPX]} { error "component.xml ne postoji: $IPX" }

ipx::open_ipxact_file $IPX
set core [ipx::current_core]
puts "### core: [get_property VLNV $core]"

# --- 1) tipovi fajlova -----------------------------------------------------
set changed 0
foreach fg [ipx::get_file_groups -of_objects $core] {
    foreach f [ipx::get_files -of_objects $fg] {
        set n [get_property NAME $f]
        if {![string match *.vhd $n]} { continue }
        if {[get_property TYPE $f] ne $VHDL_TYPE} {
            set_property TYPE $VHDL_TYPE $f
            incr changed
        }
    }
}
puts "### 1) tip fajlova -> $VHDL_TYPE : promenjeno $changed unosa"

# --- 2) C_S01_AXI_ADDR_WIDTH ----------------------------------------------
foreach getter {ipx::get_user_parameters ipx::get_hdl_parameters} {
    set p [$getter C_S01_AXI_ADDR_WIDTH -of_objects $core]
    if {$p eq ""} { error "nije nadjen parametar preko $getter" }
    set old [get_property VALUE $p]
    if {$old ne $S01_WIDTH} {
        set_property VALUE $S01_WIDTH $p
        incr changed
    }
    puts "### 2) [lindex [split $getter :] end] C_S01_AXI_ADDR_WIDTH: $old -> [get_property VALUE $p]"
}

# --- 3) core_revision -------------------------------------------------------
# Vivado kesira OOC sintezu IP-a po identitetu jezgra. Ako se RTL promeni a
# revizija ne, projekat koji je vec sintetisao ovaj IP moze da REUPOTREBI stari
# netlist -- ploca onda vrti stari RTL dok logovi javljaju uspeh. Vec smo se
# opekli na IP kesu (videti BUGS.md), zato se revizija dize pri svakoj popravci.
set old_rev [get_property core_revision $core]
set new_rev [expr {$old_rev + 1}]
set_property core_revision $new_rev $core
puts "### 3) core_revision: $old_rev -> $new_rev"

ipx::save_core $core
puts "### component.xml sacuvan (ukupno promena: $changed + revizija)"

# --- provera posle upisa ---------------------------------------------------
ipx::open_ipxact_file $IPX
set core [ipx::current_core]
set bad 0
foreach fg [ipx::get_file_groups -of_objects $core] {
    foreach f [ipx::get_files -of_objects $fg] {
        set n [get_property NAME $f]
        if {[string match *.vhd $n] && [get_property TYPE $f] ne $VHDL_TYPE} {
            puts "### GRESKA: $n je [get_property TYPE $f]"; incr bad
        }
    }
}
foreach getter {ipx::get_user_parameters ipx::get_hdl_parameters} {
    set v [get_property VALUE [$getter C_S01_AXI_ADDR_WIDTH -of_objects $core]]
    if {$v ne $S01_WIDTH} { puts "### GRESKA: $getter daje $v"; incr bad }
}
if {$bad > 0} { error "$bad neuspelih provera" }
puts "### OK: svi .vhd su $VHDL_TYPE, C_S01_AXI_ADDR_WIDTH = $S01_WIDTH"
