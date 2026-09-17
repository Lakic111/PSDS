-- ============================================================================
-- ANOTIRANA KOPIJA za ucenje -- original je src/vhdl/ncc_core.vhd, NE MENJATI
-- ovaj fajl kao izvor za sintezu. Svaka linija/blok ima objasnjenje odmah
-- pored ili iznad. Citaj odozgo na dole, kao pricu.
-- ============================================================================

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
--
-- STA JE OVO: sekvencijalni (restoring) celobrojni delilac, opsti za bilo koju
-- sirinu W. Zamenjuje kombinaciono deljenje ("/" u jednoj liniji), koje bi
-- sintisalo OGROMNO kombinaciono stablo i srusilo tajming (izmereno WNS ~ -46ns
-- kad je probano kombinaciono). Ovde se deljenje "razvuce" kroz W taktova --
-- svaki takt radi 1 bit posla (1 oduzimanje + 1 poredjenje), pa je kombinaciona
-- putanja kratka. Cena: rezultat kasni W taktova, ali se to desava svega par
-- puta po prozoru (mean, f_bar, NCC^2), ne po pikselu -- propusnost ne trpi.
--
-- INTERFEJS JE HANDSHAKE (nije kombinaciona funkcija):
--   1. spolja postavis dividend/divisor
--   2. impulsiras start='1' na jedan takt
--   3. cekas W taktova (busy='1')
--   4. done='1' na jedan takt, quotient/remainder su tad validni
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;   -- tip std_logic (bit + 'U'/'X'/'Z' za simulaciju)
use ieee.numeric_std.all;      -- tipovi unsigned/signed + aritmetika (+, -, <, >=)

entity seq_divider is
    generic (
        W : integer := 32      -- sirina operanada u bitima; PARAMETAR, ne fiksna
                                -- vrednost -- ista arhitektura se instancira dvaput
                                -- u ncc_core sa razlicitim W (18 i 83 bita)
    );
    port (
        clk       : in  std_logic;                 -- sistemski takt
        rst       : in  std_logic;                 -- sinhroni reset, aktivan '1'
        start     : in  std_logic;                 -- impuls: "pokreni deljenje sada"
        dividend  : in  unsigned(W - 1 downto 0);   -- deljenik (npr. bitovi 17..0 za W=18)
        divisor   : in  unsigned(W - 1 downto 0);   -- delilac
        quotient  : out unsigned(W - 1 downto 0);   -- kolicnik, validan kad done='1'
        remainder : out unsigned(W - 1 downto 0);   -- ostatak (ovde se nikad ne koristi
                                                     -- spolja -- port => open na oba mesta
                                                     -- instanciranja u ncc_core)
        busy      : out std_logic;                  -- '1' dok deljenje traje
        done      : out std_logic                   -- impuls od 1 takta: gotovo je
    );
end entity seq_divider;

architecture rtl of seq_divider is
    -- Cetiri interna registra + dva "shadow" signala za out portove.
    -- (VHDL ne dozvoljava da citas 'out' port unutar arhitekture, pa se drzi
    --  interni signal busy_s/done_s i na kraju samo spoji na port.)
    signal rem_reg  : unsigned(W - 1 downto 0) := (others => '0');  -- trenutni ostatak
    signal work_reg : unsigned(W - 1 downto 0) := (others => '0');  -- POCINJE kao
        -- dividend, ali se svaki takt POMERA ULEVO za 1 bit i u prazno mesto
        -- upisuje sledeci bit kolicnika -- na kraju W taktova, work_reg VISE
        -- NE sadrzi deljenik, nego GOTOV kolicnik. Ovo je "shift register" trik
        -- restoring dividera: isti registar sluzi i kao ulaz i kao izlaz.
    signal div_reg  : unsigned(W - 1 downto 0) := (others => '0');  -- registrovan
        -- divisor (da se ulaz spolja moze promeniti odmah posle start-a bez
        -- da pokvari deljenje u toku)
    signal cnt      : integer range 0 to W := 0;   -- brojac preostalih bitova/iteracija;
                                                     -- kreze W -> 1, kad dodje do 1 posle
                                                     -- te iteracije je done
    signal busy_s   : std_logic := '0';
    signal done_s   : std_logic := '0';
