# Vezba 2 — Hijerarhijski/parametrizovani dizajn, Datapath i Controlpath

Izvor: `06 Prilozi/Vezbe/Vezba-2-Hierarchical-and-Parametrized-Design-Datapath-and-Controlpath-Design.pdf`

## Šta ova vežba pokriva

Dva poglavlja (2 i 3 iz skripte):
- **Hijerarhijski i parametrizovani dizajn** — particionisanje sistema na module (na nivou sistema → IP jezgra → unutar IP jezgra na datapath/controlpath → RT komponente), plus VHDL `generic`/`generate` mehanizmi za parametrizaciju širine i ponašanja.
- **Projektovanje datapath i controlpath modula** — opšta struktura datapath-a (mreža za rutiranje ulaza → funkcionalne jedinice → mreža za rutiranje rezultata → memorijski elementi), controlpath kao **konačni automat (FSM)**, dve reprezentacije FSM-a (dijagram stanja i **ASM dijagram**), i dve arhitekture za realizaciju FSM-a (**Random Logic** i **mikroprogramirana**).

Ovo je DIREKTNO metodologija za korake 2b/2d/2e/3 iz bodovanja — nema drugog puta, ovo je taj put.

## Metodologija (opšta, iz vežbe)

1. **Particioniši IP modul na datapath i controlpath.** Datapath radi transformacije nad podacima (sabiranje, množenje, poređenje...), controlpath je FSM koji generiše redosled upravljačkih signala za datapath.
2. **Datapath ima uvek istu opštu strukturu** (slika 3.1 u vežbi):
   `ulazni podaci → [mreža za rutiranje ulaza (mux-evi)] → [funkcionalne jedinice (ALU: sabirač/množač/delitelj/komparator)] → [mreža za rutiranje rezultata (mux-evi)] → [memorijski elementi (registri)] → izlazni podaci`
   plus **statusni izlazi** (npr. `=0`, `overflow`) koji idu ka controlpath-u, i **kontrolni ulazi** koji dolaze iz controlpath-a (biraju mux-eve, enable-uju registre).
3. **Controlpath se uvek realizuje kao FSM.** Prvo se specificira dijagramom stanja ILI ASM dijagramom (ASM je pogodniji jer mreža test blokova liči na blok-dijagram algoritma — lakše se prevodi direktno iz C koda sa petljama i if-ovima).
4. **ASM blok = state blok (Murovi izlazi) + test blokovi (grananje, T/F) + uslovni izlazni blokovi (Milijevi izlazi).** Petlja u algoritmu → **self-loop na test bloku** koji proverava brojač petlje i grana se: ako uslov nije ispunjen, ostani u istom stanju i inkrementuj brojač (kao `idle` self-loop na `not mem` u primeru memorijskog kontrolera); ako jeste, pređi dalje. Ovo je KLJUČNO za "uklanjanje petlji" (korak 2b) — petlja se ne unroluje kroz N stanja, već postaje JEDNO stanje sa self-loop granom + brojač-registar u datapath-u.
5. **Realizacija FSM-a:** Random Logic (kombinaciona logika za next-state, direktno iz ASM-a — koristi se kad broj stanja nije ogroman, što je naš slučaj) ili mikroprogramirana (memorija mikroinstrukcija — korisna kad ima MNOGO sličnih stanja, verovatno preterano za NCC).
6. **Testbench** se piše odmah uz svaki model (nije naknadna faza) — svaki zadatak u vežbi traži i model i testbench.

## Primena na NCC algoritam — instrukcije za sebe

Referenca algoritma: `src/ncc.cpp` (`build_integral_image`, `calculate_template_mean`, `compute_full_matrix`, `solve_single_point`).

### Datapath — šta mi treba

