-- Testbench za ncc_core (Korak 3/4, TDD). Isti golden slucaj (4x4/2x2) kao
-- src/hls/test_ncc_kernel.cpp (test_small_4x4).
--
-- v2 (2026-07-20): ncc_core sada ima adresirane BRAM-stil portove umesto punih
-- nizova -- testbench simulira 3 spoljne sinhrone memorije (image_mem, templ_mem,
-- result_mem) sa 1-taktnim kasnjenjem citanja, tacno kao stvarni BRAM (adresa
-- ovaj takt -> podatak sledeci takt), po obrascu iz Vezbe 3-5.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.ncc_pkg.all;

entity ncc_core_tb is
end entity;

architecture sim of ncc_core_tb is

    constant CLK_PERIOD : time := 10 ns;

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

    -- Spoljne memorije (u pravom sistemu: deljeni BRAM). Testbench ih puni
    -- pre starta -- isti princip kao dual-port memorija u Vezbi 3-5.
    signal image_mem  : image_array_t := (others => (others => '0'));
    signal templ_mem  : templ_array_t := (others => (others => '0'));
    signal result_mem : resultmap_array_t := (others => (others => '0'));

    signal sim_done : boolean := false;

    type golden_array_t is array (0 to 8) of unsigned(31 downto 0);
    constant GOLDEN : golden_array_t := (
        0 => x"00000000", 1 => x"14071EF9", 2 => x"3BACAAE6",
        3 => x"1BA5B12C", 4 => x"80000000", 5 => x"01E3DBE0",
        6 => x"2D8A826C", 7 => x"00CE9343", 8 => x"0022EF14"
    );

begin

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

    -- Sinhrone "spoljne memorije": adresa se cita OVOG takta, podatak/upis se
    -- desava na IVICI takta -- isto kasnjenje kao pravi single-port BRAM.
    mem_model : process (clk)
    begin
        if rising_edge(clk) then
            img_data   <= image_mem(img_addr);
            templ_data <= templ_mem(templ_addr);
            if result_wr = '1' then
                result_mem(result_addr) <= result_data;
            end if;
        end if;
    end process mem_model;

    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    stim_gen : process
        variable fails : integer := 0;
        variable idx   : integer;
        variable exp   : unsigned(31 downto 0);
        variable act   : unsigned(31 downto 0);
    begin
        rst <= '1';
        wait for CLK_PERIOD * 3;
        rst <= '0';
        wait until rising_edge(clk);

        -- 4x4 slika / 2x2 sablon, isti golden slucaj kao Korak 1
        image_mem(0)  <= to_unsigned(10, 8);  image_mem(1)  <= to_unsigned(50, 8);
        image_mem(2)  <= to_unsigned(20, 8);  image_mem(3)  <= to_unsigned(80, 8);
        image_mem(4)  <= to_unsigned(60, 8);  image_mem(5)  <= to_unsigned(90, 8);
        image_mem(6)  <= to_unsigned(30, 8);  image_mem(7)  <= to_unsigned(10, 8);
        image_mem(8)  <= to_unsigned(40, 8);  image_mem(9)  <= to_unsigned(20, 8);
        image_mem(10) <= to_unsigned(100,8);  image_mem(11) <= to_unsigned(70, 8);
        image_mem(12) <= to_unsigned(90, 8);  image_mem(13) <= to_unsigned(10, 8);
        image_mem(14) <= to_unsigned(60, 8);  image_mem(15) <= to_unsigned(40, 8);

        templ_mem(0) <= to_unsigned(90, 8);  templ_mem(1) <= to_unsigned(30, 8);
        templ_mem(2) <= to_unsigned(20, 8);  templ_mem(3) <= to_unsigned(100,8);

        img_w <= to_unsigned(4, 8);
        img_h <= to_unsigned(4, 8);
        tmp_w <= to_unsigned(2, 8);
        tmp_h <= to_unsigned(2, 8);

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        wait until done = '1';
        wait until rising_edge(clk);

        for v in 0 to 2 loop
            for u in 0 to 2 loop
                idx := v * 3 + u;
                exp := GOLDEN(idx);
                act := result_mem(idx);
                if act /= exp then
                    report "[FAIL] u=" & integer'image(u) & " v=" & integer'image(v) &
                           " expected=0x" & to_hstring(std_logic_vector(exp)) &
                           " actual=0x" & to_hstring(std_logic_vector(act))
                        severity error;
                    fails := fails + 1;
                else
                    report "[ OK ] u=" & integer'image(u) & " v=" & integer'image(v) &
                           " = 0x" & to_hstring(std_logic_vector(act));
                end if;
            end loop;
        end loop;

        if fails = 0 then
            report "SVI TESTOVI PROSLI";
        else
            report integer'image(fails) & " TEST(OVA) PALO" severity error;
        end if;

        sim_done <= true;
        wait for CLK_PERIOD;
        std.env.finish;
    end process;

end architecture sim;
