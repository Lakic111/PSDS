# Vezba 8-9 — IP Packaging

Izvor: `06 Prilozi/Vezbe/Vezba-8-9-IP-Packaging.pdf` (= Glava 6 udžbenika, "Projektovanje IP jezgara", str. 229-316)

**Napomena:** ovaj PDF pokriva SAMO korak 6 (pakovanje u IP jezgro) — kompletno i vrlo detaljno, kroz primer "Naive" množača matrica. **Ne sadrži** materijal o integraciji u block design sa Zynq PS/BRAM Controller/DMA (korak 7) — taj deo mora doći iz drugog izvora (verovatno Vezba 9 posebno, ili je deo neke druge vežbe koju još nemam). Zadaci za vežbu na kraju (6.1-6.4) su isti obrazac primenjen na druge algoritme (sqrt, binarna pretraga, najbliži prosjeku, selection sort).

## Šta ova vežba pokriva

- AXI porodica interfejsa: **AXI-Full** (blok transferi do 256 reči, burst adresiranje fixed/incr/wrap), **AXI-Lite** (samo 1 podatak po transakciji, manje signala, jednostavniji HW), **AXI-Stream** (bez adrese, čist tok podataka, unidirekciono).
- Tipična struktura IP jezgra (slika 6.10-6.12): **modul za hardversku implementaciju algoritma** (RT dizajn iz glave 4, nestandardan interfejs) + **memorijski podsistem** (registri i/ili RAM-ovi i/ili FIFO-ovi za ulaze/izlaze algoritma) + **I/O kontroler(i)** (AXI-Lite/Full/Stream, automatski generisani od strane Vivado IP Packager-a) = "wrapper" oko algoritma.
- Kompletan hodočasnički primer: pakovanje "Naive" množača matrica u `axi_matrix_multiply` IP sa AXI-Lite (5 registara: n, m, p, cmd, status) + AXI-Full (memorije A, B, C).
- 8-koračni Package IP proces (Identification → Compatibility → File Groups → Customization Parameters → Ports and Interfaces → Addressing and Memory → Customization GUI → Review and Package) + generisanje verifikacionog testbench-a.

## Koraci pakovanja IP-a (Package IP wizard)

1. Napraviti prazan Vivado projekat (ime po IP-u, npr. `ncc_core`).
2. `Tools → Create and Package IP...` → **Create a new AXI4 peripheral** (ne "Package current project", jer želimo da wizard automatski generiše AXI kontrolere).
3. **Peripheral Details**: Name, Version, Display name, Description, IP location.
4. **Add Interfaces**: za svaki potreban interfejs definisati:
   - `Name` (prefiks signala, npr. `S00_AXI`, `S01_AXI`, `M00_AXI`)
   - `Interface Type` (Lite / Full / Stream)
   - `Interface Mode` (**Master ili Slave** — bitno: wizard PODRŽAVA generisanje master kontrolera, ne samo slave!)
   - `Data Width`
   - `Memory Size` (samo Full/Stream — gornja granica adresnog prostora IP-a)
   - `Number of Registers` (samo Lite — broj pojedinačnih registara)
5. **Create Peripheral** prozor → izabrati **"Edit IP"** (ne "Add IP to repository" direktno) jer treba ručno dopuniti automatski generisani skelet.
6. Finish → Vivado otvara privremeni projekat sa 3 auto-generisana VHDL fajla:
   - `<ip>_v1_0` — strukturni model najvišeg nivoa (nekompletan wrapper)
   - `<ip>_v1_0_S00_AXI` — AXI-Lite kontroler (samo protokol logika, bez veze ka registrima)
   - `<ip>_v1_0_S01_AXI` — AXI-Full kontroler (samo protokol logika, bez veze ka memoriji)
