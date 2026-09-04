# Mešovita simulacija (SystemC ESL + VHDL RTL) — Plan implementacije

> Zahtev profesora/asistenta: dokazati da RTL (`ncc_core.vhd`, Korak 3) daje isti
> rezultat kao SystemC/TLM ESL model (`src/ncc.cpp`, PEUSN faza) kroz **jednu
> zajedničku kosimulaciju** u Xcelium-u, ne poređenjem dva odvojeno snimljena
> golden fajla (što je već urađeno — `0x80000000 @ (32,14)` se poklapa i u C
> kernelu, i u samostalnom VHDL testbenchu, i na ploči).

**Cilj:** `NCC_Target` (SystemC TLM modul koji danas RAČUNA NCC² u C++-u) dobija
alternativni mod rada u kome se, umesto C++ proračuna, stvarni `ncc_core.vhd`
pokreće ciklus-po-ciklus unutar iste simulacije — preko `sc_foreign_module`
omotača (šablon iz `Mesovita.pdf`, poglavlje 2.1.1) i transaktora koji radi
tačno ono što `ncc_core_real_tb.vhd` već radi u čistom VHDL-u (poglavlje 2.2,
"Profinjenje modela" — faza 3, Slika 2.6: TLM + Transactor + RTL).

**Arhitektura:** Nov SystemC modul `NCC_Target_RTL` ima **identičan spoljni TLM
interfejs** kao postojeći `NCC_Target` (isti `socket`/`i_bram`), pa se u
`vp.cpp` samo menja koja se klasa instancira — ostatak sistema (`tb.cpp`,
`sys_bus`, `dma`, `ddr`) se ne dira. Iznutra, `NCC_Target_RTL` čita
sliku/šablon preko `i_bram` (isti kod kao `NCC_Target::read_from_bram`), pa ih
predaje transaktoru koji ciklus-po-ciklus vozi pinove `ncc_core`-a (BRAM-stil
adresa/podatak, `start`/`busy`/`done`), i na kraju vraća `result_map`.

**Tech stack:** Cadence Xcelium (`xmsc_run`), SystemC 2.3.x (isto okruženje kao
`src/sc_main.cpp`), VHDL-2008 (`ncc_core.vhd`, nepromenjen — Korak 3/4 izvor,
**ne diramo verifikovano jezgro**).

