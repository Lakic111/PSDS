# Vezba 3-5 — RT Modeling

Izvor: `06 Prilozi/Vezbe/Vezba-3-5-RT-Modeling.pdf` (Glava 4, "RT modelovanje", 60 strana — kompletno pročitano).

## Šta ova vežba pokriva

Formalni postupak (RT = Register Transfer metodologija) da se proizvoljni algoritam
prevede u digitalno kolo: **datapath** (registri + funkcionalne jedinice + mreže za
rutiranje) + **controlpath** (konačni automat = FSM). Ovo je metod koji profesor
očekuje da se koristi — **ručni RTL iz ASMD dijagrama, ne HLS**. Direktno pokriva
korak 2b (uklanjanje petlji), 2c (interfejs), 2d (ASM dijagram), 2e (blok dijagram) i
korak 3 (RTL) + korak 4 (verifikacija) iz bodovanja.

## Generička arhitektura (uvek ista dva bloka)

```
                    Datapath
  Ulazni podaci -> [Mreža rutiranja ulaza] -> [Funkcionalne jedinice] -> [Mreža rutiranja rezultata] -> [Registri] -> Izlazni podaci
                         ^                                                        ^
                    Kontrolni signali                                    Unutrašnji statusni signali
                    (iz Controlpath-a)                                   (u Controlpath)

                    Controlpath (FSM)
  Komande -> [Logika narednog stanja] -> [Registar stanja] -> [Izlazna logika] -> Status
```

- **Datapath** interfejsi: ulazni podaci, izlazni podaci, kontrolni ulaz (od FSM-a), statusni izlaz (ka FSM-u)
- **Controlpath** interfejsi: komandni ulaz (`start` i sl.), statusni izlaz (`ready` i sl.), kontrolni izlaz (ka datapath-u), statusni ulaz (od datapath-a — npr. `count_0`, komparatori)
- **KRITIČNO:** i u `idle` stanju postoje (trivijalne) RT operacije (`registar ← registar`) — moraju se modelovati (default assignments u VHDL-u), inače je dizajn funkcionalno pogrešan.

## Postupak projektovanja (5 koraka, redosled bitan)

1. **Eliminacija naredbi ponavljanja** — `for`/`while`/`repeat` → `if`-`goto` (jer ASMD ne ume da modeluje petlje).
2. **Definisanje interfejsa** — 4 interfejsa: ulazni podaci, izlazni podaci, komandni (`start` min.), statusni (`ready` min.). Širina izlaznih portova se izvodi funkcionalnom vezom iz širine ulaza (npr. proizvod n×m bita treba n+m bita izlaza).
3. **Projektovanje controlpath-a** — ASMD dijagram iz modifikovanog algoritma. Ako više RT operacija deli isto stanje (state blok) i nema data dependency među njima i ima dovoljno funkcionalnih jedinica → izvršavaju se **u paraleli, u istom taktu**. Ovo je mesto gde se bira brzina-vs-resursi kompromis.
4. **Projektovanje datapath-a** (4 podkoraka):
   1. Identifikuj sve unutrašnje promenljive → registri (odredi širinu svakog).
   2. Grupiši RT operacije po **odredišnom registru**.
   3. Za svaku grupu: ciljni registar + kombinaciona mreža za svaku transformaciju + multiplekser (ako registar ima >1 moguću RT operaciju, selekcija = **trenutno stanje FSM-a**, doslovno `state_reg` kao selekcioni signal multipleksera).
   4. Dodaj kombinacione mreže za statusne izlaze (komparatori sa 0 i sl.) koje idu nazad u controlpath.
5. **Pisanje HDL modela** — spoji datapath + controlpath u jedan ili više entiteta.
6. **(dodatni, iz primera 3) Verifikacija** — testbench sa clock/reset generatorima + stimulus proces + DUT.

