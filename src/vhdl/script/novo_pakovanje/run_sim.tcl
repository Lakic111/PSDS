# ============================================================================
# Pusta sve testbenchove i sabira rezultate. Verifikacija u jednoj komandi.
#
# Pokretanje (iz src/script/):
#   vivado.bat -mode batch -source run_sim.tcl
#   vivado.bat -mode batch -source run_sim.tcl -tclargs ncc_core_tb   (samo jedan)
#
# Testbenchovi PRIJAVLJUJU rezultat preko `report ... severity note/failure`.
# Ova skripta hvata "FAIL" u izlazu i pada ako ga nadje -- pokretanje bez
# provere izlaza ne bi vredelo nista.
#
# NAPOMENA o trajanju: ncc_core_real_tb i ncc_accel_tb rade pun NCC proracun
# (~2,4 miliona taktova) i traju MINUTIMA u simulaciji. Ostali su sekunde.
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT       [file normalize [file join $SCRIPT_DIR ../..]]
set SRC        [file join $ROOT src/vhdl]
set TB         [file join $ROOT src/tb]
set WORK       [file join $ROOT result/_sim]

# --- spisak: {ime_tb  {dodatni_izvori...}  opis} ---------------------------
# Redosled je od najbrzih ka najsporijim, da se greske vide rano.
set SVI {
    {dp_bram_tb                  {dp_bram.vhd}
                                 "dvoportna memorija"}
    {mem_subsystem_tb            {ncc_pkg.vhd dp_bram.vhd mem_subsystem.vhd}
                                 "memorijski podsistem"}
    {ncc_core_tb                 {ncc_pkg.vhd ncc_core.vhd}
                                 "zlatni 4x4/2x2, svih 9 tacaka"}
    {ncc_accel_wfirst_tb         {ncc_pkg.vhd dp_bram.vhd mem_subsystem.vhd ncc_core.vhd ncc_accel_slave_lite_v1_0_S00_AXI.vhd}
                                 "S00: sva cetiri redosleda upisa (W pre AW)"}
    {ncc_accel_s01_burst_wfirst_tb {ALL}
                                 "S01: burst, sva cetiri redosleda"}
    {ncc_accel_burst_tb          {ALL}
                                 "S01: burst citanje/upis, WSTRB, rani AW"}
    {ncc_core_real_tb            {ncc_pkg.vhd ncc_core.vhd}
                                 "realni 90x90 + crni top -- SPOR (minuti)"}
    {ncc_accel_tb                {ALL}
                                 "ceo IP kroz AXI, zlatni pik -- SPOR (minuti)"}
}

set SVI_IZVORI {
    ncc_pkg.vhd dp_bram.vhd mem_subsystem.vhd ncc_core.vhd
    ncc_accel_slave_lite_v1_0_S00_AXI.vhd
    ncc_accel_slave_full_v1_0_S01_AXI.vhd
    ncc_accel.vhd
}

# --- izbor: sve ili jedan imenovan -----------------------------------------
set trazeni ""
if {[info exists argv] && [llength $argv] > 0} { set trazeni [lindex $argv 0] }

file delete -force $WORK
file mkdir $WORK
cd $WORK

set prosli 0
set pali   {}
set preskoceni 0

foreach stavka $SVI {
    lassign $stavka ime izvori opis

    if {$trazeni ne "" && $ime ne $trazeni} { incr preskoceni; continue }

    set tb_fajl [file join $TB $ime.vhd]
    if {![file exists $tb_fajl]} {
        puts "@@@ PRESKACEM $ime -- nema $tb_fajl"
        incr preskoceni
        continue
    }

    if {$izvori eq "ALL"} { set izvori $SVI_IZVORI }
    set lista {}
    foreach f $izvori { lappend lista [file join $SRC $f] }
    lappend lista $tb_fajl

    puts "@@@ ---------------------------------------------------------------"
    puts "@@@ $ime -- $opis"

    # xvhdl/xelab/xsim se pozivaju kao spoljni alati; -2008 je obavezan
    # (ncc_core koristi `process (all)`).
    if {[catch {exec xvhdl -2008 {*}$lista} izlaz]} {
        puts "@@@ ANALIZA PALA:\n$izlaz"
        lappend pali "$ime (xvhdl)"
        continue
    }
    if {[catch {exec xelab -debug off $ime -s sim_$ime} izlaz]} {
        puts "@@@ ELABORACIJA PALA:\n$izlaz"
        lappend pali "$ime (xelab)"
        continue
    }
    if {[catch {exec xsim sim_$ime -R} izlaz]} {
        # xsim vraca != 0 i kad TB zavrsi sa `severity failure` -- to je ocekivano
        # za pali test, pa se izlaz svejedno pregleda.
        puts $izlaz
    } else {
        puts $izlaz
    }

    if {[string match -nocase "*FAIL*" $izlaz]} {
        puts "@@@ >>> $ime: PAO"
        lappend pali $ime
    } else {
        puts "@@@ >>> $ime: PROSAO"
        incr prosli
    }
}

puts "@@@ ==============================================================="
puts "@@@ REZULTAT: $prosli proslo, [llength $pali] palo, $preskoceni preskoceno"
if {[llength $pali] > 0} {
    foreach f $pali { puts "@@@   PAO: $f" }
    error "SIMULACIJA: [llength $pali] testbenchova nije proslo"
}
puts "@@@ SVI TESTBENCHOVI PROSLI"
