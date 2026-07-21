-- ============================================================================
-- NCC RTL jezgro -- FINALNA verzija (Korak 5): PIPELINED petlja + SEKVENCIJALNI
-- DELIOCI, sve u JEDNOM fajlu (self-contained).
--
-- Ovaj fajl sadrzi DVA design unita:
--   1) seq_divider   -- sekvencijalni (restoring) celobrojni delilac
--   2) ncc_core      -- NCC jezgro (pipelined MAC petlja + 2x seq_divider)
-- Zato projektu treba samo ncc_pkg.vhd + ncc_core.vhd (bez zasebnog divider fajla).
--
-- Optimizacije (v_final, 2026-07-21):
--   * pipelined unutrasnja petlja (S_L_YX_FILL/RUN/DRAIN, ~1 takt/piksel)
--   * tri kombinaciona deljenja (template_mean, f_bar, NCC^2) zamenjena
--     handshake-om ka seq_divider (div_mean W=18 za mean+f_bar, div_ncc W=83)
--     -> zatvara 100 MHz timing (kombinaciono deljenje je bilo WNS -46ns).
-- Rezultat je BIT-IDENTICAN C kernelu (Korak 1): golden 0x80000000 @ (32,14) na
-- realnom 90x90 segmentu + crni top. Analiza: (C) Korak 5 dokument u vault-u.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Design unit 1: seq_divider
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seq_divider is
    generic (
        W : integer := 32
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        start     : in  std_logic;
        dividend  : in  unsigned(W - 1 downto 0);
        divisor   : in  unsigned(W - 1 downto 0);
        quotient  : out unsigned(W - 1 downto 0);
        remainder : out unsigned(W - 1 downto 0);
        busy      : out std_logic;
        done      : out std_logic
    );
end entity seq_divider;

architecture rtl of seq_divider is
    signal rem_reg  : unsigned(W - 1 downto 0) := (others => '0');
    signal work_reg : unsigned(W - 1 downto 0) := (others => '0');
    signal div_reg  : unsigned(W - 1 downto 0) := (others => '0');
    signal cnt      : integer range 0 to W := 0;
    signal busy_s   : std_logic := '0';
    signal done_s   : std_logic := '0';
begin
    process (clk)
        variable sh : unsigned(W downto 0);
    begin
        if rising_edge(clk) then
            done_s <= '0';
            if rst = '1' then
                busy_s   <= '0';
                cnt      <= 0;
                rem_reg  <= (others => '0');
                work_reg <= (others => '0');
            elsif start = '1' and busy_s = '0' then
                rem_reg  <= (others => '0');
                work_reg <= dividend;
                div_reg  <= divisor;
                cnt      <= W;
                busy_s   <= '1';
            elsif busy_s = '1' then
                sh := rem_reg & work_reg(W - 1);
                if sh >= ('0' & div_reg) then
                    rem_reg  <= resize(sh - ('0' & div_reg), W);
                    work_reg <= work_reg(W - 2 downto 0) & '1';
                else
                    rem_reg  <= resize(sh, W);
                    work_reg <= work_reg(W - 2 downto 0) & '0';
                end if;
                cnt <= cnt - 1;
                if cnt = 1 then
                    busy_s <= '0';
                    done_s <= '1';
                end if;
            end if;
        end if;
    end process;

    quotient  <= work_reg;
    remainder <= rem_reg;
    busy      <= busy_s;
    done      <= done_s;
end architecture rtl;


-- ---------------------------------------------------------------------------
-- Design unit 2: ncc_core (pipelined + delioci)
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ncc_pkg.all;

entity ncc_core is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;
        busy       : out std_logic;
        done       : out std_logic;
        img_w      : in  dim_t;
        img_h      : in  dim_t;
        tmp_w      : in  dim_t;
        tmp_h      : in  dim_t;

        img_addr_o    : out integer range 0 to MAX_IMG_PIX - 1;
        img_data_i    : in  pixel_t;
        templ_addr_o  : out integer range 0 to MAX_TMP_PIX - 1;
        templ_data_i  : in  pixel_t;
        result_addr_o : out integer range 0 to MAX_IMG_PIX - 1;
        result_data_o : out result_t;
        result_wr_o   : out std_logic
    );