**Bitna tehnička napomena o `_next` signalima:** pošto nova vrednost registra postaje
dostupna tek u NAREDNOM taktu, ako ti treba unutar TEKUĆEG takta (npr. da odlučiš
da li petlja treba još jednu iteraciju), moraš koristiti `_next` (izlaz kombinacione
mreže), ne `_reg` (izlaz registra). Ovo je čest izvor grešaka.

## VHDL obrazac — dvoprocesni stil (preporučeni template za NCC)

Iz primera "Add-and-Shift" množača (parametrizovan sa `generic WIDTH`), najčistiji i
najbliži onome što treba za NCC IP:

```vhdl
entity add_and_shift_mult is
  generic (WIDTH: integer := 8);
  port (
    clk: in std_logic;
    reset: in std_logic;
    a_in: in std_logic_vector(WIDTH-1 downto 0);
    b_in: in std_logic_vector(WIDTH-1 downto 0);
    r_out: out std_logic_vector(2*WIDTH-1 downto 0);
    start: in std_logic;
    ready: out std_logic);
end entity;

architecture two_seg_arch of add_and_shift_mult is
  type state_type is (idle, add, shift);
  signal state_reg, state_next: state_type;
  signal a_reg, a_next: unsigned(WIDTH-1 downto 0);
  -- ... ostali registri
begin
  -- Proces 1: state + data registri (samo clk/reset, upisuje _reg <= _next)
  process (clk, reset)
  begin
    if reset = '1' then
      state_reg <= idle; -- + svi _reg <= 0
    elsif (clk'event and clk = '1') then
      state_reg <= state_next; -- + svi _reg <= _next
    end if;
  end process;

  -- Proces 2: kompletna kombinaciona logika (next-state + datapath next + izlazi)
  process (state_reg, start, a_in, b_in, a_reg, b_reg, ...)
  begin
    -- DEFAULT ASSIGNMENTS PRVO (bitno! sprečava latch-eve i pokriva idle trivijalne RT operacije)
    a_next <= a_reg;
    b_next <= b_reg;
    ready <= '0';
    case state_reg is
      when idle =>
        ready <= '1';
        if start = '1' then
          a_next <= a_in;
          -- ...
          state_next <= add; -- ili shift, zavisno od statusnog signala
        else
          state_next <= idle;
        end if;
      when add => ...
      when shift => ...
    end case;
  end process;

  r_out <= std_logic_vector(p_reg); -- izlaz direktno iz registra
end two_seg_arch;
```

Ovaj **dvoprocesni stil** (1 proces = registri, 1 proces = sva kombinaciona logika sa
default assignments na vrhu) je čistiji od višeprocesnog stila iz prvog primera i
preporučen je za NCC IP.

## Memorijski interfejs — NAJRELEVANTNIJI primer za NCC (Naive Matrix Multiplier)

Ovo je najvažniji deo vežbe za nas jer NCC, kao i matrični množač, mora da čita iz
**više odvojenih memorija** (kod nas: slika/segment, šablon, integral image, rezultati)
umesto da radi sa skalarnim ulazima na portovima.

Ključna lekcija (Design Space Exploration, sekcija 4.19a-4.19f): broj memorijskih
pristupa po iteraciji unutrašnje petlje direktno određuje broj taktova, i tu se bira
kompromis brzina/resursi:
- Sve u 1 jednopristupnoj memoriji → 5 taktova/iteracija (najgore, ali najjeftinije)
- 2 odvojene jednopristupne memorije (A+B zajedno, C posebno) → 3 takta/iteracija (40% brže)
- 2 dvopristupne memorije → 2 takta/iteracija (60% brže, ali skuplje)
- 3 odvojene jednopristupne memorije (A, B, C svaka svoja) → **2 takta/iteracija, ali BEZ potrebe za dvopristupnim memorijama** — ovo je "sweet spot" i tačno arhitektura koju treba kopirati za NCC (odvojene memorije za sliku, šablon, integral, rezultat).

