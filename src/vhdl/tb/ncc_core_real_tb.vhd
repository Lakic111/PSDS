-- Real-data testbench za ncc_core (Korak 4): gornji-levi 90x90 segment iz
-- board2.txt (= polje (0,0) sahovske table) + crni top sablon 25x15 iz
-- Crnitoptemplate.txt. Podaci se ucitavaju iz tb/seg90.txt i tb/crnitop.txt
-- (jedan piksel po liniji, row-major) -- generisano iz src/hls/data/data/.
--
-- Golden (iz VALIDIRANOG ncc_kernel-a, Korak 1, bit-tacan):
--   peak = 0x80000000 (NCC^2 = 1.0)  @ (u=32, v=14)  => MATCH crni top.
-- Ocekivano jer zvanicni FEN kaze da je polje (0,0) = 'r' (crni top).
--
-- Isti sinhroni memorijski modeli (1-takt kasnjenje citanja) kao ncc_core_tb.vhd,
-- samo puni 90x90 / 25x15 umesto sintetickog 4x4/2x2.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.ncc_pkg.all;

entity ncc_core_real_tb is
end entity;

architecture sim of ncc_core_real_tb is

    constant CLK_PERIOD : time := 10 ns;

    constant IW    : integer := 90;
    constant IH    : integer := 90;
    constant TW    : integer := 25;
    constant TH    : integer := 15;
    constant RES_W : integer := IW - TW + 1;   -- 66
    constant RES_H : integer := IH - TH + 1;   -- 76

    constant SEG_FILE  : string := "C:/Users/pc/Desktop/PSDS/src/vhdl/tb/seg90.txt";
    constant TMPL_FILE : string := "C:/Users/pc/Desktop/PSDS/src/vhdl/tb/crnitop.txt";

    constant GOLDEN_BEST : unsigned(31 downto 0) := x"80000000";  -- NCC^2 = 1.0
    constant THRESH_Q31  : unsigned(31 downto 0) := x"48000000";  -- 0.5625 * 2^31

    signal clk    : std_logic := '0';
    signal rst    : std_logic := '1';
    signal start  : std_logic := '0';
    signal busy   : std_logic;
    signal done   : std_logic;
    signal img_w  : dim_t := (others => '0');
    signal img_h  : dim_t := (others => '0');
    signal tmp_w  : dim_t := (others => '0');
    signal tmp_h  : dim_t := (others => '0');

    signal img_addr    : integer range 0 to MAX_IMG_PIX - 1 := 0;
    signal img_data    : pixel_t := (others => '0');
    signal templ_addr  : integer range 0 to MAX_TMP_PIX - 1 := 0;
    signal templ_data  : pixel_t := (others => '0');
    signal result_addr : integer range 0 to MAX_IMG_PIX - 1 := 0;
    signal result_data : result_t := (others => '0');
    signal result_wr   : std_logic := '0';

    signal image_mem  : image_array_t     := (others => (others => '0'));
    signal templ_mem  : templ_array_t     := (others => (others => '0'));
    signal result_mem : resultmap_array_t := (others => (others => '0'));

    signal sim_done    : boolean := false;
    signal busy_cycles : integer := 0;

