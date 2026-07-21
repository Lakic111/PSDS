# Dodatak — Inferring VHDL to DSP (DSP48 mapiranje)

Izvor: `06 Prilozi/Vezbe/Inferring_VHDL_to_DSP.pdf` (9 strana, kratak dokument o mapiranju VHDL koda na DSP48E1 ćelije)

## Šta ovaj dokument pokriva

DSP48E1 ćelija (7-series Xilinx) sadrži: 25×18 signed množač, 48-bitni ALU
(add/sub/logic, SIMD 2×24-bit ili 4×12-bit), pre-adder (sabiranje pre množenja),
pattern detector, i **do 3 nivoa opcionih pipeline registara** (ulazni operandi → rezultat
množenja → rezultat ALU). Dokument pokriva SAMO drugi od dva moguća pristupa:

1. Ručno instanciranje DSP48E1 primitive (kompleksan interfejs, ~40 portova) — NIJE
   obrađeno u dokumentu, i mi ga ne koristimo.
2. **Bihevijalni opis + `use_dsp` atribut** — alat (Vivado sintezni alat) sam prepoznaje
   `+`/`*` operatore i mapira ih na DSP48E1. Ovo je pristup koji koristimo.

## VHDL obrasci koji se mapiraju na DSP48

**Obavezan atribut** (bez njega alat MOŽDA neće mapirati na DSP, mada obično pokušava):
```vhdl
architecture Behavioral of my_module is
    attribute use_dsp : string;
    attribute use_dsp of Behavioral : architecture is "yes";
begin
```

**Sabirač** (kombinacioni, mapira se na ALU deo DSP ćelije):
```vhdl
res_o <= std_logic_vector(signed(a_i) + signed(b_i));
```

**Pipeline sabirač** (2 nivoa: ulazni registri → registrovan rezultat) — bitno je da se
operandi PRVO upišu u registre, pa se sabiranje/množenje radi NAD tim registrima u
sledećem taktu (to je jedini način da alat prepozna i iskoristi pipeline registre unutar
DSP ćelije):
```vhdl
process (clk) is
begin
    if rising_edge(clk) then
        a_reg_s <= a_i;
        b_reg_s <= b_i;
        p_reg_s <= std_logic_vector(signed(a_reg_s) + signed(b_reg_s));
    end if;
end process;
res_o <= p_reg_s;
```

**Množač sa 3 nivoa protočne obrade** (preporuka Xilinx-a za max performanse — ulaz →
rezultat množenja → propušten kroz ALU registar):
```vhdl
process (clk) is
begin
    if rising_edge(clk) then
        a_reg_s <= a_i;
        b_reg_s <= b_i;
        m_reg_s <= std_logic_vector(signed(a_reg_s) * signed(b_reg_s));
        p_reg_s <= m_reg_s;   -- mora proći kroz ALU registar DSP ćelije
    end if;
end process;
res_o <= p_reg_s;
```

**Ograničenje širine operanada:** ako je `WIDTHA <= 25` i `WIDTHB <= 18` → množač staje
u JEDNU DSP48E1 ćeliju. Ako su operandi širi → alat koristi više DSP ćelija + dodatnu
logiku (skuplje, sporije). **Uvek ciljati da operandi ostanu unutar 25×18.**

**Zadaci iz vežbe** (za referencu, ne moramo raditi generičku verziju — radimo direktno
na NCC): 1) analiza resursa 32×32 množača, 2) `multiply_accumulate` modul, 3) parametrizovan
FIR filtar sa MAC lancem (Slika 5 — akumulator + množač po tapu, isti obrazac koji nama
treba).

## Primena na NCC datapath — instrukcije za sebe

U `solve_single_point` (ncc.cpp:154-193) postoje TRI multiply-accumulate petlje koje se
izvršavaju za svaki od do `tmp_w*tmp_h` piksela prozora (do 900 puta za 30×30 šablon, i
to za SVAKU poziciju prozora u,v — ovo je najskuplji deo celog algoritma i glavni
kandidat za DSP48 mapiranje):

```c
sum_num   += diff_f * diff_t;   // MAC #1
sum_den_f += diff_f * diff_f;   // MAC #2 (poseban slučaj: a*a)
sum_den_t += diff_t * diff_t;   // MAC #3 (poseban slučaj: a*a)
```

