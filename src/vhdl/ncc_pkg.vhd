-- Zajednicki tipovi/konstante za NCC RTL model (Korak 3).
-- Sirine tipova prate ESL Tabelu 2 + signed ispravku iz Koraka 1
-- (videti src/hls/ncc_kernel.hpp i 02 Dokumentacija/(C) Korak 2 ... .md).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ncc_pkg is

    -- Isti budzet kao src/hls/ncc_kernel.hpp: pun segment/sablon (90x90/30x30)
    -- ili grubi coarse-to-fine prolaz (45x45/15x15).
    constant MAX_IMG_W   : integer := 90;
    constant MAX_IMG_H   : integer := 90;
    constant MAX_TMP_W   : integer := 30;
    constant MAX_TMP_H   : integer := 30;
    constant MAX_IMG_PIX : integer := MAX_IMG_W * MAX_IMG_H;
    constant MAX_TMP_PIX : integer := MAX_TMP_W * MAX_TMP_H;
    constant SAT_W       : integer := MAX_IMG_W + 1;
    constant SAT_H       : integer := MAX_IMG_H + 1;
    constant SAT_SIZE    : integer := SAT_W * SAT_H;

    subtype pixel_t  is unsigned(7 downto 0);           -- piksel (0..255)
    subtype dim_t    is unsigned(7 downto 0);           -- img_w/h, tmp_w/h (max 90)
    subtype mean_t   is unsigned(7 downto 0);           -- f_bar / template_mean (zaokruzeno)
    subtype diff_t   is signed(8 downto 0);             -- diff_f/diff_t (ISPRAVKA: signed, ne unsigned)
    subtype numacc_t is signed(26 downto 0);             -- sum_num (ISPRAVKA: signed)
    subtype denacc_t is unsigned(25 downto 0);           -- sum_den_f / sum_den_t
    subtype sq52_t   is unsigned(51 downto 0);           -- num_sq / den_prod
    subtype sat_t    is unsigned(31 downto 0);           -- integral image akumulator (nije u Tabeli 2)
    subtype result_t is unsigned(31 downto 0);           -- rezultat po poziciji prozora (Q1.31)

    type pixel_array_t  is array (natural range <>) of pixel_t;
    type result_array_t is array (natural range <>) of result_t;
    type sat_array_t    is array (natural range <>) of sat_t;

    subtype image_array_t     is pixel_array_t(0 to MAX_IMG_PIX-1);
    subtype templ_array_t     is pixel_array_t(0 to MAX_TMP_PIX-1);
    subtype resultmap_array_t is result_array_t(0 to MAX_IMG_PIX-1);
    subtype sat_mem_t         is sat_array_t(0 to SAT_SIZE-1);

end package ncc_pkg;