begin

    -- Broj aktivnih taktova akceleratora (busy='1') -- throughput metrika.
    cyc_cnt : process (clk)
    begin
        if rising_edge(clk) then
            if busy = '1' then
                busy_cycles <= busy_cycles + 1;
            end if;
        end if;
    end process cyc_cnt;

    dut : entity work.ncc_core
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            busy          => busy,
            done          => done,
            img_w         => img_w,
            img_h         => img_h,
            tmp_w         => tmp_w,
            tmp_h         => tmp_h,
            img_addr_o    => img_addr,
            img_data_i    => img_data,
            templ_addr_o  => templ_addr,
            templ_data_i  => templ_data,
            result_addr_o => result_addr,
            result_data_o => result_data,
            result_wr_o   => result_wr
        );

    -- Sinhrone spoljne memorije (single-port BRAM model): adresa ovog takta ->
    -- podatak/upis na ivici takta.
    mem_model : process (clk)
    begin
        if rising_edge(clk) then
            img_data   <= image_mem(img_addr);
            templ_data <= templ_mem(templ_addr);
            if result_wr = '1' then
                result_mem(result_addr) <= result_data;
            end if;
        end if;
    end process;

    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    -- Watchdog: pun 90x90/25x15 prolaz je ~3.8M taktova (~38 ms sim vremena);
    -- ako done ne stigne do 100 ms, nesto je zaglavilo.
    watchdog : process
    begin
        wait for 100 ms;
        report "WATCHDOG: done nije stigao -- FSM verovatno zaglavljen" severity failure;
    end process;

    stim_gen : process
        file fseg  : text;
        file ftmpl : text;
        variable l : line;
        variable v : integer;
        variable img_v  : image_array_t := (others => (others => '0'));
        variable tmpl_v : templ_array_t := (others => (others => '0'));
        variable best   : unsigned(31 downto 0);
        variable s      : unsigned(31 downto 0);
        variable bu, bv : integer;
        variable ratio_x1024 : integer;
    begin
        -- Ucitaj segment i sablon iz fajlova (jedan piksel po liniji, row-major).
        file_open(fseg, SEG_FILE, read_mode);
        for i in 0 to IW * IH - 1 loop
            readline(fseg, l); read(l, v);
            img_v(i) := to_unsigned(v, 8);
        end loop;
        file_close(fseg);

        file_open(ftmpl, TMPL_FILE, read_mode);
        for i in 0 to TW * TH - 1 loop
            readline(ftmpl, l); read(l, v);
            tmpl_v(i) := to_unsigned(v, 8);
        end loop;
        file_close(ftmpl);

        image_mem <= img_v;
        templ_mem <= tmpl_v;

        img_w <= to_unsigned(IW, 8);
        img_h <= to_unsigned(IH, 8);
        tmp_w <= to_unsigned(TW, 8);
        tmp_h <= to_unsigned(TH, 8);

        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);   -- da image_mem/templ_mem sigurno stignu

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        report "NCC pokrenut: 90x90 segment (polje 0,0) + crni top 25x15. Cekam done...";
        wait until done = '1';
        wait until rising_edge(clk);

        report "LATENCIJA: busy taktova = " & integer'image(busy_cycles) &
               " (pipeline + sekvencijalni delilac)";

        -- Nadji maksimum NCC^2 u mapi rezultata (66x76).
        best := (others => '0'); bu := 0; bv := 0;
        for vv in 0 to RES_H - 1 loop
            for uu in 0 to RES_W - 1 loop
                s := result_mem(vv * RES_W + uu);
                if s > best then
                    best := s; bu := uu; bv := vv;
                end if;
            end loop;
        end loop;

        ratio_x1024 := to_integer(best(31 downto 21));  -- best/2^21 = NCC^2 * 1024

        report "BEST NCC^2 = 0x" & to_hstring(std_logic_vector(best)) &
               "  @ (u=" & integer'image(bu) & ", v=" & integer'image(bv) & ")";
        report "NCC^2 ~ " & integer'image(ratio_x1024) & "/1024" &
               "  (prag 576/1024 = 0.5625)";

        if best > THRESH_Q31 then
            report "=> MATCH crni top (skor iznad praga)";
        else
            report "=> NO MATCH (skor ispod praga)" severity error;
        end if;

        -- Golden provera protiv ncc_kernel-a (Korak 1): bit-tacno.
        assert best = GOLDEN_BEST
            report "GOLDEN FAIL: best ocekivano 0x80000000, dobijeno 0x" &
                   to_hstring(std_logic_vector(best)) severity error;
        assert bu = 32 and bv = 14
            report "GOLDEN FAIL: lokacija ocekivano (u=32,v=14), dobijeno (u=" &
                   integer'image(bu) & ",v=" & integer'image(bv) & ")" severity error;

        if best = GOLDEN_BEST and bu = 32 and bv = 14 then
            report "GOLDEN OK: peak 0x80000000 @ (32,14) -- bit-tacno kao C kernel";
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.finish;
    end process;

end architecture sim;