begin

    -- JEDINI proces u ovom design unit-u -- i sekvencijalna logika (registri)
    -- i "next state" logika su POMESANI ovde (jednoprocesni stil), za razliku
    -- od ncc_core koji koristi DVOPROCESNI stil (registri odvojeni od
    -- kombinacione logike). Ovo je svesna razlika: seq_divider je mali i
    -- samostalan, ne mora da prati istu konvenciju kao glavni FSM.
    process (clk)
        variable sh : unsigned(W downto 0);  -- POMOCNA promenljiva, SIRA za 1 bit
            -- (W+1 bita) -- treba nam prostor za "probno oduzimanje" pre nego sto
            -- znamo da li je rezultat negativan (restoring algoritam: probaj
            -- oduzimanje, ako je rezultat negativan vrati nazad = "restore")
    begin
        if rising_edge(clk) then
            done_s <= '0';   -- default: done je impuls, spusti ga svaki takt
                              -- osim kad ga eksplicitno dignes ispod (cnt=1)

            if rst = '1' then
                -- SINHRONI RESET: sve na nulu, spremno za sledeci start
                busy_s   <= '0';
                cnt      <= 0;
                rem_reg  <= (others => '0');
                work_reg <= (others => '0');

            elsif start = '1' and busy_s = '0' then
                -- POKRETANJE: ucitaj operande, pripremi brojac.
                -- 'and busy_s=0' stiti od ponovnog starta usred deljenja koje
                -- vec traje (spoljna logika ionako ne bi trebalo to da uradi,
                -- ali ovo je dodatna sigurnosna kocnica u samom deliocu)
                rem_reg  <= (others => '0');   -- ostatak kreze od 0
                work_reg <= dividend;          -- work_reg = deljenik (jos)
                div_reg  <= divisor;
                cnt      <= W;                 -- W iteracija do kraja
                busy_s   <= '1';

            elsif busy_s = '1' then
                -- JEDNA ITERACIJA RESTORING ALGORITMA (izvrsava se svaki takt
                -- dok busy_s='1', tj. W puta ukupno):
                --
                -- sh = (rem_reg pomeren ulevo za 1 bit) sa NAJZNACAJNIJIM bitom
                --      work_reg-a ugurana kao novi LSB.
                -- To je isto sto i "spusti sledeci bit deljenika u ostatak",
                -- klasicni korak deljenja "na papiru" (dugo deljenje).
                sh := rem_reg & work_reg(W - 1);

                if sh >= ('0' & div_reg) then
                    -- Probno oduzimanje USPELO (sh >= divisor): taj bit
                    -- kolicnika je '1'. Novi ostatak = sh - divisor.
                    rem_reg  <= resize(sh - ('0' & div_reg), W);
                    -- work_reg se pomera ulevo, u prazan LSB upisujemo '1'
                    -- (bit kolicnika koji smo upravo odredili)
                    work_reg <= work_reg(W - 2 downto 0) & '1';
                else
                    -- Probno oduzimanje NE USPEVA (sh < divisor): taj bit
                    -- kolicnika je '0', ostatak ostaje sh (bez oduzimanja --
                    -- "restore", otud ime algoritma).
                    rem_reg  <= resize(sh, W);
                    work_reg <= work_reg(W - 2 downto 0) & '0';
                end if;

                cnt <= cnt - 1;
                if cnt = 1 then
                    -- Ovo je bila POSLEDNJA iteracija (upravo smo izracunali
                    -- poslednji bit). Javi gotovo.
                    busy_s <= '0';
                    done_s <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Spajanje internih signala na izlazne portove.
    -- VAZNO: quotient <= work_reg -- posle W iteracija, work_reg vise NIJE
    -- deljenik (potrosen je, bit po bit izguran napolje), nego je GOTOV
    -- kolicnik. Ovo iznenadi na prvo citanje -- ime "work_reg" ne kaze da mu
    -- se namena menja tokom rada.
    quotient  <= work_reg;
    remainder <= rem_reg;
    busy      <= busy_s;
    done      <= done_s;
end architecture rtl;


-- ---------------------------------------------------------------------------
-- Design unit 2: ncc_core (pipelined + delioci)
--
-- OVO JE GLAVNO JEZGRO -- FSM koji implementira ceo NCC algoritam. Koristi
-- DVOPROCESNI STIL: PROCES 1 (registri, sinhroni) je odvojen od PROCES 2
-- (kombinaciona logika, next-state). Ovo je stil koji vezba 3-5 trazi i koji
-- ASMD dijagram direktno opisuje: svaki 'when' u PROCES 2 = jedan ASM blok =
-- jedno stanje na dijagramu.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ncc_pkg.all;   -- tipovi/konstante projekta: dim_t, pixel_t, sat_t,
                         -- mean_t, numacc_t, denacc_t, diff_t, sq52_t, result_t,
                         -- MAX_IMG_W/H, MAX_TMP_W/H, MAX_TMP_PIX, SAT_W, SAT_SIZE...
                         -- (definisano u ncc_pkg.vhd -- pogledaj taj fajl za
                         --  tacne sirine bita ako te pitaju "zasto bas X bita")

entity ncc_core is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        start      : in  std_logic;      -- impuls od AXI-Lite REG_CTRL preko IP omotaca
        busy       : out std_logic;      -- ide u REG_STATUS bit1
        done       : out std_logic;      -- interni signal, IP omotac ga pretvara u
                                          -- REG_STATUS bit0 (done_sticky, drzi se dok
                                          -- se ne procita/restartuje)
        img_w      : in  dim_t;          -- sirina slike/segmenta (iz REG_IMG_W)
        img_h      : in  dim_t;          -- visina slike/segmenta
        tmp_w      : in  dim_t;          -- sirina sablona
        tmp_h      : in  dim_t;          -- visina sablona

        -- Ova tri para (adresa/podatak) su INTERNI portovi ka memorijama IP-a
        -- (port B dvoportnih BRAM-ova u mem_subsystem.vhd) -- NISU AXI adrese!
        -- CPU puni te iste memorije preko DRUGOG porta (port A, kroz S01 AXI),
        -- potpuno nezavisno, PRE nego sto se start='1' desi.
        img_addr_o    : out integer range 0 to MAX_IMG_PIX - 1;  -- 0..8099 (90x90)
        img_data_i    : in  pixel_t;                              -- 8-bitni piksel slike
        templ_addr_o  : out integer range 0 to MAX_TMP_PIX - 1;  -- 0..899 (30x30)
        templ_data_i  : in  pixel_t;                              -- 8-bitni piksel sablona
        result_addr_o : out integer range 0 to MAX_IMG_PIX - 1;  -- pozicija u mapi rezultata
        result_data_o : out result_t;     -- 32-bitni NCC^2 rezultat (Q1.31)
        result_wr_o   : out std_logic     -- upisni enable za result_mem (port B)
    );
end entity ncc_core;