**Širine operanada:** `pixel_t` je `uint8_t` (0..255), `template_mean`/`f_bar` su takođe
u tom opsegu → `diff_f`, `diff_t` stanu u **10-bitni signed** (opseg -255..255, dovoljno
9 bita + znak = 10 bita da bude bezbedno). Proizvod `diff_f * diff_t` je onda ≤ 20-bitni
signed → **staje u JEDAN DSP48E1** (10 ≤ 25, 10 ≤ 18 — čak i sa rezervom). Akumulacija
ide do 900 sabiranja proizvoda čija je apsolutna vrednost ≤ 255² = 65025 → suma stane u
~27 bita (900 × 65025 ≈ 58.5M) — 48-bitni ALU akumulator u DSP ćeliji ima ogromnu
rezervu, nema overflow rizika.

**Konkretan RTL obrazac za MAC jedinicu (jedna od tri, npr. sum_num):**
```vhdl
process (clk) is
begin
    if rising_edge(clk) then
        if load_new_window = '1' then
            acc_reg <= (others => '0');           -- reset akumulatora na start prozora
        elsif mac_enable = '1' then
            acc_reg <= acc_reg + (diff_f_reg * diff_t_reg);  -- MAC u jednom taktu
        end if;
    end if;
end process;
```

**Odluka za dizajn (FSMD, korak 2d/2e/3):** Pošto ista operacija (MAC) treba 3 puta po
svakom pikselu (sum_num, sum_den_f, sum_den_t), a piksela ima do 900 po pozivu — NE
instancirati 900 množača. Umesto toga: **3 fizičke MAC jedinice** (jedna po akumulatoru),
svaka iterira kroz piksele prozora takt-po-takt pod kontrolom FSM brojača (y,x), tačno
kao FIR filtar sa Slike 5 iz ove vežbe, samo bez pomeračkog registra (shift register) —
ovde se novi `diff_f`/`diff_t` par čita iz BRAM-a/registra svaki takt umesto da klizi kroz
liniju kašnjenja. Ovo direktno diktira broj taktova po pozivu `solve_single_point`
(≈ tmp_w×tmp_h + par taktova overhead za load/mean) — što se poklapa sa `K_CYC`
kalibracijom u `ncc.cpp` (linija 83).

## Bitne stvari / zamke na koje paziti

- Operande UVEK prvo upisati u registar pa tek onda množiti/sabirati nad registrovanim
  vrednostima — inače alat neće prepoznati pipeline strukturu DSP ćelije.
- `sum_den_f`/`sum_den_t` su oblika `a*a` (kvadrat) — i dalje ide na isti obrazac
  množača, samo sa oba ulaza DSP-a vezana na isti signal.
- **Deljenje NIJE multiply-accumulate** i ovaj dokument ga ne pokriva: `f_bar = sum_f /
  count`, `template_mean` (već `int`, prosek), i finalno `ncc2 = num_sq / den_prod` —
  ovo su prava deljenja (count i den_prod su runtime vrednosti, ne stepen dvojke) i
  zahtevaju **Vivado Divider Generator IP** ili iterativni deliteljski FSM, ne prost
  operator `/`. Ovo je posebna stavka za korak 3 (RTL), ne rešava se ovom vežbom.
- Pratiti širinu operanada — ako slučajno pustimo da `diff_f`/`diff_t` budu šire nego
  što treba (npr. pun 32-bitni `int` kao u C kodu), alat će nepotrebno trošiti više DSP
  ćelija po množenju. U RTL-u koristiti tačno onoliko bita koliko je stvarno potrebno
  (10-bit signed za diff, ne 32-bit).

## Mapiranje na korake iz bodovanja

- **Korak 3** (RTL modeling) — direktno diktira kako se piše VHDL za MAC jedinice u
  datapath-u.
- **Korak 5a** (analiza utrošenih resursa posle sinteze) — očekujemo da izveštaj pokaže
  DSP48E1 utilizaciju umesto LUT-based multiply logike; ako se to ne desi, proveriti da
  li je `use_dsp` atribut ispravno postavljen i da li su operandi u dozvoljenim
  širinama (25×18).