end entity ncc_core;

architecture rtl of ncc_core is

    type state_t is (S_IDLE,
                      S_LOAD_IMG_ADDR, S_LOAD_IMG_DATA,
                      S_LOAD_TMPL_ADDR, S_LOAD_TMPL_DATA,
                      S_CALC_MEAN, S_CALC_MEAN_WAIT,
                      S_L_V,
                      S_L_U_A, S_L_U_B, S_L_U_C, S_L_U_D, S_L_U_E, S_L_U_WAIT,
                      S_L_YX_FILL, S_L_YX_RUN, S_L_YX_DRAIN,
                      S_NCC_DIV, S_NCC_WAIT,
                      S_WRITE_RESULT, S_DONE);

    signal state_reg, state_next : state_t := S_IDLE;

    signal img_w_reg, img_w_next, img_h_reg, img_h_next : integer range 0 to MAX_IMG_W := 0;
    signal tmp_w_reg, tmp_w_next, tmp_h_reg, tmp_h_next : integer range 0 to MAX_IMG_W := 0;
    signal res_w_reg, res_w_next, res_h_reg, res_h_next : integer range 0 to MAX_IMG_W := 0;
    signal y_reg, y_next, x_reg, x_next                 : integer range 0 to MAX_IMG_W := 0;
    signal v_reg, v_next, u_reg, u_next                 : integer range 0 to MAX_IMG_W := 0;
    signal p_reg, p_next                                : integer range 0 to MAX_TMP_PIX := 0;

    signal row_sum_reg, row_sum_next             : sat_t := (others => '0');
    signal sum_t_reg, sum_t_next                 : sat_t := (others => '0');
    signal f_bar_reg, f_bar_next                 : mean_t := (others => '0');
    signal template_mean_reg, template_mean_next : mean_t := (others => '0');
    signal sum_num_reg, sum_num_next             : numacc_t := (others => '0');
    signal sum_den_f_reg, sum_den_f_next         : denacc_t := (others => '0');
    signal sum_den_t_reg, sum_den_t_next         : denacc_t := (others => '0');
    signal busy_reg, busy_next                   : std_logic := '0';
    signal done_reg, done_next                   : std_logic := '0';
    signal sum_f_partial_reg, sum_f_partial_next : sat_t := (others => '0');
    signal result_q_reg, result_q_next           : result_t := (others => '0');

    signal sat_mem     : sat_mem_t := (others => (others => '0'));
    signal sat_wr_en   : std_logic := '0';
    signal sat_wr_addr : integer range 0 to SAT_SIZE - 1 := 0;
    signal sat_wr_data : sat_t := (others => '0');
    signal sat_rd_addr : integer range 0 to SAT_SIZE - 1 := 0;
    signal sat_rd_data : sat_t := (others => '0');

    constant DM_W : integer := 18;   -- template_mean / f_bar
    constant DN_W : integer := 83;   -- NCC^2: num_sq(52) << 31
    signal dm_start, dm_done                 : std_logic := '0';
    signal dm_dividend, dm_divisor, dm_quot  : unsigned(DM_W - 1 downto 0) := (others => '0');
    signal dn_start, dn_done                 : std_logic := '0';
    signal dn_dividend, dn_divisor, dn_quot  : unsigned(DN_W - 1 downto 0) := (others => '0');