**Optimizacija koja se direktno primenjuje na NCC:** umesto da se `c(i,j)` čita/piše iz
memorije u SVAKOM prolasku unutrašnje petlje, uvodi se lokalni akumulatorski registar
`temp` koji se ažurira kroz petlju i upisuje u memoriju TEK na kraju. **Naš SystemC
kod već radi ovo** — `sum_num`, `sum_den_f`, `sum_den_t` u `solve_single_point` su
tačno takvi `temp` akumulatori, ne memorijske lokacije. Ovo potvrđuje da je algoritam
već u obliku pogodnom za RT metodologiju bez dodatnih izmena.

Memorijski interfejs (port po memoriji) izgleda ovako (iz primera, prilagoditi imena):
```vhdl
-- Interfejs ka jednoj jednopristupnoj memoriji (npr. memorija slike)
a_addr_o: out std_logic_vector(ADDR_WIDTH-1 downto 0);
a_data_i: in  std_logic_vector(WIDTH-1 downto 0);
a_wr_o:   out std_logic;
```

ASMD dijagram za ovakav sistem ima stanja koja postavljaju adresu **jedan takt pre**
nego što je podatak validan (jer je čitanje iz sinhrone memorije registrovano), pa
prochitani podatak `a_data_i` postaje dostupan tek u NAREDNOM stanju — ovo je isti
problem kao NCC-ov `read_from_bram` koji čeka `delay` pre upotrebe podatka.

## Verifikacija / testbench — obrazac

Struktura (iz "Naive" matrix multiplier primera, sekcija Korak 6):
```
stim_gen (proces) ---> DUT (matrix_mult) ---> memorije (dp_memory instance, dual-port)
clk_gen  (proces) --/
```
- `clk_gen`: `process begin clk_s <= '0', '1' after T/2; wait for T; end process;`
- `stim_gen`: `process begin reset<='1'; wait; reset<='0'; [upiši test podatke u memorije preko porta 1]; start<='1'; wait until falling_edge(clk); start<='0'; wait until ready_s='1'; wait; end process;`
- Memorije su **dual-port** u testbench-u (port 1 = testbench upisuje test podatke, port 2 = DUT čita/piše) — ovo rešava problem "ko puni memoriju pre starta".
- Verifikacija = inspekcija talasnih oblika / vrednosti signala nakon simulacije (WaveForm viewer), poređenje sa ručno izračunatom očekivanom vrednošću.

**Za NCC:** testbench treba da upiše poznatu sliku + šablon u "BRAM" memorijske
modele, pokrene IP, i uporedi `result_map` sa golden vrednošću (iz C funkcije iz koraka
1, ili čak iz postojećeg SystemC modela za iste ulaze — dupla provera).

## Primena na NCC IP — konkretne instrukcije za sebe

1. **Interfejs (korak 2c već imamo)** — mapiraj `common.hpp` registre direktno:
   - Komandni/statusni interfejs = `REG_CTRL` (start), `REG_STATUS` (ready/busy) — kao AXI-Lite registri umesto direktnih portova
   - "Ulazni podaci" nisu na portovima nego se ČITAJU preko master interfejsa iz BRAM-a (kao `a_data_i`/`a_addr_o` par) — NCC treba SVOJ memorijski master port (adresa + read data), tačno kao `a_addr_o`/`a_data_i` iz primera
   - `REG_IMG_W/H`, `REG_TMP_W/H`, `REG_IMG_ADDR`, `REG_TMP_ADDR` su deo komandnog interfejsa (konfiguracija pre starta, kao `n_in`/`p_in`/`m_in` u matrix multiplier primeru)
2. **Uklanjanje petlji (korak 2b)** — `ncc.cpp` petlje treba pretvoriti u `if`-`goto` formu:
   - `build_integral_image`: dvostruka petlja (y,x) → dva ugnježdena stanja/brojača
   - `compute_full_matrix`: dvostruka petlja (v,u) → dva brojača (spolja: pozicija prozora)
   - `solve_single_point`: dvostruka petlja (y,x unutar prozora) → dva brojača (unutra: akumulacija po šablonu)
   - Rezultat: **4 ugnježdena brojača ukupno** (v, u, y, x) — sličan obrazac kao Naive Matrix Multiplier (i, j, k) ali sa jednim nivoom više ugnježdenosti.