architecture rtl of ncc_core is

    -- SVIH 23 STANJA FSM-a. Redosled u tipu NIJE bitan za funkcionalnost
    -- (VHDL enum), ali je ovde napisan u LOGICKOM redosledu toka -- citaj ovu
    -- listu kao "poglavlja" price koju FSM prica:
    type state_t is (S_IDLE,                                    -- cekaj start
                      S_LOAD_IMG_ADDR, S_LOAD_IMG_DATA,          -- FAZA A: ucitaj sliku + SAT
                      S_LOAD_TMPL_ADDR, S_LOAD_TMPL_DATA,        -- FAZA B: ucitaj sablon
                      S_CALC_MEAN, S_CALC_MEAN_WAIT,             -- FAZA C: srednja vrednost sablona
                      S_L_V,                                      -- spoljna petlja: sledeci red prozora
                      S_L_U_A, S_L_U_B, S_L_U_C, S_L_U_D, S_L_U_E, S_L_U_WAIT,
                                                                   -- f_bar iz SAT-a (A-B-C+D formula)
                      S_L_YX_FILL, S_L_YX_RUN, S_L_YX_DRAIN, S_L_YX_DRAIN2,
                                                                   -- UNUTRASNJA PETLJA: MAC pipeline
                      S_NCC_SQ, S_NCC_DIV, S_NCC_WAIT,            -- NCC^2 = kvadriranje + deljenje
                      S_WRITE_RESULT, S_DONE);                    -- upis rezultata / kraj

    -- STANDARDNI PAR ZA SVAKI REGISTAR U DVOPROCESNOM STILU:
    -- "_reg" = trenutna vrednost (menja se SAMO u PROCES 1, na ivici takta)
    -- "_next" = sledeca vrednost (racuna se KOMBINACIONO u PROCES 2, spaja se
    --           na _reg tek na sledecem taktu)
    -- Ovaj par se ponavlja za SVAKI signal ispod -- kad vidis "_next <= X" u
    -- PROCES 2 to JOS NIJE promenjena vrednost, promenice se tek posle takta.
    signal state_reg, state_next : state_t := S_IDLE;

    -- Dimenzije i izvedene velicine (registrovane u S_IDLE kad start stigne,
    -- konstantne za citavo trajanje jednog poziva)
    signal img_w_reg, img_w_next, img_h_reg, img_h_next : integer range 0 to MAX_IMG_W := 0;
    signal tmp_w_reg, tmp_w_next, tmp_h_reg, tmp_h_next : integer range 0 to MAX_IMG_W := 0;
    signal res_w_reg, res_w_next, res_h_reg, res_h_next : integer range 0 to MAX_IMG_W := 0;
        -- res_w/res_h = broj MOGUCIH POZICIJA prozora po sirini/visini =
        -- img_w - tmp_w + 1 (klizni prozor -- koliko puta sablon "stane" u sliku)

    -- Brojaci petlji -- svaki ima svoju ulogu, LAKO SE ZABUNI KOJI JE KOJI:
    signal y_reg, y_next, x_reg, x_next                 : integer range 0 to MAX_IMG_W := 0;
        -- (x,y) = SPOLJNI par: koristi se DVA PUTA za razlicite stvari --
        -- prvo u Fazi A kao pozicija piksela slike (0..img_w/h), pa PONOVO
        -- u unutrasnjoj petlji kao lokalna pozicija UNUTAR sablona (0..tmp_w/h).
        -- Ponovna upotreba istog registra je namerna usteda resursa, ne greska.
    signal v_reg, v_next, u_reg, u_next                 : integer range 0 to MAX_IMG_W := 0;
        -- (u,v) = POZICIJA PROZORA u slici (gornji-levi ugao trenutnog prozora
        -- koji se testira) -- v ide 0..res_h, u ide 0..res_w
    signal p_reg, p_next                                : integer range 0 to MAX_TMP_PIX := 0;
        -- p = linearni brojac piksela sablona SAMO tokom ucitavanja (Faza B)

    -- Akumulatori algoritma:
    signal row_sum_reg, row_sum_next             : sat_t := (others => '0');
        -- suma piksela u TEKUCEM REDU slike, koristi se pri gradnji SAT-a
    signal sum_t_reg, sum_t_next                 : sat_t := (others => '0');
        -- suma SVIH piksela sablona (za srednju vrednost sablona)
    signal f_bar_reg, f_bar_next                 : mean_t := (others => '0');
        -- srednja vrednost SLIKE u trenutnom prozoru (racuna se IZNOVA za
        -- svaku poziciju (u,v) -- to je razlog za S_L_U_A..E svaki put)
    signal template_mean_reg, template_mean_next : mean_t := (others => '0');
        -- srednja vrednost SABLONA -- racuna se JEDNOM po pozivu (S_CALC_MEAN),
        -- ne menja se dok se sablon ne promeni
    signal sum_num_reg, sum_num_next             : numacc_t := (others => '0');
        -- brojilac NCC formule: suma (piksel-f_bar)*(sablon-template_mean)
    signal sum_den_f_reg, sum_den_f_next         : denacc_t := (others => '0');
        -- deo imenioca: suma (piksel-f_bar)^2
    signal sum_den_t_reg, sum_den_t_next         : denacc_t := (others => '0');
        -- deo imenioca: suma (sablon-template_mean)^2

    -- STEPEN 2 protocne MAC petlje (Korak 8b): razlike piksel-sredina se
    -- registruju PRE mnozenja, da se putanja BRAM -> oduzimanje -> mnozenje ->
    -- akumulator presece na DVA takta umesto jednog. mac_v_reg kaze da li
    -- df_reg/dt_reg trenutno drze VALIDAN registrovan piksel (spreca da se
    -- na prvom taktu petlje akumulira "djubre" iz reseta).
    signal df_reg, df_next                       : diff_t := (others => '0');  -- piksel - f_bar (SIGNED!)
    signal dt_reg, dt_next                       : diff_t := (others => '0');  -- sablon - template_mean (SIGNED!)
    signal mac_v_reg, mac_v_next                 : std_logic := '0';           -- "df/dt su validni" bit

    -- Kvadriranje brojioca / proizvod imenilaca, registrovani PRE ulaska u
    -- delilac (Korak 8b): putanja sum_num_reg -> kvadriranje -> work_reg
    -- delioca je bila NAJGORA post-route (10,68 ns) -- ovaj registar je
    -- presekao tu putanju na pola. Izvrsava se SAMO JEDNOM po prozoru (ne po
    -- pikselu), pa propusnost prakticno ne trpi.
    signal num_sq_reg, num_sq_next               : sq52_t := (others => '0');   -- sum_num^2
    signal den_prod_reg, den_prod_next           : sq52_t := (others => '0');   -- sum_den_f * sum_den_t

    signal busy_reg, busy_next                   : std_logic := '0';
    signal done_reg, done_next                   : std_logic := '0';
    signal sum_f_partial_reg, sum_f_partial_next : sat_t := (others => '0');
        -- MEDJUREZULTAT dok se A-B-C+D racuna kroz vise stanja (S_L_U_B..D)
    signal result_q_reg, result_q_next           : result_t := (others => '0');
        -- gotov NCC^2 rezultat, ceka upis u S_WRITE_RESULT

    -- Sama integralna slika (SAT = Summed-Area Table), IMPLEMENTIRANA KAO BRAM:
    signal sat_mem     : sat_mem_t := (others => (others => '0'));
    signal sat_wr_en   : std_logic := '0';
    signal sat_wr_addr : integer range 0 to SAT_SIZE - 1 := 0;
    signal sat_wr_data : sat_t := (others => '0');
    signal sat_rd_addr : integer range 0 to SAT_SIZE - 1 := 0;
    signal sat_rd_data : sat_t := (others => '0');   -- REGISTROVAN izlaz (vidi
        -- sat_ram_proc ispod) -- zato izmedju "postavi sat_rd_addr" i "koristi
        -- sat_rd_data" MORA proci tacno 1 takt (to je razlog zasto S_L_U_A..D
        -- imaju 4 ODVOJENA stanja, a ne sve u jednom)

    -- Konstante i signali za DVA delioca (dve instance seq_divider-a, razlicite
    -- sirine za dve razlicite namene):
    constant DM_W : integer := 18;   -- "divider mean": za template_mean I f_bar
        -- (obe upotrebe dele ISTI fizicki delilac -- vremenski multipleksirano,
        -- ne rade nikad istovremeno u FSM-u)
    constant DN_W : integer := 83;   -- "divider ncc": za finalno NCC^2 deljenje
        -- (siroko jer je num_sq do 52 bita, pomeren za 31 -- << 31 za Q1.31 --
        -- pa mora stati u 52+31=83 bita)
    signal dm_start, dm_done                 : std_logic := '0';
    signal dm_dividend, dm_divisor, dm_quot  : unsigned(DM_W - 1 downto 0) := (others => '0');
    signal dn_start, dn_done                 : std_logic := '0';
    signal dn_dividend, dn_divisor, dn_quot  : unsigned(DN_W - 1 downto 0) := (others => '0');

