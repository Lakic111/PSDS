#!/bin/bash
# ============================================================================
#  Mesovita simulacija (SystemC ESL + VHDL RTL) -- pokretanje na ws2.
#
#  Preduslov:  . amsgo        (SA TACKOM -- source; bez toga nema xmsc_run)
#  Radni folder: svi fajlovi RAVNO u jednom direktorijumu (nema podfoldera),
#  jer se #include-i pisu bez putanje.
#
#  Ocekivano trajanje: pun prolaz 90x90 / 25x15 je ~3,8M taktova RTL-a
#  (~38 ms sim vremena). Bez -gui. GUI se koristi samo za debug, i to na
#  malom testu -- kroz GUI je 3,8M taktova mucenje.
# ============================================================================
set -e

FAJLOVI_CPP="sc_main_cosim.cpp ncc_target_rtl.cpp ncc.cpp bram.cpp"
FAJLOVI_VHD="ncc_pkg.vhd ncc_core.vhd"

echo "=== provera okruzenja ==="
which xmsc_run || { echo "GRESKA: nema xmsc_run -- pokreni:  . amsgo"; exit 1; }

echo "=== provera da su svi fajlovi tu ==="
for f in $FAJLOVI_CPP $FAJLOVI_VHD common.hpp ncc.hpp bram.hpp \
         ncc_core_wrap.hpp ncc_target_rtl.hpp seg90.hex crnitop.hex; do
    [ -f "$f" ] || { echo "GRESKA: nedostaje $f"; exit 1; }
done

# CRLF ubija i VHDL i heks ucitavanje, a stigao je kroz Windows klipbord.
sed -i 's/\r$//' $FAJLOVI_CPP $FAJLOVI_VHD common.hpp ncc.hpp bram.hpp \
                 ncc_core_wrap.hpp ncc_target_rtl.hpp seg90.hex crnitop.hex

echo "=== provera velicine prenetih fajlova ==="
wc -l ncc_pkg.vhd ncc_core.vhd seg90.hex crnitop.hex
echo "ncc_pkg.vhd mora biti 41 linija, ncc_core.vhd 554, seg90.hex 90, crnitop.hex 15"
md5sum ncc_pkg.vhd ncc_core.vhd
echo "ocekivano: 9b74232297daaca3ed350186471c0f4d  ncc_pkg.vhd"
echo "ocekivano: f957c44b35c4c5e15d7894ff4637a348  ncc_core.vhd"

# Radna biblioteka se cisti pre svakog pokretanja: ostatak od ranijeg
# prevodjenja daje *F,CUSCMU: More than one unit matches.
rm -rf xcelium.d INCA_libs *.log *.history

echo "=== xmsc_run ==="
set -x
xmsc_run -sc_main -xmvhdl_args,-v200x $FAJLOVI_CPP $FAJLOVI_VHD