3. **ASMD dijagram (korak 2d)** — skeleton stanja (proširiti FSM iz `ncc_proc()`):
   `idle → [load_img ako img_dirty, sa sopstvenim brojačem za build_integral] → load_tmpl → calc_mean → l_v (spoljna petlja po v) → l_u (petlja po u, računa f_bar iz SAT-a O(1)) → l_yx (unutrašnja petlja po y,x — akumulira sum_num/sum_den_f/sum_den_t) → upis rezultata u memoriju rezultata → nazad na l_u ili l_v → idle`
4. **Datapath (korak 2e)** — registri: `v,u,y,x` (brojači), `f_bar`, `template_mean`, `sum_num`, `sum_den_f`, `sum_den_t` (akumulatori — TAČNO kao `temp` iz matrix multiplier primera), plus integral image kao odvojena memorija. Funkcionalne jedinice: 2× oduzimač (diff_f, diff_t), 2-3× množač (diff_f×diff_t, diff_f², diff_t², i za NCC² na kraju), sabirač-akumulator, delilac (za NCC² razlomak — ovo je najskuplji resurs, razmotriti da li ima smisla deliti u HW ili raditi poređenje unakrsnim množenjem: `num_sq/den_prod > threshold` ⟺ `num_sq > threshold*den_prod`, izbegava se deljenje ako je moguće).
5. **Memorije (odvojene, po uzoru na "3 memorije" arhitekturu)**: slika/segment (read), šablon (read), integral image (read/write — gradi se pa se čita), rezultat (write). Ovo direktno odgovara postojećem SystemC modelu gde su `image`, `templ`, `integral`, `result_map` odvojeni `std::vector`-i.

## Bitne zamke na koje paziti

- Ne zaboraviti trivijalne RT operacije u `idle` (default assignments u VHDL-u pokrivaju ovo automatski ako se rade PRVO u kombinacionom procesu).
- Koristiti `_next` vrednosti kad je informacija potrebna U ISTOM taktu (npr. provera kraja petlje odmah nakon inkrementa brojača) — ovo se direktno odnosi na proveru `k == m_in` tipa uslova u NCC petljama.
- Deljenje resursa (Resource Sharing) — ako iste operacije (npr. množač) koriste više RT operacija u različitim stanjima, treba mreža za rutiranje ulaza (multiplekser NA ULAZU funkcionalne jedinice, ne samo na izlazu). NCC ima 3 množenja po iteraciji (diff_f×diff_t, diff_f², diff_t²) — pitanje je da li deliti jedan množač (manje resursa, sporije, treba mreža rutiranja ulaza) ili imati 3 odvojena množača (brže, 3x DSP48 blokova, videti i belešku o `Inferring_VHDL_to_DSP.pdf`).
- Adresa memorije se mora postaviti JEDAN TAKT PRE nego što je pridruženi podatak validan (sinhrona memorija) — ASMD mora imati stanje/prelaz koji ovo modeluje, inače se čita pogrešan podatak.

## Mapiranje na korake iz bodovanja

- **Korak 2b** (uklanjanje petlji): direktno primenjeno u sekciji "Primena na NCC IP" tačka 2.
- **Korak 2c** (interfejs i okruženje): tačka 1 iznad — potvrđuje da postojeći `common.hpp` registarski interfejs je već u dobrom obliku za ovaj korak.
- **Korak 2d** (ASM dijagram): tačka 3 iznad daje skeleton.
- **Korak 2e** (blok dijagram datapath/controlpath): tačka 4 iznad.
- **Korak 3** (RTL modelovanje): VHDL template (dvoprocesni stil) + memorijski interfejs obrazac su spremni za direktnu upotrebu.
- **Korak 4** (simulacija/verifikacija): testbench obrazac (clk_gen/stim_gen/dual-port memorije za punjenje test podataka) je spreman predložak.