begin

    busy <= busy_reg;   -- izlazni portovi su samo "prozor" ka internim _reg signalima
    done <= done_reg;

    -- INSTANCIRANJE prve instance seq_divider-a (Design unit 1 iznad), sa
    -- W=18. "entity work.seq_divider" znaci "uzmi taj design unit iz ovog
    -- projekta (biblioteka 'work')".
    div_mean : entity work.seq_divider
        generic map (W => DM_W)
        port map (clk => clk, rst => rst, start => dm_start,
                  dividend => dm_dividend, divisor => dm_divisor,
                  quotient => dm_quot, remainder => open, busy => open, done => dm_done);
                  -- remainder/busy => open: NE koristimo te izlaze, "open" kaze
                  -- alatu da ih ne treba ni rutirati (ustedi resurse)

    -- Druga instanca, W=83, za NCC^2 deljenje. ISTI VHDL kod (seq_divider),
    -- DRUGA fizicka instanca u hardveru (sinteza pravi dva odvojena kola).
    div_ncc : entity work.seq_divider
        generic map (W => DN_W)
        port map (clk => clk, rst => rst, start => dn_start,
                  dividend => dn_dividend, divisor => dn_divisor,
                  quotient => dn_quot, remainder => open, busy => open, done => dn_done);

    -- ========================================================================
    -- PROCES 1: registri (SEKVENCIJALNI deo dvoprocesnog stila)
    --
    -- OVO JE JEDINI PROCES KOJI STVARNO PRAVI REGISTRE (flip-flopove).
    -- Sadrzaj: SAMO "reg <= next" za svaki signal, plus reset grana. NEMA
    -- ovde nikakve "logike" (nema if/case sem samog reset-a) -- sva odluka o
    -- TOME koja ce biti sledeca vrednost je vec doneta u PROCES 2 (comb_proc)
    -- ispod. Ovaj proces samo "otkucava" tu odluku na ivici takta.
    -- ========================================================================
    reg_proc : process (clk, rst)
    begin
        if rst = '1' then
            -- ASINHRONI reset (rst je u osetljivosti procesa) -- sve na 0/IDLE
            -- odmah, bez cekanja na ivicu takta.
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
            df_reg <= (others => '0');
            dt_reg <= (others => '0');
            mac_v_reg <= '0';
            num_sq_reg <= (others => '0');
            den_prod_reg <= (others => '0');
            busy_reg <= '0';
            done_reg <= '0';
            sum_f_partial_reg <= (others => '0');
            result_q_reg <= (others => '0');
        elsif rising_edge(clk) then
            -- Na svakoj usponskoj ivici takta: SVAKI _reg preuzima vrednost
            -- svog _next para. Ovo je mehanicko preslikavanje -- ako dodas
            -- novi signal u projekat, MORAS ga dodati i ovde i u comb_proc,
            -- inace nece imati efekta (klasicna greska pocetnika).
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
            df_reg <= df_next;
            dt_reg <= dt_next;
            mac_v_reg <= mac_v_next;
            num_sq_reg <= num_sq_next;
            den_prod_reg <= den_prod_next;
            busy_reg <= busy_next;
            done_reg <= done_next;
            sum_f_partial_reg <= sum_f_partial_next;
            result_q_reg <= result_q_next;
        end if;
    end process reg_proc;

    -- ========================================================================
    -- PROCES 3: sat_mem (BRAM) IZOLOVANA u sopstveni proces
    --
    -- Zasto ODVOJENO od PROCES 1: sinteza alat prepoznaje OVAJ TACAN OBLIK
    -- (jednostavan "if enable then mem(addr)<=data" + registrovano citanje)
    -- kao BRAM PRIMITIVU i mapira ga direktno na Block RAM resurs, umesto da
    -- ga sintetise kao hiljade flip-flopova. Da je ovo pomesano sa ostalim
    -- registrima u istom procesu, alat verovatno NE BI prepoznao obrazac.
    -- ========================================================================
    sat_ram_proc : process (clk)
    begin
        if rising_edge(clk) then
            if sat_wr_en = '1' then
                sat_mem(sat_wr_addr) <= sat_wr_data;   -- sinhroni upis
            end if;
            sat_rd_data <= sat_mem(sat_rd_addr);       -- REGISTROVANO citanje --
                -- rezultat kasni 1 takt iza promene sat_rd_addr (standardno
                -- ponasanje BRAM-a). Ovo je razlog "1 takt kasnjenja" pravila
                -- koje se provlaci kroz ceo FSM (S_LOAD_IMG_ADDR pa tek onda
                -- S_LOAD_IMG_DATA, S_L_U_A pa tek S_L_U_B, itd.)
        end if;
    end process sat_ram_proc;

    -- ========================================================================
    -- PROCES 2: kombinaciona logika (KOMBINACIONI deo dvoprocesnog stila)
    --
    -- OVDE ZIVI CEO FSM. process(all) znaci "osetljiv na SVE signale koje
    -- cita" (VHDL-2008 skraceni oblik za dugacku listu osetljivosti) -- ovo
    -- OBAVEZNO mora biti kombinaciono (nema clk u listi osetljivosti, nema
    -- rising_edge unutra), inace bi alat pravio "latch" umesto FSM logike.
    -- ========================================================================
    comb_proc : process (all)
        variable count       : integer range 0 to MAX_TMP_PIX;  -- pomocna: broj piksela sablona
        variable new_row_sum : sat_t;                            -- pomocna: privremena suma reda
    begin
        -- ====================================================================
        -- DEFAULT DODELE (izvrsavaju se NA POCETKU SVAKOG POZIVA procesa, za
        -- SVAKO stanje, PRE case-a ispod). Ovo je standardni FSM idiom:
        -- "ostani gde jesi, osim ako case grana ispod kaze drugacije".
        -- Bez ovoga bi svaki signal morao eksplicitno da se dodeli u SVAKOM
        -- 'when' grani -- i VHDL bi (pogresno) zakljucio da treba latch za
        -- slucajeve kad se signal ne pominje u nekoj grani.
        -- ====================================================================
        state_next <= state_reg;   -- podrazumevano: ostani u istom stanju
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
        df_next <= df_reg;
        dt_next <= dt_reg;
        mac_v_next <= mac_v_reg;
        num_sq_next <= num_sq_reg;
        den_prod_next <= den_prod_reg;
        busy_next <= busy_reg;
        done_next <= '0';   -- IZUZETAK: done je PODRAZUMEVANO 0 (impuls), samo
                             -- S_DONE grana ga digne na 1 -- nije "zadrzi
                             -- prethodnu vrednost" kao ostali signali
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

        -- ====================================================================
        -- GLAVNI CASE -- svaka grana = JEDNO STANJE = JEDAN ASM BLOK na
        -- dijagramu. Redosled komentara prati redosled u 'type state_t' iznad.
        -- ====================================================================
        case state_reg is

            -- ----------------------------------------------------------------
            -- S_IDLE -- ASM blok: "cekaj start". Test blok (sestougao na
            -- dijagramu) je 'if start=1'. Kad stigne, sve dimenzije i izvedene
            -- velicine se REGISTRUJU ODJEDNOM (uslovni izlazni blok).
            -- ----------------------------------------------------------------
            when S_IDLE =>
                if start = '1' then
                    -- UGOVOR SA SOFTVEROM (code review Koraka 8): dimenzije dolaze iz
                    -- 8-bitnih AXI-Lite registara, dakle 0..255, a ovde se smestaju u
                    -- `integer range 0 to MAX_IMG_W (=90)`. Van opsega je u simulaciji
                    -- fatalna greska opsega, a u hardveru tiho odsecanje bita i indeksi
                    -- van `sat_mem`. Dodatno: tmp_w*tmp_h mora stati u MAX_TMP_PIX,
                    -- tmp<=img (inace res ide u minus), i tmp!=0 (inace deljenje nulom
                    -- u seq_divider daje sve jedinice). Ove tvrdnje su simulaciona
                    -- kapija -- u sintezi nestaju, softver mora da postuje ugovor.
                    assert to_integer(img_w) >= 1 and to_integer(img_w) <= MAX_IMG_W
                        and to_integer(img_h) >= 1 and to_integer(img_h) <= MAX_IMG_H
                        report "ncc_core: img_w/img_h van opsega 1.." & integer'image(MAX_IMG_W)
                        severity failure;
                    assert to_integer(tmp_w) >= 1 and to_integer(tmp_w) <= MAX_TMP_W
                        and to_integer(tmp_h) >= 1 and to_integer(tmp_h) <= MAX_TMP_H
                        report "ncc_core: tmp_w/tmp_h van opsega 1.." & integer'image(MAX_TMP_W)
                        severity failure;
                    assert to_integer(tmp_w) * to_integer(tmp_h) <= MAX_TMP_PIX
                        report "ncc_core: tmp_w*tmp_h > MAX_TMP_PIX" severity failure;
                    assert to_integer(tmp_w) <= to_integer(img_w)
                        and to_integer(tmp_h) <= to_integer(img_h)
                        report "ncc_core: sablon veci od slike -> negativan res_w/res_h"
                        severity failure;
                    -- ^^^ cetiri "assert" iznad = SIMULACIONA KAPIJA (nestaju u
                    -- sintezi -- hardver ih NE proverava, softver mora da pazi)

                    img_w_next <= to_integer(img_w);   -- pretvori iz AXI std_logic_vector-a
                    img_h_next <= to_integer(img_h);   -- (preko dim_t/unsigned) u integer,
                    tmp_w_next <= to_integer(tmp_w);   -- lakse za aritmetiku ispod
                    tmp_h_next <= to_integer(tmp_h);
                    res_w_next <= to_integer(img_w) - to_integer(tmp_w) + 1;  -- broj pozicija
                    res_h_next <= to_integer(img_h) - to_integer(tmp_h) + 1;  -- prozora po osi
                    y_next <= 0; x_next <= 0;           -- pripremi brojace za Fazu A
                    row_sum_next <= (others => '0');
                    busy_next <= '1';                    -- digni busy (vidi se na AXI REG_STATUS)
                    state_next <= S_LOAD_IMG_ADDR;        -- pocni Fazu A
                end if;

            -- ----------------------------------------------------------------
            -- FAZA A: ucitaj sliku + izgradi integralnu sliku (SAT).
            -- DVA STANJA PO PIKSELU (ADDR pa DATA) jer je citanje BRAM-a
            -- registrovano -- adresa ovaj takt, podatak SLEDECI takt.
            -- ----------------------------------------------------------------
            when S_LOAD_IMG_ADDR =>
                img_addr_o  <= y_reg * img_w_reg + x_reg;       -- linearizuj (x,y) -> indeks
                sat_rd_addr <= y_reg * SAT_W + (x_reg + 1);     -- paralelno: procitaj SAT celiju
                                                                  -- "iznad" trenutne (za rekurentnu sumu)
                state_next <= S_LOAD_IMG_DATA;

            when S_LOAD_IMG_DATA =>
                -- img_data_i je SADA validan (adresa je bila postavljena
                -- PRETHODNI takt). new_row_sum = akumulirana suma u OVOM redu
                -- do i ukljucujuci trenutni piksel.
                if x_reg = 0 then
                    new_row_sum := resize(img_data_i, 32);      -- pocetak reda: resetuj na
                                                                  -- sam piksel (NE akumuliraj
                                                                  -- stari row_sum_reg iz proslog reda!)
                else
                    new_row_sum := row_sum_reg + resize(img_data_i, 32);
                end if;
                sat_wr_en   <= '1';
                sat_wr_addr <= (y_reg + 1) * SAT_W + (x_reg + 1);
                -- REKURENTNA FORMULA integralne slike:
                -- SAT[y+1][x+1] = SAT[y][x+1] (red iznad, procitan gore u ADDR
                --                 stanju, stize sad kao sat_rd_data)
                --               + new_row_sum (kumulativna suma OVOG reda do x)
                sat_wr_data <= sat_rd_data + new_row_sum;
                row_sum_next <= new_row_sum;

                -- Test grana (sestougao): sledeci piksel u redu, ili sledeci
                -- red, ili gotova cela slika -> predji u Fazu B.
                if x_reg + 1 < img_w_reg then
                    x_next <= x_reg + 1;
                    state_next <= S_LOAD_IMG_ADDR;
                elsif y_reg + 1 < img_h_reg then
                    x_next <= 0; y_next <= y_reg + 1;
                    state_next <= S_LOAD_IMG_ADDR;
                else
                    p_next <= 0;
                    sum_t_next <= (others => '0');
                    state_next <= S_LOAD_TMPL_ADDR;   -- cela slika ucitana -> Faza B
                end if;

            -- ----------------------------------------------------------------
            -- FAZA B: ucitaj sablon, saberi sve piksele (za srednju vrednost).
            -- Isti ADDR/DATA obrazac, prostije jer nema SAT-a za sablon.
            -- ----------------------------------------------------------------
            when S_LOAD_TMPL_ADDR =>
                templ_addr_o <= p_reg;
                state_next <= S_LOAD_TMPL_DATA;

            when S_LOAD_TMPL_DATA =>
                sum_t_next <= sum_t_reg + resize(templ_data_i, 32);
                if p_reg + 1 < tmp_w_reg * tmp_h_reg then
                    p_next <= p_reg + 1;
                    state_next <= S_LOAD_TMPL_ADDR;
                else
                    state_next <= S_CALC_MEAN;   -- sablon ucitan -> izracunaj mu srednju vrednost
                end if;

            -- ----------------------------------------------------------------
            -- FAZA C: template_mean = (sum_t + count/2) / count  (preko div_mean)
            -- "+ count/2" pre deljenja = ZAOKRUZIVANJE na najblizi ceo broj
            -- (umesto odsecanja na dole).
            -- ----------------------------------------------------------------
            when S_CALC_MEAN =>
                count := tmp_w_reg * tmp_h_reg;
                dm_dividend <= resize(sum_t_reg + to_unsigned(count / 2, 32), DM_W);
                dm_divisor  <= to_unsigned(count, DM_W);
                dm_start    <= '1';           -- IMPULS: pokreni delilac ovaj takt
                state_next  <= S_CALC_MEAN_WAIT;

            when S_CALC_MEAN_WAIT =>
                -- Cekaj dok delilac ne javi dm_done. Ovo je STANJE CEKANJA:
                -- RT operacija (upis registra) je u USLOVNOM IZLAZNOM BLOKU
                -- (zaobljena kutija), NE izvrsava se svaki takt -- samo kad je
                -- dm_done='1'. Test je sestougao 'dm_done=1', T/F grane.
                if dm_done = '1' then
                    template_mean_next <= resize(dm_quot, 8);
                    v_next <= 0;
                    state_next <= S_L_V;   -- predji na spoljnu petlju po prozorima
                end if;
                -- (F grana: ostani ovde, sve _next default vrednosti vec
                --  postavljene na pocetku procesa -- "cekaj dalje")

            -- ----------------------------------------------------------------
            -- SPOLJNA PETLJA PO PROZORIMA: za svaku poziciju (u,v) ponovi
            -- ceo unutrasnji racun. v = red prozora, u = kolona (postavlja se
            -- u S_L_U_A..S_WRITE_RESULT).
            -- ----------------------------------------------------------------
            when S_L_V =>
                if v_reg < res_h_reg then
                    u_next <= 0;
                    state_next <= S_L_U_A;   -- ima jos redova -> pocni novi red pozicija
                else
                    state_next <= S_DONE;    -- svi redovi obradjeni -> kraj
                end if;

            -- ----------------------------------------------------------------
            -- f_bar (srednja vrednost SLIKE u prozoru (u,v)) preko integralne
            -- slike -- SAT INKLUZIJA-EKSKLUZIJA formula, 4 ugla pravougaonika:
            --   suma_prozora = A - B - C + D
            -- gde je A donji-desni, B gornji-desni, C donji-levi, D gornji-levi
            -- ugao SAT tabele (SAT ima 1 red/kolonu VISE nego slika, otud +tmp_w/+tmp_h
            -- i obican v/u bez pomeraja na "gornjim" uglovima).
            -- Cetiri ODVOJENA stanja jer je citanje SAT BRAM-a registrovano
            -- (1 takt kasnjenja izmedju postavljanja adrese i citanja podatka).
            -- ----------------------------------------------------------------
            when S_L_U_A =>
                sat_rd_addr <= (v_reg + tmp_h_reg) * SAT_W + (u_reg + tmp_w_reg);  -- A (donji-desni)
                state_next <= S_L_U_B;

            when S_L_U_B =>
                sum_f_partial_next <= resize(sat_rd_data, 32);       -- + A (A je sad citljivo)
                sat_rd_addr <= v_reg * SAT_W + (u_reg + tmp_w_reg);  -- trazi B (gornji-desni)
                state_next <= S_L_U_C;

            when S_L_U_C =>
                sum_f_partial_next <= sum_f_partial_reg - resize(sat_rd_data, 32);  -- - B
                sat_rd_addr <= (v_reg + tmp_h_reg) * SAT_W + u_reg;  -- trazi C (donji-levi)
                state_next <= S_L_U_D;

            when S_L_U_D =>
                sum_f_partial_next <= sum_f_partial_reg - resize(sat_rd_data, 32);  -- - C
                sat_rd_addr <= v_reg * SAT_W + u_reg;   -- trazi D (gornji-levi)
                state_next <= S_L_U_E;

            when S_L_U_E =>
                -- D je sad citljivo (sat_rd_data). Dovrsi sumu (+ D) i odmah
                -- pokreni deljenje za f_bar, PARALELNO resetuj akumulatore MAC
                -- petlje i pripremi (x,y) za unutrasnju petlju.
                count := tmp_w_reg * tmp_h_reg;
                dm_dividend <= resize(sum_f_partial_reg + resize(sat_rd_data, 32) +
                                      to_unsigned(count / 2, 32), DM_W);
                dm_divisor  <= to_unsigned(count, DM_W);
                dm_start    <= '1';
                sum_num_next <= (others => '0');     -- NOVI prozor -> nuliraj akumulatore
                sum_den_f_next <= (others => '0');
                sum_den_t_next <= (others => '0');
                y_next <= 0; x_next <= 0;             -- x,y se sad KORISTE PONOVO, ovaj put
                                                       -- kao lokalna pozicija unutar sablona
                state_next <= S_L_U_WAIT;

            when S_L_U_WAIT =>
                if dm_done = '1' then
                    f_bar_next <= resize(dm_quot, 8);
                    state_next <= S_L_YX_FILL;   -- f_bar gotov -> pokreni MAC pipeline
                end if;

            -- ----------------------------------------------------------------
            -- UNUTRASNJA PETLJA -- PIPELINED MAC, TROSTEPENA (Korak 8b):
            --   stepen 1: izdaj adresu piksela slike/sablona (ovaj takt)
            --   stepen 2: podatak piksela STIZE (bio zatrazen PROSLI takt) ->
            --             registruj razliku (df_reg <= piksel - f_bar)
            --   stepen 3: mnozenje + akumulacija iz df_reg/dt_reg (PRETHODNI
            --             registrovan par, ne trenutni df_next!)
            -- Ranije su stepeni 2 i 3 bili u ISTOM taktu (BRAM -> oduzimanje ->
            -- mnozenje -> 27-bitni akumulator). Post-route je ta putanja bila
            -- 13,0 ns (16 nivoa, 9x CARRY4) i obarala 100 MHz: WNS -3,299 ns.
            -- Cena razdvajanja: +1 takt po prozoru od ~485 = +0,2% latencije.
            -- mac_v_reg gejtuje akumulaciju dok se protok ne napuni (cev prazna
            -- na pocetku -- prvi takt FILL, jos nema sta da se akumulira).
            -- ----------------------------------------------------------------
            when S_L_YX_FILL =>
                img_addr_o   <= v_reg * img_w_reg + u_reg;   -- prvi piksel prozora: (x=0,y=0) lokalno
                templ_addr_o <= 0;                            -- prvi piksel sablona
                mac_v_next   <= '0';        -- jos nema registrovanog piksela, cev prazna
                if tmp_w_reg = 1 and tmp_h_reg = 1 then
                    -- DEGENERISAN SABLON 1x1: nema sta da se "trci" kroz
                    -- pipeline, samo jedan piksel -> skoci pravo na DRAIN
                    -- (ova grana JE NEDOSTAJALA na staroj verziji ASMD dijagrama)
                    state_next <= S_L_YX_DRAIN;
                else
                    if tmp_w_reg > 1 then
                        x_next <= 1;         -- sledeca pozicija: pomeri se po x
                    else
                        x_next <= 0; y_next <= 1;   -- tmp_w=1 ali tmp_h>1: predji u sledeci red
                    end if;
                    state_next <= S_L_YX_RUN;
                end if;

            when S_L_YX_RUN =>
                -- STEPEN 2: registruj razlike za piksel ciji je PODATAK sad na
                -- ulazu (zatrazen PROSLI takt, bilo u FILL ili prethodnom RUN-u).
                -- SIGNED oduzimanje -- OVO JE ISPRAVKA ESL greske (ESL je imao
                -- unsigned, sto pada kad je piksel < f_bar/template_mean, tj.
                -- razlika negativna).
                df_next    <= signed(resize(img_data_i, 9))   - signed(resize(f_bar_reg, 9));
                dt_next    <= signed(resize(templ_data_i, 9)) - signed(resize(template_mean_reg, 9));
                mac_v_next <= '1';    -- od sad pa nadalje, df_reg/dt_reg NOSE validan piksel
                -- STEPEN 3: akumuliraj PRETHODNI registrovan par (df_reg/dt_reg
                -- OD PRE ovog takta, ne df_next koji se tek sad racuna gore!)
                if mac_v_reg = '1' then
                    sum_num_next   <= sum_num_reg   + resize(df_reg * dt_reg, 27);
                    sum_den_f_next <= sum_den_f_reg + unsigned(resize(df_reg * df_reg, 26));
                    sum_den_t_next <= sum_den_t_reg + unsigned(resize(dt_reg * dt_reg, 26));
                end if;
                -- STEPEN 1: adresa SLEDECEG piksela (za sledeci takt)
                img_addr_o   <= (v_reg + y_reg) * img_w_reg + (u_reg + x_reg);
                templ_addr_o <= y_reg * tmp_w_reg + x_reg;

                -- Test: da li smo na POSLEDNJEM pikselu sablona? Ako da ->
                -- DRAIN (nema vise novih adresa da se izdaju). Inace pomeri
                -- (x,y) na sledecu poziciju unutar sablona (red-major redosled).
                if x_reg = tmp_w_reg - 1 and y_reg = tmp_h_reg - 1 then
                    state_next <= S_L_YX_DRAIN;
                elsif x_reg + 1 < tmp_w_reg then
                    x_next <= x_reg + 1;
                else
                    x_next <= 0; y_next <= y_reg + 1;
                end if;

            -- DRAIN: podatak POSLEDNJEG piksela je SAD na ulazu (zatrazen u
            -- proslom RUN taktu) -> registruj ga (stepen 2), a akumuliraj
            -- PRETPOSLEDNJI (stepen 3, isto kao RUN, samo BEZ stepena 1 --
            -- nema vise novih adresa da se izda, petlja je gotova).
            when S_L_YX_DRAIN =>
                df_next    <= signed(resize(img_data_i, 9))   - signed(resize(f_bar_reg, 9));
                dt_next    <= signed(resize(templ_data_i, 9)) - signed(resize(template_mean_reg, 9));
                mac_v_next <= '1';
                if mac_v_reg = '1' then
                    sum_num_next   <= sum_num_reg   + resize(df_reg * dt_reg, 27);
                    sum_den_f_next <= sum_den_f_reg + unsigned(resize(df_reg * df_reg, 26));
                    sum_den_t_next <= sum_den_t_reg + unsigned(resize(dt_reg * dt_reg, 26));
                end if;
                state_next <= S_L_YX_DRAIN2;

            -- DRAIN2: cev se prazni do kraja -- akumuliraj POSLEDNJI
            -- registrovan piksel (onaj sto je upravo registrovan u DRAIN
            -- stanju iznad). Posle ovoga, mac_v_next<='0' vraca cev u "prazno"
            -- stanje za SLEDECI prozor.
            when S_L_YX_DRAIN2 =>
                sum_num_next   <= sum_num_reg   + resize(df_reg * dt_reg, 27);
                sum_den_f_next <= sum_den_f_reg + unsigned(resize(df_reg * df_reg, 26));
                sum_den_t_next <= sum_den_t_reg + unsigned(resize(dt_reg * dt_reg, 26));
                mac_v_next     <= '0';
                state_next     <= S_NCC_SQ;

            -- ----------------------------------------------------------------
            -- NCC^2 = (sum_num^2 << 31) / (sum_den_f * sum_den_t)  -- preko div_ncc
            -- << 31 = SKALIRANJE u Q1.31 fiksni zarez (0x80000000 = 1,0 tacno)
            -- Razdvojeno u DVA takta (Korak 8b): kvadriranje/mnozenje se
            -- registruje (S_NCC_SQ), pa TEK ONDA ulazi u 83-bitni delilac
            -- (S_NCC_DIV). Putanja sum_num_reg -> kvadriranje -> work_reg bila
            -- je najgora post-route (10,682 ns, WNS -0,869). Izvrsava se
            -- JEDNOM po prozoru (~485 taktova), pa propusnost prakticno ne pati.
            -- ----------------------------------------------------------------
            when S_NCC_SQ =>
                if sum_den_f_reg = 0 or sum_den_t_reg = 0 then
                    -- RAVNA POVRSINA (nulta varijansa) -- deljenje nulom bi
                    -- dalo besmislen rezultat (seq_divider bi vratio sve
                    -- jedinice). Umesto toga, eksplicitno rezultat = 0.
                    result_q_next <= (others => '0');
                    state_next <= S_WRITE_RESULT;
                else
                    num_sq_next   <= unsigned(resize(sum_num_reg * sum_num_reg, 52));
                    den_prod_next <= resize(sum_den_f_reg * sum_den_t_reg, 52);
                    state_next    <= S_NCC_DIV;
                end if;

            when S_NCC_DIV =>
                dn_dividend <= shift_left(resize(num_sq_reg, DN_W), 31);  -- << 31 = Q1.31
                dn_divisor  <= resize(den_prod_reg, DN_W);
                dn_start    <= '1';
                state_next  <= S_NCC_WAIT;

            when S_NCC_WAIT =>
                if dn_done = '1' then
                    result_q_next <= resize(dn_quot, 32);
                    state_next <= S_WRITE_RESULT;
                end if;

            -- ----------------------------------------------------------------
            -- Upisi gotov rezultat u memoriju rezultata, pa predji na sledecu
            -- poziciju prozora (u+1), ili na sledeci red (v+1) ako je red gotov.
            -- ----------------------------------------------------------------
            when S_WRITE_RESULT =>
                result_addr_o <= v_reg * res_w_reg + u_reg;   -- linearizuj (u,v) -> indeks u mapi rezultata
                result_wr_o   <= '1';
                result_data_o <= result_q_reg;

                if u_reg + 1 < res_w_reg then
                    u_next <= u_reg + 1;
                    state_next <= S_L_U_A;   -- sledeca pozicija u ISTOM redu prozora
                else
                    v_next <= v_reg + 1;
                    state_next <= S_L_V;     -- red gotov -> proveri ima li sledeceg
                end if;

            -- ----------------------------------------------------------------
            -- Kraj: spusti busy, digni done na TACNO JEDAN TAKT (done_next je
            -- vec '0' po default-u na pocetku procesa -- sledeci takt ce se
            -- automatski vratiti na 0 cim state_reg predje u S_IDLE).
            -- ----------------------------------------------------------------
            when S_DONE =>
                busy_next <= '0';
                done_next <= '1';
                state_next <= S_IDLE;

        end case;
    end process comb_proc;

end architecture rtl;