**Memorijski elementi (registri):**
- Konfiguracioni: `img_w`, `img_h`, `tmp_w`, `tmp_h`, `img_addr`, `tmp_addr` (upisuju se preko AXI-Lite, već postoje kao "registri" u `common.hpp`)
- Brojači petlji: `u`, `v` (pozicija prozora), `x`, `y` (pozicija piksela unutar prozora/šablona) — OVO su registri koji zamenjuju C `for` petlje
- Akumulatori: `sum_num`, `sum_den_f`, `sum_den_t` (moraju biti dovoljno široki — videti napomenu o širini niže), `row_sum` (za SAT gradnju)
- Rezultati po fazi: `f_bar`, `template_mean`
- BRAM/memorijski portovi: `integral[]` (SAT, veličine (img_w+1)×(img_h+1) — razmotriti da li ovo mora biti puna memorija ili se može strimovati red-po-red), `image[]`, `templ[]`, `result_map[]`

**Funkcionalne jedinice (ALU):**
- Sabirač/oduzimač: za `diff_f = pixel - f_bar`, `diff_t = tmpl - template_mean`, `row_sum += pixel`, `integral[...] = ... + ...` (4 vrednosti za SAT čitanje), inkrement brojača petlji
- Množač: `diff_f * diff_t` (multiply-accumulate → sum_num), `diff_f*diff_f` (→ sum_den_f), `diff_t*diff_t` (→ sum_den_t), `sum_num*sum_num`, `sum_den_f*sum_den_t` — **ovo su 5 množenja, kandidat za DSP48 inferring (videti napomenu Vežba Inferring_VHDL_to_DSP)**
- Delilac: `num_sq / den_prod` na kraju — **najskuplji element datapath-a, razmotriti pipeline/iterativni delilac umesto kombinacionog**
- Komparator: `u < res_w`, `v < res_h`, `x < tmp_w`, `y < tmp_h` (test blokovi u ASM-u), `sum_den_f == 0`, `sum_den_t == 0`

**Mreže za rutiranje:** mux na ulazu ALU-a bira između: konstante 0 (reset akumulatora), trenutne vrednosti registra (akumulacija), izlaza iz BRAM porta (novi piksel). Kontrolni ulazi mux-eva dolaze iz FSM-a (npr. `sel_acc_reset`, `sel_acc_add`).

**Parametrizacija (generic):** `img_w`/`img_h`/`tmp_w`/`tmp_h` NISU generic (menjaju se u runtime-u preko registara — to je razlika od Zadatka 2.2 gde su M/N generic konstante). Ono što BI moglo biti generic: širina fixed-point registara (Q1.31 → generic `RESULT_WIDTH`), širina piksela (8 bita, generic `PIXEL_WIDTH`) — korisno ako se ista IP jezgro instancira dvaput (ncc0, ncc1) sa istim parametrima ili ako se kasnije menja rezolucija.

### Controlpath — FSM (ASM dijagram, nacrt stanja)

Direktno iz `ncc_proc()` (ncc.cpp:77-115), sa petljama pretvorenim u self-loop + brojač po metodologiji iz vežbe:

```
IDLE          -- Murov izlaz: ready<=1, status<=BUSY_ne_još
  test: start=1?  F -> ostani IDLE
                  T -> pređi dalje, status<=0 (BUSY)

CHECK_DIRTY   test: img_dirty=1?  F -> LOAD_TMPL
                                   T -> LOAD_IMG (y<=0)

LOAD_IMG      -- čita image[y*img_w+x] iz BRAM-a, self-loop dok (y,x) ne pređu img_w*img_h
  (ovo je zapravo dve ugnježdene petlje x,y — u ASM-u: jedan state blok, dva test bloka
   ugnježdena: x<img_w-1? (T: x++, ostani) F: y<img_h-1? (T: y++, x<=0, ostani) F: dalje)

BUILD_SAT     -- self-loop nad (y,x), računa integral[] = row_sum akumulacija (linije 128-138)
                 isti obrazac ugnježdenih test blokova kao LOAD_IMG

LOAD_TMPL     -- self-loop, čita templ[] iz BRAM-a, akumulira sum (za mean)
CALC_MEAN     -- jedan takt: template_mean <= (sum + n/2) / n  (deljenje - videti napomenu)

COMPUTE_V     -- v<=0 (spoljna petlja prozora)
COMPUTE_U     -- u<=0 (unutrašnja petlja prozora)
READ_SAT      -- 4 pristupa integral[], O(1) f_bar (jedan ili par taktova)
PIXEL_LOOP    -- self-loop nad (y,x) unutar šablona: diff_f, diff_t, akumulacija
                 sum_num/sum_den_f/sum_den_t (linije 171-180) — NAJDUŽE stanje po broju
                 iteracija (tmp_w*tmp_h, do 900 za 30x30)
NCC_CALC      -- deljenje num_sq/den_prod, skaliranje Q1.31, upis u result_map[v*res_w+u]
NEXT_U        test: u<res_w-1? T: u++, nazad na COMPUTE_U/READ_SAT
                     F: test v<res_h-1? T: v++, u<=0, nazad na COMPUTE_U
                                        F: dalje -> DONE
DONE          -- Murov izlaz: status<=1 (DONE), jednokratni "interrupt" (done_ev ekvivalent)
                 bezuslovno nazad na IDLE
```