begin

    busy <= busy_reg;
    done <= done_reg;

    div_mean : entity work.seq_divider
        generic map (W => DM_W)
        port map (clk => clk, rst => rst, start => dm_start,
                  dividend => dm_dividend, divisor => dm_divisor,
                  quotient => dm_quot, remainder => open, busy => open, done => dm_done);

    div_ncc : entity work.seq_divider
        generic map (W => DN_W)
        port map (clk => clk, rst => rst, start => dn_start,
                  dividend => dn_dividend, divisor => dn_divisor,
                  quotient => dn_quot, remainder => open, busy => open, done => dn_done);

    -- PROCES 1: registri
    reg_proc : process (clk, rst)
    begin
        if rst = '1' then
            state_reg <= S_IDLE;
            img_w_reg <= 0; img_h_reg <= 0; tmp_w_reg <= 0; tmp_h_reg <= 0;
            res_w_reg <= 0; res_h_reg <= 0;
            y_reg <= 0; x_reg <= 0; v_reg <= 0; u_reg <= 0; p_reg <= 0;
            row_sum_reg <= (others => '0');
            sum_t_reg <= (others => '0');
            f_bar_reg <= (others => '0');
            template_mean_reg <= (others => '0');
            sum_num_reg <= (others => '0');
            sum_den_f_reg <= (others => '0');
            sum_den_t_reg <= (others => '0');
            busy_reg <= '0';
            done_reg <= '0';
            sum_f_partial_reg <= (others => '0');
            result_q_reg <= (others => '0');
        elsif rising_edge(clk) then
            state_reg <= state_next;
            img_w_reg <= img_w_next; img_h_reg <= img_h_next;
            tmp_w_reg <= tmp_w_next; tmp_h_reg <= tmp_h_next;
            res_w_reg <= res_w_next; res_h_reg <= res_h_next;
            y_reg <= y_next; x_reg <= x_next; v_reg <= v_next; u_reg <= u_next; p_reg <= p_next;
            row_sum_reg <= row_sum_next;
            sum_t_reg <= sum_t_next;
            f_bar_reg <= f_bar_next;
            template_mean_reg <= template_mean_next;
            sum_num_reg <= sum_num_next;
            sum_den_f_reg <= sum_den_f_next;
            sum_den_t_reg <= sum_den_t_next;
            busy_reg <= busy_next;
            done_reg <= done_next;
            sum_f_partial_reg <= sum_f_partial_next;
            result_q_reg <= result_q_next;
        end if;
    end process reg_proc;

    -- PROCES 3: sat_mem (BRAM) izolovana
    sat_ram_proc : process (clk)
    begin
        if rising_edge(clk) then
            if sat_wr_en = '1' then
                sat_mem(sat_wr_addr) <= sat_wr_data;
            end if;
            sat_rd_data <= sat_mem(sat_rd_addr);
        end if;
    end process sat_ram_proc;

    -- PROCES 2: kombinaciona logika
    comb_proc : process (all)
        variable count       : integer range 0 to MAX_TMP_PIX;
        variable df, dt      : diff_t;
        variable num_sq_v    : unsigned(51 downto 0);
        variable den_prod_v  : unsigned(51 downto 0);
        variable new_row_sum : sat_t;
    begin
        state_next <= state_reg;
        img_w_next <= img_w_reg; img_h_next <= img_h_reg;
        tmp_w_next <= tmp_w_reg; tmp_h_next <= tmp_h_reg;
        res_w_next <= res_w_reg; res_h_next <= res_h_reg;
        y_next <= y_reg; x_next <= x_reg; v_next <= v_reg; u_next <= u_reg; p_next <= p_reg;
        row_sum_next <= row_sum_reg;
        sum_t_next <= sum_t_reg;
        f_bar_next <= f_bar_reg;
        template_mean_next <= template_mean_reg;
        sum_num_next <= sum_num_reg;
        sum_den_f_next <= sum_den_f_reg;
        sum_den_t_next <= sum_den_t_reg;
        busy_next <= busy_reg;
        done_next <= '0';
        sum_f_partial_next <= sum_f_partial_reg;
        result_q_next <= result_q_reg;

        sat_wr_en <= '0'; sat_wr_addr <= 0; sat_wr_data <= (others => '0');
        sat_rd_addr <= 0;

        img_addr_o    <= 0;
        templ_addr_o  <= 0;
        result_addr_o <= 0;
        result_data_o <= (others => '0');
        result_wr_o   <= '0';

        dm_start <= '0'; dm_dividend <= (others => '0'); dm_divisor <= (others => '0');
        dn_start <= '0'; dn_dividend <= (others => '0'); dn_divisor <= (others => '0');

        case state_reg is

            when S_IDLE =>
                if start = '1' then
                    img_w_next <= to_integer(img_w);
                    img_h_next <= to_integer(img_h);
                    tmp_w_next <= to_integer(tmp_w);
                    tmp_h_next <= to_integer(tmp_h);
                    res_w_next <= to_integer(img_w) - to_integer(tmp_w) + 1;
                    res_h_next <= to_integer(img_h) - to_integer(tmp_h) + 1;
                    y_next <= 0; x_next <= 0;
                    row_sum_next <= (others => '0');
                    busy_next <= '1';
                    state_next <= S_LOAD_IMG_ADDR;
                end if;

            when S_LOAD_IMG_ADDR =>
                img_addr_o  <= y_reg * img_w_reg + x_reg;
                sat_rd_addr <= y_reg * SAT_W + (x_reg + 1);
                state_next <= S_LOAD_IMG_DATA;

            when S_LOAD_IMG_DATA =>
                if x_reg = 0 then
                    new_row_sum := resize(img_data_i, 32);
                else
                    new_row_sum := row_sum_reg + resize(img_data_i, 32);
                end if;
                sat_wr_en   <= '1';
                sat_wr_addr <= (y_reg + 1) * SAT_W + (x_reg + 1);
                sat_wr_data <= sat_rd_data + new_row_sum;
                row_sum_next <= new_row_sum;

                if x_reg + 1 < img_w_reg then
                    x_next <= x_reg + 1;
                    state_next <= S_LOAD_IMG_ADDR;
                elsif y_reg + 1 < img_h_reg then
                    x_next <= 0; y_next <= y_reg + 1;
                    state_next <= S_LOAD_IMG_ADDR;
                else
                    p_next <= 0;
                    sum_t_next <= (others => '0');
                    state_next <= S_LOAD_TMPL_ADDR;
                end if;

            when S_LOAD_TMPL_ADDR =>
                templ_addr_o <= p_reg;
                state_next <= S_LOAD_TMPL_DATA;

            when S_LOAD_TMPL_DATA =>
                sum_t_next <= sum_t_reg + resize(templ_data_i, 32);
                if p_reg + 1 < tmp_w_reg * tmp_h_reg then
                    p_next <= p_reg + 1;
                    state_next <= S_LOAD_TMPL_ADDR;
                else
                    state_next <= S_CALC_MEAN;
                end if;

            -- template_mean = (sum_t + count/2) / count  -> div_mean
            when S_CALC_MEAN =>
                count := tmp_w_reg * tmp_h_reg;
                dm_dividend <= resize(sum_t_reg + to_unsigned(count / 2, 32), DM_W);
                dm_divisor  <= to_unsigned(count, DM_W);
                dm_start    <= '1';
                state_next  <= S_CALC_MEAN_WAIT;

            when S_CALC_MEAN_WAIT =>
                if dm_done = '1' then
                    template_mean_next <= resize(dm_quot, 8);
                    v_next <= 0;
                    state_next <= S_L_V;
                end if;

            when S_L_V =>
                if v_reg < res_h_reg then
                    u_next <= 0;
                    state_next <= S_L_U_A;
                else
                    state_next <= S_DONE;
                end if;

            when S_L_U_A =>
                sat_rd_addr <= (v_reg + tmp_h_reg) * SAT_W + (u_reg + tmp_w_reg);  -- A
                state_next <= S_L_U_B;

            when S_L_U_B =>
                sum_f_partial_next <= resize(sat_rd_data, 32);  -- + A
                sat_rd_addr <= v_reg * SAT_W + (u_reg + tmp_w_reg);  -- B
                state_next <= S_L_U_C;

            when S_L_U_C =>
                sum_f_partial_next <= sum_f_partial_reg - resize(sat_rd_data, 32);  -- - B
                sat_rd_addr <= (v_reg + tmp_h_reg) * SAT_W + u_reg;  -- C
                state_next <= S_L_U_D;

            when S_L_U_D =>
                sum_f_partial_next <= sum_f_partial_reg - resize(sat_rd_data, 32);  -- - C
                sat_rd_addr <= v_reg * SAT_W + u_reg;  -- D
                state_next <= S_L_U_E;

            -- f_bar = (sum_f_partial + D + count/2) / count  -> div_mean
            when S_L_U_E =>
                count := tmp_w_reg * tmp_h_reg;
                dm_dividend <= resize(sum_f_partial_reg + resize(sat_rd_data, 32) +
                                      to_unsigned(count / 2, 32), DM_W);
                dm_divisor  <= to_unsigned(count, DM_W);
                dm_start    <= '1';
                sum_num_next <= (others => '0');
                sum_den_f_next <= (others => '0');
                sum_den_t_next <= (others => '0');
                y_next <= 0; x_next <= 0;
                state_next <= S_L_U_WAIT;

            when S_L_U_WAIT =>
                if dm_done = '1' then
                    f_bar_next <= resize(dm_quot, 8);
                    state_next <= S_L_YX_FILL;
                end if;

            -- PIPELINED unutrasnja petlja (~1 takt/piksel)
            when S_L_YX_FILL =>
                img_addr_o   <= v_reg * img_w_reg + u_reg;   -- (x=0, y=0)
                templ_addr_o <= 0;
                if tmp_w_reg = 1 and tmp_h_reg = 1 then
                    state_next <= S_L_YX_DRAIN;
                else
                    if tmp_w_reg > 1 then
                        x_next <= 1;
                    else
                        x_next <= 0; y_next <= 1;
                    end if;
                    state_next <= S_L_YX_RUN;
                end if;

            when S_L_YX_RUN =>
                df := signed(resize(img_data_i, 9))   - signed(resize(f_bar_reg, 9));
                dt := signed(resize(templ_data_i, 9)) - signed(resize(template_mean_reg, 9));
                sum_num_next   <= sum_num_reg   + resize(df * dt, 27);
                sum_den_f_next <= sum_den_f_reg + unsigned(resize(df * df, 26));
                sum_den_t_next <= sum_den_t_reg + unsigned(resize(dt * dt, 26));

                img_addr_o   <= (v_reg + y_reg) * img_w_reg + (u_reg + x_reg);
                templ_addr_o <= y_reg * tmp_w_reg + x_reg;

                if x_reg = tmp_w_reg - 1 and y_reg = tmp_h_reg - 1 then
                    state_next <= S_L_YX_DRAIN;
                elsif x_reg + 1 < tmp_w_reg then
                    x_next <= x_reg + 1;
                else
                    x_next <= 0; y_next <= y_reg + 1;
                end if;

            when S_L_YX_DRAIN =>
                df := signed(resize(img_data_i, 9))   - signed(resize(f_bar_reg, 9));
                dt := signed(resize(templ_data_i, 9)) - signed(resize(template_mean_reg, 9));
                sum_num_next   <= sum_num_reg   + resize(df * dt, 27);
                sum_den_f_next <= sum_den_f_reg + unsigned(resize(df * df, 26));
                sum_den_t_next <= sum_den_t_reg + unsigned(resize(dt * dt, 26));
                state_next <= S_NCC_DIV;

            -- NCC^2 = (num_sq << 31) / den_prod  -> div_ncc
            when S_NCC_DIV =>
                if sum_den_f_reg = 0 or sum_den_t_reg = 0 then
                    result_q_next <= (others => '0');
                    state_next <= S_WRITE_RESULT;
                else
                    num_sq_v   := unsigned(resize(sum_num_reg * sum_num_reg, 52));
                    den_prod_v := resize(sum_den_f_reg * sum_den_t_reg, 52);
                    dn_dividend <= shift_left(resize(num_sq_v, DN_W), 31);
                    dn_divisor  <= resize(den_prod_v, DN_W);
                    dn_start    <= '1';
                    state_next  <= S_NCC_WAIT;
                end if;

            when S_NCC_WAIT =>
                if dn_done = '1' then
                    result_q_next <= resize(dn_quot, 32);
                    state_next <= S_WRITE_RESULT;
                end if;

            when S_WRITE_RESULT =>
                result_addr_o <= v_reg * res_w_reg + u_reg;
                result_wr_o   <= '1';
                result_data_o <= result_q_reg;

                if u_reg + 1 < res_w_reg then
                    u_next <= u_reg + 1;
                    state_next <= S_L_U_A;
                else
                    v_next <= v_reg + 1;
                    state_next <= S_L_V;
                end if;

            when S_DONE =>
                busy_next <= '0';
                done_next <= '1';
                state_next <= S_IDLE;

        end case;
    end process comb_proc;

end architecture rtl;