7. **Ručno napisati/dodati**: memorijski podsistem (VHDL), sam algoritam (RT dizajn iz ranije glave), `utils_pkg` (log2c i sl. helper funkcije).
8. **Ručno modifikovati auto-generisani AXI-Lite kontroler**: dodati generic-e, dodati portove `*_wr_o`/`*_axi_i` po registru, izbaciti `slv_reg1..N` signale i zameniti ih direktnim write-enable po registru (case na `loc_addr`) i direktnim čitanjem iz `*_axi_i` ulaza (case na `loc_addr` za read mux).
9. **Ručno modifikovati auto-generisani AXI-Full kontroler**: dodati `mem_addr_o`, `mem_data_o`, `mem_wr_o` (ili `_i` za master smer) portove, povezati burst adresu/podatak na memorijski interfejs (`mem_addr_o <= axi_araddr(...) when arv_arr_flag='1' else axi_awaddr(...) when awv_awr_flag='1'`).
10. **Ručno modifikovati top-level wrapper**: instancirati memorijski podsistem + algoritam + oba (sva) AXI kontrolera, povezati signale.
11. `Add Sources` u projekat: memorijski podsistem, algoritam, utils_pkg (ako ih čarobnjak ne vidi, koristiti **"Merge changes from File Groups Wizard"** dugme koje automatski ubacuje ručno dodate fajlove u `VHDL Synthesis`/`VHDL Simulation` grupe).
12. Napisati i pokrenuti **verifikacioni testbench** (vidi sekciju ispod) pre pakovanja.
13. U `Package IP` kartici proći kroz 8 koraka (`Packaging Steps`):
    - **Identification**: Vendor, Library, Name, Version, Description, **Categories** (npr. `AXI_Peripheral` + specifična kategorija).
    - **Compatibility**: izabrati FPGA familiju (za nas: **Zynq**).
    - **File Groups**: proveriti da su svi fajlovi u `VHDL Synthesis` grupi (koristiti "Merge changes..." ako čarobnjak signalizira).
    - **Customization Parameters**: generic-e podeliti u `Customization Parameters` (vidljivi korisniku, sa `Specify Range`) vs `Hidden Parameters` (fiksni, obično svi auto-generisani AXI parametri idu ovde). Koristiti "Merge changes from Customization Parameters Wizard" da se novi generic-i pokupe, zatim ih ručno prebaciti/konfigurisati preko `Edit Parameter`.
    - **Ports and Interfaces**: čarobnjak automatski prepoznaje definisane AXI interfejse — obično nema šta da se menja ako nismo ručno dodavali portove van wizard-a.
    - **Addressing and Memory**: interna memorijska mapa (preskočiti ako nije potrebno).
    - **Customization GUI**: izgled prozora za konfigurisanje IP-a (preskočiti za default izgled).
    - **Review and Package**: **obavezno uključiti "Create archive of IP"** (opcija je default isključena!) preko "edit packaging settings" → Project Settings → IP → Packager tab.
14. `Package IP` dugme → generiše `.zip` arhivu + dodaje IP u IP Catalog tekućeg projekta.
15. Instanciranje: `IP Catalog` → dvoklik na IP → `Customize IP` prozor (prikazuje SAMO vidljive `Customization Parameters`, npr. WIDTH/SIZE) → `Generate`.

## Primena na NCC IP — instrukcije za sebe

Naš NCC IP se **razlikuje** od primera iz udžbenika po jednoj ključnoj stvari: matrix-multiply primer čuva SVE ulaze/izlaze (A, B, C) u memorijama UNUTAR IP-a, pristupačnim CPU-u preko AXI-Full **slave**. Naš NCC:
- **NE** čuva sliku/šablon unutar sebe — čita ih sam iz **spoljašnjeg** deljenog BRAM-a preko `i_bram` mastera (`ncc.hpp:12`). Ovo znači da treba **AXI-Full (ili AXI4) MASTER** interfejs, ne slave — koristiti `Interface Mode = Master` u "Add Interfaces" koraku (5 iznad). Kontroler generisan za master mora se ručno napuniti FSM-om koji generiše AR/AW transakcije prema BRAM Controller-u u block dizajnu (ovo NIJE pokriveno primerom iz vežbe — istražiti posebno, verovatno u dokumentaciji Xilinx "AXI Reference Guide" ili idućoj vežbi o integraciji).
- **REGISTAR interfejs** (REG_IMG_W, REG_IMG_H, REG_TMP_W, REG_TMP_H, REG_IMG_ADDR, REG_TMP_ADDR, REG_CTRL, REG_STATUS = **8 registara**) → jedan **AXI-Lite slave** sa `Number of Registers = 8`. Isti obrazac kao `n`,`m`,`p`,`cmd`,`status` u primeru — svaki registar dobija `*_wr_o` (write enable iz AXI-Lite kontrolera ka memorijskom podsistemu) i `*_axi_i` (read-back ulaz iz memorijskog podsistema ka AXI-Lite kontroleru).
- **ADDR_RESULTS (result_map)** je NIZ (int32 po poziciji prozora, promenljive dužine do ~61×61 za najveći slučaj) → analogno matrici C iz primera: interna dvopristupna memorija, CPU je čita burst-om preko **AXI-Full SLAVE** interfejsa (drugi interfejs, `S01_AXI` po analogiji). Jedan pristup memorije ide ka AXI-Full kontroleru (za CPU čitanje), drugi ka NCC datapath-u (upis rezultata tokom `solve_single_point`).
- Dakle NCC IP treba **3 AXI interfejsa**: 1× AXI-Lite slave (kontrola), 1× AXI-Full slave (rezultati), 1× AXI-Full (ili Full/Lite, videti dole) master (čitanje slike/šablona iz spoljašnjeg BRAM-a).
- **Generic parametri** (analogno WIDTH/SIZE): npr. `MAX_IMG_DIM`, `MAX_TMP_DIM` — koriste se za dimenzionisanje interne rezultatske memorije i adresnog dekodera. **Voditi računa** (kao u primeru sa SIZE≤8 → 256 elemenata): maksimalna dimenzija implicitno ograničava veličinu adresnog prostora AXI-Full interfejsa (`Memory Size` polje) — mora se odabrati dovoljno velika da pokrije najveći segment (90×90 u našem slučaju, ili čak veći radi rezerve).
- **Testbench za NCC** treba da prati isti obrazac kao `axi_matrix_mult_tb` (vidi ispod), ali dodatno mora simulirati AXI-Full MASTER stranu (mock BRAM slave koji odgovara na NCC-ove AR/AW zahteve za sliku/šablon) — ovo je dodatna komponenta koje NEMA u primeru iz vežbe.

