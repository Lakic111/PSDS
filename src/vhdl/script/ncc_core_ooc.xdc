# Ograničenje takta za samostalnu (out-of-context) sintezu golog ncc_core.
# MORA se procitati PRE synth_design -- inace se jezgro sintetise neogranice
# (bez timing-driven mapiranja), pa je svaki WNS izmeren nad netlistom od koga
# se zadata frekvencija nikad nije ni trazila. Nadjeno u code review-u Koraka 8.
#
# PERIOD JE PARAMETAR (Korak 8, Task 10). Postavi `NCC_PERIOD` pre `read_xdc`:
#   set NCC_PERIOD 11.0   ;# radni takt sistema, 90,909 MHz
#   set NCC_PERIOD 10.0   ;# nominalnih 100 MHz  (podrazumevano)
#
# ZASTO PARAMETAR: alat optimizuje DO zadatog ogranicenja i staje kad ga ispuni,
# pa je kriticna putanja na labavijem ogranicenju DUZA. Slack se zato ne sme
# aritmeticki prevoditi izmedju ogranicenja, a Fmax se meri na ogranicenju koje
# se tvrdi. Izmereno na aktuelnom RTL-u, xc7z010clg400-1, post-route:
#   @ 11,0 ns -> WNS +0,387 ns, putanja 10,638 ns (46% rutiranje), 16 nivoa
#   @ 10,0 ns -> WNS +0,146 ns, putanja  9,832 ns (20% rutiranje), 12 nivoa,
#                kvadriranje mapirano u DSP48E1  =>  Fmax ~101,5 MHz
# Videti BUGS.md, odeljak o prevodjenju rezerve izmedju ogranicenja.

if {![info exists NCC_PERIOD]} { set NCC_PERIOD 10.0 }
create_clock -period $NCC_PERIOD -name clk [get_ports clk]
