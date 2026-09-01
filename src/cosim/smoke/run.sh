#!/bin/bash
# Task 1 -- dijagnostika: da li Xcelium na fakultetskoj masini ume mesovitu
# VHDL + SystemC simulaciju. Pusta se NA CentOS masini, u ~/xcelium_smoke/.
#
#   ./run.sh v      -> Verilog varijanta (Listing 2.1, poznat-dobar primer)
#   ./run.sh vhd    -> VHDL varijanta (isti portovi, ovo nam zapravo treba)
#   ./run.sh top    -> bez sc_main, preko -top tb_counter
#
# GUI se NE koristi po difoltu: preko remote veze cesto nema X displeja, a
# smoke test se vidi iz konzole. Za GUI dodati -gui (treba X11 forwarding).

set -e
VARIJANTA="${1:-v}"

echo "=== okruzenje ==="
which xmsc_run || { echo "GRESKA: xmsc_run nije u PATH-u -- ucitaj Cadence setup"; exit 1; }
xmsc_run -version 2>&1 | head -3 || true
echo

case "$VARIJANTA" in
  v)
    echo "=== Korak 2: Verilog, sa sc_main (str. 104) ==="
    set -x
    xmsc_run -sc_main sc_main.cpp tb_counter.cpp counter.v
    ;;
  vhd)
    echo "=== Korak 3: VHDL, sa sc_main ==="
    echo "Ako Xcelium ne prepozna .vhd po ekstenziji, probati redom:"
    echo "   xmsc_run -sc_main sc_main.cpp tb_counter.cpp -vhdl counter.vhd"
    echo "   xmsc_run -sc_main sc_main.cpp tb_counter.cpp -v200x counter.vhd"
    echo "   xmsc_run -help | grep -i vhdl"
    set -x
    xmsc_run -sc_main sc_main.cpp tb_counter.cpp counter.vhd
    ;;
  top)
    echo "=== varijanta bez sc_main, top je tb_counter (str. 104) ==="
    set -x
    xmsc_run tb_counter.cpp counter.v -top tb_counter
    ;;
  *)
    echo "upotreba: $0 [v|vhd|top]"; exit 2
    ;;
esac

# OCEKIVANO: niz SC_REPORT_INFO linija oblika
#   Info: uut: @<vreme> dout = 00000111 (7)
# Posle rst pada na 0 brojac broji; na load upisuje din = 7, pa nastavlja.
# Ako se to vidi -> alat radi, prelazi se na Task 2.