**Ovo je nacrt za ASM dijagram koji treba nacrtati u dokumentaciji (korak 2d)** — pri stvarnom crtanju koristiti tačnu notaciju iz vežbe (state blok/test blok/uslovni izlazni blok, T/F grane, Murovi izlazi unutar state bloka).

## Bitne stvari / zamke na koje paziti

- **Ne unrolovati petlje u N stanja.** `PIXEL_LOOP` ima do 900 iteracija — to je JEDNO ASM stanje sa self-loop granom, ne 900 stanja. Ovo je suština "uklanjanja petlji" (korak 2b): algoritamska petlja postaje brojač-registar + test blok + self-loop, ne razvijena sekvenca stanja.
- **Deljenje (division) je najskuplji operator** — `calculate_template_mean` i `solve_single_point` oboje dele. Kombinacioni delilac je skup/spor; razmotriti iterativni (restoring/non-restoring) delilac koji troši više taktova ali manje resursa, ili shift-based aproksimaciju ako je moguće. Ovo direktno utiče na broj stanja u FSM-u (deljenje može zahtevati sopstvenu multi-ciklusnu sekvencu, slično kao SRAM read/write u primeru iz vežbe).
- **Q1.31 fixed point** — `num_sq` i `den_prod` su do 64-bitni (uint64_t u C kodu) pre finalnog deljenja. Širina sabirača/množača u datapath-u mora ovo pratiti (64-bitni akumulatori/množači su realni resursni trošak — bitno za korak 5a analizu resursa).
- **SAT (integral image) memorija** — `integral[]` je (img_w+1)×(img_h+1) 64-bitnih vrednosti. Za 90×90 sliku to je 91×91×8B ≈ 66KB — proveriti da li staje u BRAM/URAM na ciljanoj Zynq ploči ili mora ići u DDR (dodatna kompleksnost u datapath interfejsu ako ide u DDR).
- **Dva NCC bloka (ncc0, ncc1) = ista IP jezgro instancirano dvaput** — datapath/controlpath dizajn se radi JEDNOM, IP se samo instancira dvaput u block design-u (korak 7). Nema potrebe za dva različita RTL dizajna.
- **Murovi vs Milijevi izlazi:** `status`/`ready` izlazi (koje čita CPU preko AXI-Lite) treba da budu **Murovi** (bez gliceva, stabilni) — Milijevi izlazi su za brze interne reakcije unutar datapath-a (npr. mux select signali), ne za spoljašnji AXI interfejs.

## Mapiranje na korake iz bodovanja

- **2b** (uklanjanje petlji): odeljak "Controlpath — FSM" iznad, self-loop + brojač obrazac
- **2d** (ASM dijagram): nacrt stanja iznad je osnova, treba ga precrtati u pravoj ASM notaciji
- **2e** (blok dijagram datapath/controlpath): odeljak "Datapath — šta mi treba" iznad + generalna struktura sa slike 3.1/3.3 iz vežbe kao template za crtanje
- **3** (RTL model): kad se ASM dijagram finalizuje, prevesti ga u VHDL FSM (Random Logic arhitektura — vidi 3.2.1 u vežbi za VHDL šablon strukture: logika za naredno stanje + registar stanja + logika za Murove/Milijeve izlaze) + datapath VHDL (registri + ALU + mux-evi, moguće kao strukturni model sa zasebnim entitetima po funkcionalnoj jedinici, po uzoru na Zadatak 3.1c)