## Obrazac verifikacionog testbench-a (iz primera, primeniti na NCC)

1. Reset AXI-Lite (10 taktova), zatim release.
2. AXI-Lite pojedinačni upisi za svaki konfiguracioni registar: `awaddr+awvalid` i `wdata+wvalid+wstrb` istovremeno → čekaj `awready` da padne → čekaj `bvalid` pa spusti `bready`.
3. AXI-Full burst upis (za nas: ne treba, jer CPU ne piše sliku/šablon direktno u NCC — to radi sam NCC preko mastera).
4. Upis `REG_CTRL=1` (start), zatim odmah upis `REG_CTRL=0` (clear, da ne bi ponovo krenulo posle završetka).
5. Petlja: AXI-Lite čitanje `REG_STATUS` dok bit nije 1 (`wait for 1000 ns` između pokušaja).
6. AXI-Full burst čitanje `ADDR_RESULTS` (broj reči = res_w×res_h).

## Bitne stvari / zamke na koje paziti

- Wizard može generisati **master** AXI interfejse — ranije sam pogrešno pretpostavio da je za NCC master port potrebna potpuno ručna implementacija; treba proveriti da li generisani master kontroler štedi dovoljno posla ili je ipak jednostavnije ručno napisati FSM za čitanje (par AR/R transakcija po pozivu je jednostavno, ne treba burst).
- **"Create archive of IP" je isključeno podrazumevano** — lako se zaboravi, pa se posle pakovanja ne dobije `.zip` fajl.
- Generic parametri se moraju ručno prebaciti iz `Hidden Parameters` u `Customization Parameters` (i obrnuto za auto-generisane AXI parametre) — wizard ih SVE prvo stavi kao vidljive/hidden na osnovu odakle dolaze, ne na osnovu toga da li ih korisnik treba da menja.
- `Number of Registers` u AXI-Lite delu i broj bitova adrese (`loc_addr`) direktno određuju maksimalan broj registara — voditi računa da 8 registara NCC-a stane (Number of Registers dozvoljava 4-512, nije problem).
- Adresni dekoder unutar memorijskog podsistema (case na gornje bite adrese) mora ručno da se piše — nije automatski generisan čak ni za slave memorije.
- Testbench koristi `std_logic_arith`/`conv_std_logic_vector` (stariji, Xilinx-specifičan stil) umesto `numeric_std` — ostati konzistentan sa stilom auto-generisanog koda unutar istog fajla da ne bi bilo konflikta biblioteka.

## Mapiranje na korake iz bodovanja

- **Korak 6** (pakovanje u IP jezgro, 10 bodova) — ovo je GLAVNI sadržaj cele vežbe, direktno primenjivo.
- **Korak 7** (integracija u block integrator) — **NIJE pokriveno ovim PDF-om**, potrebna dodatna referenca (Zynq PS blok, BRAM Controller, AXI DMA IP u Vivado block design-u).
- Indirektno relevantno za **korak 2c** (interfejs dizajna) — AXI signal tabele i talasni oblici su dobar materijal za tu sekciju dokumentacije.
