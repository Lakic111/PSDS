#!/bin/bash
# ---------------------------------------------------------------
# PSDS -- Task 1 mesovite simulacije (SystemC + HDL) u Xcelium-u.
# Pravi ~/xcelium_smoke/ sa fajlovima iz Mesovita.pdf (Listinzi 2.1-2.5).
#
# Pokretanje na CentOS masini:
#   curl -sL https://raw.githubusercontent.com/Lakic111/PSDS/korak6-axi-ip/src/cosim/smoke/setup.sh | bash
# ---------------------------------------------------------------
set -e
mkdir -p ~/xcelium_smoke && cd ~/xcelium_smoke

cat > counter.v <<'PSDS_EOF'
// Listing 2.1 iz Mesovita.pdf (str. 100-101) -- prepisano doslovno.
// Poznat-dobar primer; ne menjati. Sluzi samo da potvrdi da xmsc_run radi.
module counter (
        dout,
        clk, rst, load, din
        );
   input clk;
   input rst;
   input load;
   input [7:0] din;
   output [7:0] dout;

   reg [7:0] cnt;

   always @ ( posedge clk )
     begin
        if (rst)
          cnt <= 8'd0;
        else
          if (load)
            cnt <= din;
          else
            cnt <= cnt + 1'b1;
     end

   assign dout = cnt;
endmodule
PSDS_EOF

cat > counter.vhd <<'PSDS_EOF'
-- VHDL verzija Listinga 2.1 -- za Korak 3 Taska 1: da li xmsc_run prima VHDL
-- isto kao Verilog. Portovi su IDENTICNI (imena i redosled) da counter.hpp
-- omotac ne mora da se menja.
--
-- std_logic_vector za din/dout jer omotac koristi sc_lv<8>, i std_logic za
-- rst/load jer omotac koristi sc_logic. clk je sc_in<bool> u omotacu -- to
-- Xcelium mapira na std_logic ulaz.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
    port (
        dout : out std_logic_vector(7 downto 0);
        clk  : in  std_logic;
        rst  : in  std_logic;
        load : in  std_logic;
        din  : in  std_logic_vector(7 downto 0)
    );
end entity counter;

architecture rtl of counter is
    signal cnt : unsigned(7 downto 0);
begin
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt <= (others => '0');
            else
                if load = '1' then
                    cnt <= unsigned(din);
                else
                    cnt <= cnt + 1;
                end if;
            end if;
        end if;
    end process;

    dout <= std_logic_vector(cnt);
end architecture rtl;
PSDS_EOF

cat > counter.hpp <<'PSDS_EOF'
// Listing 2.2 iz Mesovita.pdf (str. 101) -- omotac klase brojaca.
// Nasledjuje sc_foreign_module: navedeni su svi portovi HDL modela, a
// hdl_name() vraca ime entiteta/modula kako ga simulator vidi.
#ifndef _COUNTER_HPP_
#define _COUNTER_HPP_

#include <systemc>

class counter : public sc_core::sc_foreign_module
{
public:
    counter(sc_core::sc_module_name name) :
        sc_core::sc_foreign_module(name),
        clk("clk"),
        rst("rst"),
        load("load"),
        din("din"),
        dout("dout")
    {
    }

    sc_core::sc_in< bool >              clk;
    sc_core::sc_in< sc_dt::sc_logic >   rst;
    sc_core::sc_in< sc_dt::sc_logic >   load;
    sc_core::sc_in< sc_dt::sc_lv<8> >   din;
    sc_core::sc_out< sc_dt::sc_lv<8> >  dout;

    const char* hdl_name() const { return "counter"; }
};

#endif
PSDS_EOF

cat > tb_counter.hpp <<'PSDS_EOF'
// Listing 2.3 iz Mesovita.pdf (str. 102) -- zaglavlje jednostavnog testbenca.
// SC_MODULE_EXPORT oznacava tb_counter kao kandidata za top modul kada se
// simulacija pokrece BEZ sc_main (varijanta sa -top tb_counter).
#ifndef TB_COUNTER
#define TB_COUNTER

#include <systemc>
#include "counter.hpp"

class tb_counter : public sc_core::sc_module
{
public:
    tb_counter(sc_core::sc_module_name name);
protected:
    void gen_thread();
    void mon_thread();
    counter dut;
    sc_core::sc_clock clk;

    sc_core::sc_signal< sc_dt::sc_logic >  rst;
    sc_core::sc_signal< sc_dt::sc_logic >  load;
    sc_core::sc_signal< sc_dt::sc_lv<8> >  din;
    sc_core::sc_signal< sc_dt::sc_lv<8> >  dout;
private:
};

#ifndef SC_MAIN
SC_MODULE_EXPORT(tb_counter)
#endif

#endif
PSDS_EOF

cat > tb_counter.cpp <<'PSDS_EOF'
// Listing 2.4 iz Mesovita.pdf (str. 103) -- implementacija testbenca.
// Napomena: u PDF-u su razmaci u string literalima odstampani kao donje crte
// (font za listinge); ovde su vraceni u obicne razmake.
#include "tb_counter.hpp"
#include <string>
#include <sstream>

using namespace sc_core;
using namespace sc_dt;
using namespace std;

SC_HAS_PROCESS(tb_counter);

tb_counter::tb_counter(sc_module_name name) :
    sc_module(name),
    dut("dut"),
    clk("clk", 5, SC_NS)
{
    SC_THREAD(gen_thread);
    SC_METHOD(mon_thread);
    dont_initialize();
    sensitive << dout;
    dut.clk( clk.signal() );
    dut.rst( rst );
    dut.load( load );
    dut.din( din );
    dut.dout( dout );
}

void tb_counter::gen_thread()
{
    rst.write( SC_LOGIC_1 );
    load.write( SC_LOGIC_0 );
    din.write( 7 );
    wait(100, SC_NS);
    rst.write( SC_LOGIC_0 );
    wait(500, SC_NS);
    load.write( SC_LOGIC_1 );
    wait(100, SC_NS);
    load.write( SC_LOGIC_0 );
    wait(1000, SC_NS);
    sc_stop();
}

void tb_counter::mon_thread()
{
    ostringstream ss;
    ss << "@" << sc_time_stamp();
    ss << " dout = " << dout.read();
    ss << " (" << static_cast< sc_uint<8> >( dout.read() ) << ")";
    SC_REPORT_INFO(name(), ss.str().c_str());
}
PSDS_EOF

cat > sc_main.cpp <<'PSDS_EOF'
// Listing 2.5 iz Mesovita.pdf (str. 103-104) -- glavni program.
// SC_MAIN se definise PRE ukljucivanja tb_counter.hpp da SC_MODULE_EXPORT
// ne bi bio aktiviran (top modul je ovde sc_main, ne tb_counter).
#define SC_MAIN
#include <systemc>
#include "tb_counter.hpp"

using namespace sc_core;

int sc_main(int argc, char* argv[])
{
    tb_counter uut("uut");
    sc_start();
    return 0;
}
PSDS_EOF

cat > run.sh <<'PSDS_EOF'
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
PSDS_EOF

chmod +x run.sh
echo
echo "Napravljeno u $(pwd):"
ls -l
echo
echo "Sledece:  cd ~/xcelium_smoke"
echo "          ./run.sh v      # Verilog, poznat-dobar primer"
echo "          ./run.sh vhd    # VHDL -- ovo nam zapravo treba"