**Spec:** `Mesovita.pdf` (na Desktopu — dokumentacija predmeta koji je prethodio
ovom projektu), poglavlja 2.1 ("Simulacija modela razvijenih u različitim
jezicima") i 2.2 ("Profinjavanje modela"), + postojeći
`src/vhdl/tb/ncc_core_real_tb.vhd` kao referentni protokol.

## Globalna ograničenja

- **Xcelium NIJE instaliran na ovoj mašini** (proveреno — nema `xrun`/`xmsc_run`
  u PATH-u, nema Cadence foldera). Ovaj plan se izvršava **na fakultetskoj
  mašini** koja ima licencu. Task 1 je dijagnostički i mora proći PRE bilo čega
  drugog.
- `ncc_core.vhd` se **ne menja** — to je verifikovano jezgro (Koraci 3-5,
  golden `0x80000000 @ (u=32,v=14)`, bit-tačno kroz ceo tok do ploče). Ako
  kosimulacija ne prođe, greška je u transaktoru/omotaču, ne u jezgru.
- `NCC_Target` (postojeći C++ model) se **ne menja** — nova klasa je paralelna,
  aktivira se preko `#ifdef NCC_COSIM_RTL` u `vp.cpp`, da default build (bez
  Xcelium-a) ostane potpuno nepromenjen i i dalje radiv na ovoj mašini.
- Test podaci: isti kao Korak 4 — `src/hls/data/data/board2.txt` (90×90 segment
  polja a8) + `Crnitoptemplate.txt` (25×15), ili već izvučeni
  `src/vhdl/tb/seg90.txt`/`crnitop.txt` (jedan piksel po liniji, već u repou).
  Golden: `0x80000000` na poziciji `(u=32, v=14)` = indeks 956 u result mapi
  66×76.

---

### Task 1: Dijagnostika — potvrditi da Xcelium ume mešovitu VHDL+SystemC simulaciju

**Cilj:** Pre pisanja ijedne linije transaktora, potvrditi na fakultetskoj
mašini da `xmsc_run` ume da elaborira VHDL entitet zajedno sa SystemC
`sc_foreign_module` omotačem, i kojim se tačno flegom VHDL fajl prosleđuje
(u `Mesovita.pdf` primeri su za Verilog — `xmsc_run ... counter.v` — VHDL
flag/ekstenzija treba potvrditi iz Xcelium `-help` ili lokalne dokumentacije,
jer PEUSN materijal to ne pokriva eksplicitno).

**Fajlovi:**
- Create (na fakultetskoj mašini, van git repoa): `~/xcelium_smoke/counter.v`,
  `counter.hpp`, `tb_counter.hpp/.cpp`, `sc_main.cpp` — **doslovno prepisan
  primer iz `Mesovita.pdf`, Listinzi 2.1–2.5** (brojač, ne NCC). Cilj ovog
  taska nije NCC nego potvrda da alat radi, sa najmanjim mogućim primerom.

- [x] **Korak 1: Prepiši primer brojača iz PDF-a u čist folder** (2026-09-01)

  Listing 2.1 (`counter.v`), 2.2 (`counter.hpp`), 2.3 (`tb_counter.hpp`),
  2.4 (`tb_counter.cpp`), 2.5 (`sc_main.cpp`) — tačno kako stoji u
  `Mesovita.pdf` str. 100-103. Ne menjati ništa, ovo je poznat-dobar primer.

- [x] **Korak 2: Pokreni prema uputstvu iz PDF-a (str. 104)** — prošlo

  ```
  xmsc_run -sc_main -gui sc_main.cpp tb_counter.cpp counter.v
  ```

  Očekivano: simulacija se pokrene, GUI se otvori, `mon_thread` ispisuje
  `dout` posle `load`/`rst` sekvence iz `gen_thread` (vidljivo u konzoli/logu
  kao `SC_REPORT_INFO` linije sa `dout_=`).

- [x] **Korak 3: Ponovi isto sa VHDL verzijom brojača umesto `counter.v`** — prošlo, videti Nalaze

  Prepiši `counter.v` (Listing 2.1) u VHDL (trivijalan brojač, isti portovi:
  `clk, rst, load, din[7:0], dout[7:0]`), sačuvaj kao `counter.vhd`, i probaj:

  ```
  xmsc_run -sc_main -gui sc_main.cpp tb_counter.cpp counter.vhd
  ```

  Ako Xcelium sam po ekstenziji prepozna VHDL — gotovo, prelazi se na Task 2.
  Ako javi grešku da fajl nije prepoznat, proveri `xmsc_run -help` za flegove
  tipa `-vhdl`/`-v93`/`-v08` i probaj ponovo. **Zapiši tačnu komandu koja radi**
  — ona ide u Task 5.

- [x] **Korak 4: Zapiši nalaz u `BUGS.md` ili ovaj plan** — upisano u Nalaze

  Bez obzira na ishod, dopuni ovaj fajl (sekcija "Nalazi sa fakultetske
  mašine" na dnu) sa tačnom komandom i verzijom Xcelium-a — sledeći put se ne
  traži ispočetka.

---

### Task 2: `sc_foreign_module` omotač oko `ncc_core.vhd`

**Fajlovi:**
- Create: `src/cosim/ncc_core_wrap.hpp`

**Interfejsi:**
- Konzumira: entitet `ncc_core` iz `src/vhdl/ncc_core.vhd` (17 portova, videti
  ispod) — **fajl se NE kopira ni menja**, samo se referencira po imenu kroz
  `hdl_name()`.
- Produkuje: klasu `ncc_core_wrap : public sc_core::sc_foreign_module` sa
  javnim `sc_in`/`sc_out` portovima koje Task 3 (transaktor) direktno vozi.

`ncc_core` entitet (`src/vhdl/ncc_core.vhd`, ne menjati):

```vhdl
entity ncc_core is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        busy       : out std_logic;
        done       : out std_logic;
        img_w      : in  dim_t;                                    -- unsigned(7 downto 0)
        img_h      : in  dim_t;
        tmp_w      : in  dim_t;
        tmp_h      : in  dim_t;
        img_addr_o    : out integer range 0 to MAX_IMG_PIX - 1;     -- 0..8099
        img_data_i    : in  pixel_t;                                -- unsigned(7 downto 0)
        templ_addr_o  : out integer range 0 to MAX_TMP_PIX - 1;     -- 0..899
        templ_data_i  : in  pixel_t;
        result_addr_o : out integer range 0 to MAX_IMG_PIX - 1;
        result_data_o : out result_t;                               -- unsigned(31 downto 0)
        result_wr_o   : out std_logic
    );
end entity ncc_core;
```

- [x] **Korak 1: Napiši omotač po šablonu iz `Mesovita.pdf` Listing 2.2/2.6**

```cpp
// src/cosim/ncc_core_wrap.hpp
#ifndef NCC_CORE_WRAP_HPP
#define NCC_CORE_WRAP_HPP

#include <systemc.h>

// Omotac oko VHDL entiteta `ncc_core` (src/vhdl/ncc_core.vhd, Korak 3/4).
// NE MENJATI ncc_core.vhd -- ovo je samo SystemC "ogledalo" njegovih pinova,
// prema xmsc_run konvenciji za mesovitu simulaciju (Mesovita.pdf, 2.1.1).
class ncc_core_wrap : public sc_core::sc_foreign_module
{
public:
    // Kontrolni/status pinovi
    sc_core::sc_in<bool>  clk;
    sc_core::sc_in<bool>  rst;
    sc_core::sc_in<bool>  start;
    sc_core::sc_out<bool> busy;
    sc_core::sc_out<bool> done;

    // Dimenzije (dim_t = unsigned(7 downto 0))
    sc_core::sc_in<sc_dt::sc_uint<8> > img_w;
    sc_core::sc_in<sc_dt::sc_uint<8> > img_h;
    sc_core::sc_in<sc_dt::sc_uint<8> > tmp_w;
    sc_core::sc_in<sc_dt::sc_uint<8> > tmp_h;

    // BRAM-stil interfejs ka slici/sablonu/rezultatu
    // NAPOMENA (proveriti u Task 1): ako Xcelium ne mapira VHDL `integer`
    // direktno na sc_uint, probati sc_core::sc_in<int>/sc_out<int> ovde --
    // MAX_IMG_PIX-1 = 8099 stane u 13 bita, ali integer u VHDL-u je 32-bitni
    // signed, pa je sc_uint<32> najsigurniji prvi pokusaj.
    sc_core::sc_out<sc_dt::sc_uint<32> > img_addr_o;
    sc_core::sc_in<sc_dt::sc_uint<8> >   img_data_i;
    sc_core::sc_out<sc_dt::sc_uint<32> > templ_addr_o;
    sc_core::sc_in<sc_dt::sc_uint<8> >   templ_data_i;
    sc_core::sc_out<sc_dt::sc_uint<32> > result_addr_o;
    sc_core::sc_in<sc_dt::sc_uint<32> >  result_data_o;
    sc_core::sc_in<bool>                 result_wr_o;

    ncc_core_wrap(sc_core::sc_module_name name) :
        sc_core::sc_foreign_module(name),
        clk("clk"), rst("rst"), start("start"), busy("busy"), done("done"),
        img_w("img_w"), img_h("img_h"), tmp_w("tmp_w"), tmp_h("tmp_h"),
        img_addr_o("img_addr_o"), img_data_i("img_data_i"),
        templ_addr_o("templ_addr_o"), templ_data_i("templ_data_i"),
        result_addr_o("result_addr_o"), result_data_o("result_data_o"),
        result_wr_o("result_wr_o")
    {
        elaborate_foreign_module();
    }

    const char* hdl_name() const { return "ncc_core"; }
};

#endif // NCC_CORE_WRAP_HPP
```

- [x] **Korak 2: Zapamti otvoreno pitanje o `sc_out`/`sc_in` smeru za
  `result_data_o`/`result_wr_o`**

  U VHDL-u su to `out` portovi jezgra, ali u SystemC omotaču se posmatraju kao
  ULAZ (jezgro ih vozi, transaktor ih ČITA) — otud `sc_in` u omotaču iako se
  zovu `_o`. Ovo je namerno, ne printing greška; ostavi komentar u kodu da se
  ne "ispravi" pogrešno.

---

### Task 3: Transaktor `NCC_Target_RTL` (isti TLM interfejs kao `NCC_Target`)

**Fajlovi:**
- Create: `src/cosim/ncc_target_rtl.hpp`
- Create: `src/cosim/ncc_target_rtl.cpp`

**Interfejsi:**
- Konzumira: `ncc_core_wrap` (Task 2), `common.hpp` registre
  (`REG_IMG_W..REG_CTRL`, `ADDR_BRAM`), `tlm_utils::simple_target_socket` i
  `simple_initiator_socket` (isti tip kao `NCC_Target`).
- Produkuje: klasu `NCC_Target_RTL` sa **identičnim javnim članovima kao
  `NCC_Target`** (`socket`, `i_bram`) — `vp.cpp` (Task 4) je jedino mesto koje
  zna za razliku.

Protokol koji transaktor mora da vozi je **doslovno isti** kao
`mem_model`/`clk_gen` procesi u `src/vhdl/tb/ncc_core_real_tb.vhd`: registrovano
čitanje (adresa ovog takta → podatak sledećeg takta), `result_wr='1'` upisuje
`result_data` na `result_addr`.

- [x] **Korak 1: Header — isti javni interfejs kao `NCC_Target`**

```cpp
// src/cosim/ncc_target_rtl.hpp
#ifndef NCC_TARGET_RTL_HPP
#define NCC_TARGET_RTL_HPP

#include "common.hpp"
#include "ncc_core_wrap.hpp"
#include <vector>

// Isti spoljni TLM interfejs kao NCC_Target (src/ncc.hpp), ali NCC^2 racuna
// stvarni VHDL RTL (ncc_core_wrap) umesto C++ koda -- za mesovitu simulaciju
// koju trazi profesor (Mesovita.pdf, 2.2 "Profinjavanje modela", Slika 2.6).
class NCC_Target_RTL : public sc_core::sc_module {
public:
    SC_HAS_PROCESS(NCC_Target_RTL);

    tlm_utils::simple_target_socket<NCC_Target_RTL>    socket;
    tlm_utils::simple_initiator_socket<NCC_Target_RTL> i_bram;

    sc_core::sc_event start_ev;
    sc_core::sc_event done_ev;

    std::vector<uint8_t> image, templ;
    std::vector<int32_t> result_map;
    int img_w, img_h, tmp_w, tmp_h;
    uint64_t img_addr, tmp_addr;
    uint32_t hw_status;
    bool     img_dirty;

    NCC_Target_RTL(sc_core::sc_module_name name);
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay);

private:
    void ncc_proc();               // SC_THREAD: vozi RTL ciklus-po-ciklus
    void drive_clock();             // SC_THREAD: 100 MHz clk za dut
    void mem_and_pins_proc();       // SC_METHOD, osetljiv na clk.pos(): BRAM model + hvatanje rezultata
    void read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len);

    ncc_core_wrap dut;
    sc_core::sc_signal<bool> sig_clk, sig_rst, sig_start, sig_busy, sig_done;
    sc_core::sc_signal<sc_dt::sc_uint<8> > sig_img_w, sig_img_h, sig_tmp_w, sig_tmp_h;
    sc_core::sc_signal<sc_dt::sc_uint<32> > sig_img_addr, sig_templ_addr, sig_result_addr, sig_result_data;
    sc_core::sc_signal<sc_dt::sc_uint<8> > sig_img_data, sig_templ_data;
    sc_core::sc_signal<bool> sig_result_wr;

    bool clk_running;
};

#endif // NCC_TARGET_RTL_HPP
```

- [x] **Korak 2: Implementacija — konstruktor i vezivanje pinova**

```cpp
// src/cosim/ncc_target_rtl.cpp
#include "ncc_target_rtl.hpp"

using namespace sc_core;
using namespace tlm;
using namespace std;

NCC_Target_RTL::NCC_Target_RTL(sc_module_name name) :
    sc_module(name), socket("socket"), i_bram("i_bram"),
    img_w(0), img_h(0), tmp_w(0), tmp_h(0), img_addr(0), tmp_addr(0),
    hw_status(0), img_dirty(false),
    dut("dut"),
    sig_clk("sig_clk"), sig_rst("sig_rst"), sig_start("sig_start"),
    sig_busy("sig_busy"), sig_done("sig_done"),
    sig_img_w("sig_img_w"), sig_img_h("sig_img_h"),
    sig_tmp_w("sig_tmp_w"), sig_tmp_h("sig_tmp_h"),
    sig_img_addr("sig_img_addr"), sig_templ_addr("sig_templ_addr"),
    sig_result_addr("sig_result_addr"), sig_result_data("sig_result_data"),
    sig_img_data("sig_img_data"), sig_templ_data("sig_templ_data"),
    sig_result_wr("sig_result_wr"),
    clk_running(false)
{
    socket.register_b_transport(this, &NCC_Target_RTL::b_transport);

    dut.clk(sig_clk);       dut.rst(sig_rst);       dut.start(sig_start);
    dut.busy(sig_busy);     dut.done(sig_done);
    dut.img_w(sig_img_w);   dut.img_h(sig_img_h);
    dut.tmp_w(sig_tmp_w);   dut.tmp_h(sig_tmp_h);
    dut.img_addr_o(sig_img_addr);       dut.img_data_i(sig_img_data);
    dut.templ_addr_o(sig_templ_addr);   dut.templ_data_i(sig_templ_data);
    dut.result_addr_o(sig_result_addr); dut.result_data_o(sig_result_data);
    dut.result_wr_o(sig_result_wr);

    SC_THREAD(ncc_proc);
    SC_THREAD(drive_clock);
    SC_METHOD(mem_and_pins_proc);
    sensitive << sig_clk.pos();
    dont_initialize();
}

// Isti kod kao NCC_Target::read_from_bram (src/ncc.cpp) -- transaktor cita
// sliku/sablon iz iste deljene BRAM memorije pre nego sto pokrene RTL.
void NCC_Target_RTL::read_from_bram(uint64_t bram_addr, unsigned char* dst, unsigned int len) {
    sc_time scratch = SC_ZERO_TIME;
    tlm_generic_payload pl;
    pl.set_command(TLM_READ_COMMAND);
    pl.set_address(bram_addr - ADDR_BRAM);
    pl.set_data_ptr(dst);
    pl.set_data_length(len);
    i_bram->b_transport(pl, scratch);
    wait(scratch);
}

// Registri se iz iste ove b_transport tacke pune kao kod NCC_Target
// (src/ncc.cpp) -- CTRL=1 samo okida start_ev, obrada ide u ncc_proc().
void NCC_Target_RTL::b_transport(tlm_generic_payload& trans, sc_time& delay) {
    tlm_command cmd = trans.get_command();
    uint64_t addr = trans.get_address();
    unsigned char* ptr = trans.get_data_ptr();

    if (cmd == TLM_WRITE_COMMAND) {
        if (addr == REG_IMG_W) img_w = *(int*)ptr;
        else if (addr == REG_IMG_H) img_h = *(int*)ptr;
        else if (addr == REG_TMP_W) tmp_w = *(int*)ptr;
        else if (addr == REG_TMP_H) tmp_h = *(int*)ptr;
        else if (addr == REG_IMG_ADDR) { img_addr = *(uint32_t*)ptr; img_dirty = true; }
        else if (addr == REG_TMP_ADDR) tmp_addr = *(uint32_t*)ptr;
        else if (addr == REG_CTRL && *(uint32_t*)ptr == 1) {
            hw_status = 0;
            start_ev.notify(SC_ZERO_TIME);
        }
    } else if (cmd == TLM_READ_COMMAND) {
        if (addr == REG_STATUS) *(uint32_t*)ptr = hw_status;
        else if (addr >= ADDR_RESULTS) {
            size_t idx = (addr - ADDR_RESULTS) / 4;
            if (idx < result_map.size()) *(int32_t*)ptr = result_map[idx];
        }
    }
}
```

- [x] **Korak 3: Clock generator i BRAM-model/hvatanje rezultata**

```cpp
// nastavak src/cosim/ncc_target_rtl.cpp

// 100 MHz -- isti nominalni takt kao ostatak ESL modela (K_CYC iz ncc.cpp).
// Radi samo dok je clk_running=true, da van RTL poziva simulacija ne trosi
// dogadjaje uzalud.
void NCC_Target_RTL::drive_clock() {
    while (true) {
        if (clk_running) {
            sig_clk.write(false); wait(5, SC_NS);
            sig_clk.write(true);  wait(5, SC_NS);
        } else {
            wait(sig_clk.value_changed_event() | sc_time(5, SC_NS));
        }
    }
}

// Isti model kao `mem_model` proces u ncc_core_real_tb.vhd: registrovano
// citanje (adresa OVOG takta -> podatak SLEDECEG), i hvatanje result_wr.
void NCC_Target_RTL::mem_and_pins_proc() {
    unsigned img_a = sig_img_addr.read().to_uint();
    unsigned tmp_a = sig_templ_addr.read().to_uint();
    sig_img_data.write(img_a < image.size() ? image[img_a] : 0);
    sig_templ_data.write(tmp_a < templ.size() ? templ[tmp_a] : 0);

    if (sig_result_wr.read()) {
        unsigned r_a = sig_result_addr.read().to_uint();
        uint32_t r_d = sig_result_data.read().to_uint();
        if (r_a >= result_map.size()) result_map.resize(r_a + 1, 0);
        result_map[r_a] = (int32_t)r_d;
    }
}

// Glavni proces: ceka start_ev (isto kao NCC_Target::ncc_proc), ucitava
// sliku/sablon preko i_bram (identican kod kao NCC_Target), pokrece RTL kroz
// reset+run+wait-done, pa objavljuje done_ev.
void NCC_Target_RTL::ncc_proc() {
    while (true) {
        wait(start_ev);

        if (img_dirty) {
            image.resize((size_t)img_w * img_h);
            read_from_bram(img_addr, image.data(), (unsigned)image.size());
            img_dirty = false;
        }
        templ.resize((size_t)tmp_w * tmp_h);
        read_from_bram(tmp_addr, templ.data(), (unsigned)templ.size());
        result_map.assign((size_t)img_w * img_h, 0);

        clk_running = true;
        sig_rst.write(true);
        wait(sig_clk.posedge_event());
        wait(sig_clk.posedge_event());
        sig_rst.write(false);

        sig_img_w.write(img_w);   sig_img_h.write(img_h);
        sig_tmp_w.write(tmp_w);   sig_tmp_h.write(tmp_h);

        sig_start.write(true);
        wait(sig_clk.posedge_event());
        sig_start.write(false);

        // Ceka opadajucu ivicu 'done' -- isti signal koji ncc_core_real_tb.vhd
        // koristi kao kraj testa (golden: done bez ijedne greske u handshake-u).
        do { wait(sig_clk.posedge_event()); } while (!sig_done.read());

        clk_running = false;
        hw_status = 1;   // DONE (isti kod kao NCC_Target::ncc_proc)
        done_ev.notify(SC_ZERO_TIME);
    }
}
```

- [x] **Korak 4: Napomena o `done_ev` potrošaču**

  `vp.cpp`/`tb.cpp` čekaju `done_ev` preko istog accessor mehanizma kao za
  `NCC_Target` (proveri tačno ime u `vp.cpp` — verovatno `ncc->done_ev` ili
  slično). Pošto je `NCC_Target_RTL` javni interfejs identičan, taj kod se ne
  menja — samo Task 4 menja koja se klasa instancira.

---

### Task 4: Uključivanje u `vp.cpp` iza build-flega

**Fajlovi:**
- Modify: `src/vp.hpp`, `src/vp.cpp`

**Interfejsi:**
- Konzumira: `NCC_Target` (postojeći, `src/ncc.hpp`) ILI `NCC_Target_RTL`
  (Task 3, `src/cosim/ncc_target_rtl.hpp`) — bira se na kompajl vremenu.

- [x] **Korak 1: Pronađi tačno mesto instanciranja u `vp.cpp`**

  ```
  grep -n "NCC_Target" src/vp.hpp src/vp.cpp
  ```

  Očekivano: `NCC_Target* ncc;` (ili slično) u headeru, `ncc = new
  NCC_Target("ncc");` u konstruktoru `vp`-a, plus vezivanje `ncc->socket` i
  `ncc->i_bram` na `sys_bus`/`ddr`.

- [x] **Korak 2: Uslovna kompilacija oko te dve linije**

  U `vp.hpp`, na vrh dodaj:

  ```cpp
  #ifdef NCC_COSIM_RTL
  #include "cosim/ncc_target_rtl.hpp"
  typedef NCC_Target_RTL NccImpl;
  #else
  #include "ncc.hpp"
  typedef NCC_Target NccImpl;
  #endif
  ```

  Zameni `NCC_Target* ncc;` sa `NccImpl* ncc;` i `new NCC_Target("ncc")` sa
  `new NccImpl("ncc")`. Ostatak fajla (vezivanje socketa) se ne menja jer je
  interfejs identičan (Task 3).

- [x] **Korak 3: Potvrdi da običan build (bez flega) i dalje radi nepromenjeno**

  ```
  g++ -std=c++17 -I<systemc_include> -I<tlm_include> -c src/vp.cpp -o /tmp/vp.o
  ```

  Očekivano: kompajlira se identično kao pre ovog taska (flag nije prosleđen,
  `NccImpl = NCC_Target`, nula promena u ponašanju). Ovo je regresiona provera
  da mešovita simulacija ne ugrožava postojeći, već verifikovani C++ model.

---

### Task 5: Xcelium build i poređenje sa golden rezultatom

**Fajlovi:**
- Create (na fakultetskoj mašini): `src/cosim/run_mixed_sim.sh` (ili `.bat`,
  zavisno od OS na toj mašini)

- [x] **Korak 1: Sastavi listu fajlova za `xmsc_run`**

  Na osnovu Task 1 nalaza (tačna VHDL komanda), pokreni:

  ```
  xmsc_run -sc_main -DNCC_COSIM_RTL \
      src/sc_main.cpp src/vp.cpp src/tb.cpp src/bram.cpp src/ddr.cpp \
      src/dma.cpp src/sys_bus.cpp src/cosim/ncc_target_rtl.cpp \
      src/vhdl/ncc_pkg.vhd src/vhdl/ncc_core.vhd \
      -top tb_top
  ```

  (`-top` ime proveri u `sc_main.cpp` — koji je SC_MODULE_EXPORT ili
  `sc_main()` ulazna tačka; ako `sc_main.cpp` već ima `int sc_main(...)`, flag
  `-sc_main` je ispravan izbor kao u PDF primeru, ne treba `-top`.)

- [x] **Korak 2: Pokreni sa istim test podacima kao Korak 4**

  Uveri se da `tb.cpp` učitava `board2.txt` + `Crnitoptemplate.txt` (ili već
  pripremljeni `seg90.txt`/`crnitop.txt`) na isti način kao za čisto-SystemC
  golden test — nema novih test podataka, cilj je **isti ulaz, isti izlaz,
  drugačiji mehanizam računanja**.

- [x] **Korak 3: Uporedi izlaz sa golden vrednošću**

  Očekivano: `result_map[956] == 0x80000000` (indeks `(u=32, v=14)` u 66×76
  mapi), identično Koraku 1 (C kernel), Koraku 4 (samostalni VHDL testbench) i
  Koraku 9 (ploča). Ako se ne poklapa, prvo posumnjaj na transaktor (Task 3),
  ne na `ncc_core.vhd` — jezgro je nezavisno verifikovano četiri puta pre ovog
  taska.

- [x] **Korak 4: Zapiši rezultat u vault**

  Dopuni `(C) Sljedeća sesija.md` sa ishodom (prošlo/nije prošlo, tačna
  Xcelium komanda, verzija alata) — ovaj plan ostaje kao trajna referenca za
  ponovno pokretanje.

---

## Nalazi sa fakultetske mašine

> **Task 1 ZAVRŠEN 2026-09-01, mašina `ws2` (CentOS).** Xcelium na ovoj mašini
> ume mešovitu VHDL + SystemC simulaciju, uključujući VHDL-2008. Nastavlja se
> na Task 2.

### Okruženje

| | |
|---|---|
| Podizanje okruženja | **`. amsgo`** (sa tačkom — `source`, ne `./amsgo`) |
| `xmsc_run` | `/eda/cadence/2019-20/RHELx86/XCELIUM_19.03.013/tools/bin/xmsc_run` |
| Verzija | **Xcelium 19.03-s013** (`xmvhdl(64): 19.03-s013`) |
| Radni folder | `~/xcelium_smoke` na `ws2` (`/nethome/stefan.lakic/`) |

⚠️ **Mašina nema izlaz na internet** — DNS radi (vraća samo IPv6), ali i IPv4 i
IPv6 saobraćaj su blokirani. Prenos fajlova ide **klipbordom kroz remote sesiju**,
i to u komadima do ~100 linija: paste od 283 linije je bio presečen na pola
heredoc bloka (ostalo `cat > s`, pa je `cat` tiho gutao sve dalje kucano).

### Tačne komande (provereno)

```bash
. amsgo                                   # okruzenje
cd ~/xcelium_smoke

# Verilog (Listing 2.1) -- prosao
xmsc_run -sc_main tb.cpp counter.v

# VHDL-93 -- prosao
xmsc_run -sc_main -v93 tb.cpp counter.vhd

# VHDL-2008 -- prosao, OVO NAM TREBA za ncc_core.vhd
xmsc_run -sc_main -xmvhdl_args,-v200x tb.cpp counter.vhd
```

Sva tri daju **identičan izlaz**: brojač do `dout = 207` u 1695 ns, `sc_stop()`
u 1700 ns.

### Četiri stvari koje PDF ne pominje, a zaustavljaju

1. **`.vhd` se prepoznaje po ekstenziji** — `xmsc_run` sam pozove `xmvhdl`, ne
   treba poseban fleg za tip fajla. PDF ima samo Verilog primere, pa je ovo bilo
   otvoreno pitanje; nije problem.
2. **Podrazumevani VHDL dijalekt je 87** — bez fleg­a puca na `end entity` /
   `end architecture`:
   `*E,OPENTI: Optional end entity is only allowed in 93`.
3. **`-v200x` NIJE fleg `xmsc_run`-a** — `*E,TBILLARG: Argument -v200x is not
   recognized`. `xmsc_run` prima samo `-V93` direktno; sve ostalo za VHDL ide
   kroz **`-xmvhdl_args,<arg>`** (nađeno u `xmsc_run -help`).
   **`process (all)` je eksplicitno testiran i prolazi** — ubačen u brojač
   umesto `process (clk)` pre pokretanja, jer je to jedini 2008 konstrukt zbog
   koga nam `-v200x` i treba (`ncc_core.vhd:258`).
4. **Radna biblioteka se mora čistiti između jezika** — ako `counter.v` i
   `counter.vhd` odu u istu `worklib`, elaboracija pada sa
   `*F,CUSCMU: More than one unit matches 'counter'`. Rešenje:
   `rm -rf xcelium.d INCA_libs *.log *.history` pre svakog pokretanja koje menja
   jezik. Za Task 5 nije bitno (samo VHDL), ali jeste dok se eksperimentiše.

### Mapiranje tipova SystemC ↔ VHDL — SVE POTVRĐENO MERENJEM (2026-09-01)

Ovo je bilo otvoreno pitanje br. 1 i br. 2 ispod; razrešeno je sa dva mala
testa (`intport.vhd`, `typeprobe.vhd`) umesto da se otkriva na jezgru sa 17
portova. **Nijedan VHDL adapter nije potreban — `ncc_core.vhd` ide nepromenjen.**

| VHDL port | SystemC tip u omotaču | potvrda |
|---|---|---|
| `std_logic` (ulaz takta) | `sc_in<bool>` | brojač + typeprobe |
| `std_logic` (ostalo) | `sc_in<sc_logic>` / `sc_out<sc_logic>` | typeprobe |
| `unsigned(7 downto 0)` — `dim_t`, `pixel_t` | `sc_uint<8>` | typeprobe |
| `integer range 0 to N-1` — sve tri adrese | `sc_uint<32>` | intport + typeprobe |
| `unsigned(31 downto 0)` — `result_t` | `sc_uint<32>` | typeprobe |

⚠️ **Test je namerno postavljen tako da hvata i ULAZNE portove.** `typeprobe`
računa `res <= resize(dim,32) + a`, pa ispis `res = 100 + addr` dokazuje da je
ulazni `unsigned` stvarno stigao u VHDL. Da smo gledali samo izlaze, port koji
tiho ostaje nula izgledao bi ispravno.

### Fajlovi

Smoke test je u repou: `src/cosim/smoke/`

| fajl | šta dokazuje |
|---|---|
| `counter.v`, `counter.vhd`, `tb.cpp` | Verilog i VHDL kosimulacija rade (Listinzi 2.1–2.5, `tb.cpp` je 2.2–2.5 spojeno radi prenosa klipbordom) |
| `counter.hpp`, `tb_counter.hpp/.cpp`, `sc_main.cpp` | ista stvar u podeljenoj verziji, tačno kako stoji u PDF-u |
| `intport.vhd`, `tb_int.cpp` | `integer range` → `sc_uint<32>` |
| `typeprobe.vhd`, `tb_probe.cpp` | svi tipovi koje `ncc_core` koristi, u oba smera |
| `setup.sh` | pravi ceo `~/xcelium_smoke/` jednim pozivom (za mašinu sa internetom) |

## Izmena arhitekture posle Taska 1 (2026-09-02)

Plan je pisan pod dve pretpostavke koje kod ne potvrđuje:

1. **`vp.cpp` instancira DVA NCC bloka** (`ncc0`, `ncc1`), ne jedan. `#ifdef`
   zamena tipa bi zamenila oba.
2. **Pun `tb.cpp` prolaz kroz RTL nije izvodiv** — 64 polja × 12 šablona, a jedan
   prolaz 90×90/25×15 je već ~3,8M taktova.

Zato Task 3/4 idu **side-by-side** umesto zamene: `ncc0` ostaje C++ ESL model,
`ncc1` je `NCC_Target_RTL`, oba čitaju **isti** BRAM, startuju u istom trenutku i
porede se **unutar jedne simulacije**. To je i jači odgovor na profesorovu
primedbu — zamena bi i dalje značila dva odvojena run-a.

`vp.cpp`/`vp.hpp` se **ne diraju**; kosimulacija ima sopstveni, manji top
(`sc_main_cosim.cpp`) koji veže samo `bram + ncc0 + ncc1`, bez
`sys_bus`/`dma`/`ddr`. Manje fajlova za prenos klipbordom na ws2.

### Šta se tvrdi, a šta ne

Cela mapa **neće** biti bit-identična: `ncc.cpp` deli u `double`
(`double ncc2 = num_sq/den_prod`), RTL celobrojnim `seq_divider`-om. Van vrha se
najniži bitovi razilaze po konstrukciji. Test zato **tvrdo** proverava samo vrh
(`0x80000000 @ (u=32,v=14)` kod oba bloka), a razlike po mapi **meri i ispisuje**
(broj identičnih pozicija, najveće odstupanje). Tvrdnja koja bi pukla nije dokaz.

### Ispravka plana koju je smoke test rešio merenjem

Task 2 je u planu imao kontradikciju: `busy`/`done` kao `sc_out`, ali
`result_data_o`/`result_wr_o` kao `sc_in` — a sva četiri su VHDL `out`.
`typeprobe.vhd` (`addr`/`res`/`wr` su `out`) u `tb_probe.cpp` ima **sve kao
`sc_out`** i čita ih ispravno. Važi: **VHDL `out` → `sc_out`, bez izuzetka.**
Takođe, smoke verzija **ne zove** `elaborate_foreign_module()` — ne "popravljati"
po PDF-u.

### Napisani fajlovi (2026-09-02, na Windows mašini, još neprevedeni)

| fajl | šta je |
|---|---|
| `src/cosim/ncc_core_wrap.hpp` | Task 2 — `sc_foreign_module` omotač, 17 portova |
| `src/cosim/ncc_target_rtl.hpp/.cpp` | Task 3 — transaktor, isti TLM interfejs kao `NCC_Target` |
| `src/cosim/sc_main_cosim.cpp` | Task 5 — top: BRAM + ncc0 (ESL) + ncc1 (RTL) + poređenje |
| `src/cosim/run_cosim.sh` | `xmsc_run` poziv + provera md5/CRLF pre pokretanja |
| `src/cosim/seg90.hex`, `crnitop.hex` | isti pikseli kao `src/vhdl/tb/*.txt`, u heksu (90 i 15 linija umesto 8100 i 375 — zbog prenosa klipbordom) |
| `src/cosim/PRENOS_NA_WS2.txt` | svi fajlovi u jednom dokumentu + kontrolna tabela md5 |

⚠️ **Ništa od ovoga nije prevedeno** — na Windows mašini nema SystemC
biblioteke. Prva prava kapija je `./run_cosim.sh` na ws2.

Komanda (iz Taska 1, sa `-v200x` kroz `-xmvhdl_args`):

```bash
xmsc_run -sc_main -xmvhdl_args,-v200x     sc_main_cosim.cpp ncc_target_rtl.cpp ncc.cpp bram.cpp     ncc_pkg.vhd ncc_core.vhd
```

---

---

## ISHOD: KOSIMULACIJA PROŠLA (2026-09-04, `ws1`)

**Taskovi 2-5 završeni. `run_cosim.sh` prolazi od kraja do kraja.**

```
=== MESOVITA SIMULACIJA: SystemC ESL (ncc0) vs VHDL RTL (ncc1) ===
Ucitano: segment 90x90, sablon 25x15
Start oba bloka @ 0 s ...
Oba bloka javila done @ 58221970 ns

--- REZULTAT ---
ESL (ncc0): best = 0x80000000  @ (u=32, v=14)
RTL (ncc1): best = 0x80000000  @ (u=32, v=14)   busy taktova = 2461201
Mapa 66x76 = 5016 pozicija: 5016 bit-identicnih (100 %)

GOLDEN OK: ESL i RTL daju isti vrh 0x80000000 @ (32,14) u JEDNOJ
zajednickoj simulaciji.
```

### Jedina greška prevođenja — nedostajao `SC_INCLUDE_DYNAMIC_PROCESSES`

Prvo pokretanje palo je sa 12 grešaka u **Cadence-ovom** `tlm_utils/simple_target_socket.h`,
ne u našem kodu:

```
error: namespace "sc_core" has no member "sc_spawn"
error: incomplete type is not allowed        <- sc_core::sc_spawn_options opts;
error: identifier "sc_bind" is undefined
error: identifier "sc_ref" is undefined
```

`simple_target_socket` iznutra pravi dinamičke procese (`sc_spawn` u `b2nb_thread`/
`nb2b_thread`), a SystemC te simbole otkriva **samo** ako je
`SC_INCLUDE_DYNAMIC_PROCESSES` definisan **pre** `#include <systemc>`.
Rešenje je jedna linija u `src/common.hpp` (prvi include u svakoj jedinici
prevođenja, pa pokriva sva četiri `.cpp`):

```cpp
#define SC_INCLUDE_DYNAMIC_PROCESSES   // tlm_utils socketi iznutra zovu sc_spawn/sc_bind
#define SC_INCLUDE_FX
#include <systemc>
```

Ovo je nedostajalo i u originalnom `src/common.hpp` — g++ build na Windows/Linux
mašini je prolazio jer tamošnji SystemC ne gejtuje `sc_spawn` istim `#ifdef`-om.

### Mapa je ispala 100 % identična — jače nego što je plan tvrdio

Plan je (sekcija „Šta se tvrdi, a šta ne") predviđao da cela mapa **neće** biti
bit-identična, jer `ncc.cpp` deli u `double`, a RTL celobrojnim `seq_divider`-om;
zato je poređenje pisano da razlike **meri**, a tvrdo proverava samo vrh.
Izmereno: **5016/5016**, grana koja ispisuje `Najvece odstupanje` se nije ni
aktivirala. Deljenje u `double` na Q31 skali pada na isti ceo broj kao RTL na
svakoj poziciji.

Poređenje nije artefakt: `m0` i `m1` su dve odvojene mape, pročitane preko dva
odvojena TLM socketa (`map_read(i_ncc0, m0)` / `map_read(i_ncc1, m1)`).

### Ostali brojevi

| | |
|---|---|
| Mašina | `ws1` (ne `ws2` — radi na obe) |
| Radni folder | `~/ncc_cosim` |
| RTL busy taktova | **2 461 201** (plan je procenjivao ~3,8M — procena je bila gornja granica) |
| Sim vreme do `done` | 58 221 970 ns |
| Trajanje bez `-gui` | prihvatljivo, GUI nije bio potreban |

### Zamke koje su se stvarno pojavile (pored onih iz Taska 1)

1. **`SC_INCLUDE_DYNAMIC_PROCESSES`** — gore, jedina prava greška.
2. **Clock skew na `nethome`** — `make: Warning: File has modification time N s in
   the future` + `xmls: *W: creation time ... is earlier than last modification
   time`. NFS-ov sat ne prati lokalni; **bezopasno**, build je i dalje ispravan.
   Ne gubiti vreme na to.
3. Prenos je prošao iz prve — md5 kapija je pokazala 14/14 OK. Redni brojevi u
   imenima (`01_`, `02_`...) se brišu pri snimanju, `.txt` ekstenzija takođe.

## Otvorena pitanja / rizici

1. ~~**Mapiranje VHDL `integer` porta na SystemC tip**~~ — **RAZREŠENO
   2026-09-01 merenjem.** `integer range 0 to N-1` se veže na `sc_uint<32>`
   bez ikakve konverzije; isto tako `unsigned(7/31 downto 0)` na
   `sc_uint<8>`/`sc_uint<32>`. Tabela je u Nalazima iznad. Adapter u VHDL-u
   nije potreban.
2. **Takt generator u dva mesta** — `NCC_Target_RTL::drive_clock()` pravi
   sopstveni 100 MHz takt nezavisno od bilo kog takta u `sc_main.cpp`. Ako
   ostatak ESL modela već ima globalni `sc_clock`, razmotriti deljenje istog
   umesto novog — jednostavnije za rezonovanje o vremenu, ali menja više
   fajlova van `src/cosim/`.
3. **Trajanje simulacije** — pun 90×90/25×15 prolaz je ~3,8M taktova RTL-a
   (izmereno u Koraku 5/8). Kroz Xcelium GUI (`-gui` flag iz PDF primera) ovo
   može biti sporo za interaktivan rad; razmotriti bez `-gui` za pun prolaz, a
   sa `-gui` samo za debug na malom testu (npr. 4×4/2×2 golden iz
   `ncc_core_tb.vhd`, brže za prvu proveru da transaktor uopšte radi).
