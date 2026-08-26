# Ideje

Stvari koje bi mogle da poboljšaju sistem, ali nisu deo trenutnog koraka.

## Suziti `sat_t` sa 32 na 21 bit

Memorija integralne slike je deklarisana kao `unsigned(31 downto 0)`, a najveća
moguća vrednost je `90·90·255 = 2.065.500 < 2²¹ = 2.097.152` — dakle **21 bit je
dovoljan**. Trenutno: 8281 reči × 32 b = 265 kb → **9× RAMB36 (15%)**.
Posle suženja: 8281 × 21 = 174 kb → **~6 blokova**.

Izmena je jedna linija u `ncc_pkg.vhd`. Nije urađeno jer 15% BRAM-a nije usko
grlo, ali je to jedina stavka u kojoj smo lošiji od ESL/HLS reference
(4× BRAM_18K). Dokumentovano u PDF-u, odeljak 7.2.

**Oprez 1:** `row_sum_reg`, `sum_t_reg` i `sum_f_partial_reg` su takođe `sat_t` —
provereno da im 21 bit i dalje dovoljno: `row_sum` ≤ 90·255 = 22.950,
`sum_t` ≤ 30·30·255 = 229.500 (18 bita), `sum_f_partial` ≤ 2.065.500 (21 bit).

**Oprez 2:** `sum_f_partial` računa `A − B − C + D` u tri koraka, pa
međurezultat `A − B − C` **može biti negativan** i wrap-ovati (tip je unsigned).
To radi ispravno zahvaljujući modularnoj aritmetici — konačni rezultat je uvek
u opsegu — i nastavlja da radi i na 21 bitu, ali nije očigledno pri čitanju koda.
Ne "popravljati" prelaskom na signed bez razloga.

## Registrovati kritičnu putanju

Kritična putanja je `sum_num_reg[16] → div_ncc/work_reg[78]` (kvadriranje
brojioca + ulaz u 83-bitni delilac), 8.670 ns od 10 ns. Ako ikad zatreba veći
takt, ta putanja se može preseći registrom **bez uticaja na propusnost**, jer se
izvršava samo jednom po poziciji prozora (a ne u unutrašnjoj petlji). Cena: +1
takt po prozoru od ~485.

## Dalje ubrzanje unutrašnje petlje

Petlja je sad 1 takt/piksel i nosi ~77% posla po prozoru. Sledeći nivo bio bi
obrada 2 piksela po taktu (dvoportna memorija + 6 množača umesto 3) — DSP ima
mesta (9 od 80), ali bi trebalo dupli port ka memoriji slike, što utiče na
Korak 7 (block design). Razmotriti tek ako se posle merenja na ploči (Korak 9)
pokaže da je propusnost problem.

## Jača verifikacija: test na različitim pozadinama

Trenutni realni testbench (`ncc_core_real_tb`) koristi segment koji **tačno**
sadrži šablon, pa je vršni NCC² = 1,0 (`0x80000000`). To pokriva ekstreme (0 i
2³¹), ali ne i realan slučaj **delimičnog** poklapanja.

Jači test: šablon na **drugačijoj pozadini** nego na slici — npr. crni top na
crnoj pozadini u segmentu, a šablon crnog topa na beloj pozadini. Tada poklapanje
nije egzaktno 1, pa se delilac i ceo datapath proveravaju na netrivijalnim NCC²
vrednostima (strogo između 0 i 2³¹), bliže tome kako sistem stvarno radi nad
`board2`.

Posao je na testbenčevima (izvući takav par segment/šablon iz realnih podataka i
uporediti sa C kernelom iz Koraka 1), ne na samom jezgru. Ideja sa pregleda
dokumentacije (23.07.2026).

## Kvadriranje: DSP u OOC-u, CARRY4 u sistemu — možda 100 MHz bez izmene RTL-a

Zapaženo pri kontrolnom merenju na 10 ns (2026-08-26), **nije provereno** — trag,
ne nalaz.

Ista putanja `sum_num_reg → num_sq_reg` (kvadriranje brojioca pred deliocem)
implementira se **različito** zavisno od toga da li se gradi golo jezgro ili sistem:

| | nivoa | primitive | WNS na 10 ns |
|---|---|---|---|
| golo jezgro, OOC | 12 | **DSP48E1 = 2** | **+0,146 ns** |
| ceo sistem | 13 | **CARRY4 = 8**, bez DSP-a | −0,054 ns |

DSP-ova ima — 9 po instanci u oba slučaja — ali ih alat u sistemskoj gradnji nije
upotrebio na *toj* putanji.

Ako se ikad zatraži punih 100 MHz, ovo je **prvo** mesto za gledanje, pre bilo kakvog
zahvata u verifikovano jezgro: možda je dovoljno naterati alat na isto mapiranje
(`USE_DSP` atribut na signalu/procesu, ili direktiva sinteze), bez ijedne izmene
logike. Za razliku od dodatnog protočnog stepena, ne košta ni takt latencije.

Provera bi bila jedno merenje: `set NCC_FCLK 100` uz atribut, pa uporediti sa
−0,054 ns. Videti `BUGS.md` za kontekst merenja.


## Izmestiti AXI-Lite slave-ove na zaseban interkonekt — da burstovi prorade

Nađeno u Koraku 9: burstovi duži od dva beata zaglavljuju `axi_interconnect_0`
(`STRATEGY=1`, deljena magistrala). Zbog toga aplikacija radi prenose procesorom umesto
DMA-om, što košta oko 9 % vremena.

**Hipoteza:** u deljenom režimu svi slave-ovi dele podatkovni put, a tri od šest su
AXI-Lite (`ncc0.S00`, `ncc1.S00`, `axi_cdma_0.S_AXI_LITE`) i ne podržavaju burst.

**Predlog:** dva interkonekta — jedan `STRATEGY=1` samo za tri Lite slave-a (kontrolni
registri, retke jednobeat transakcije), drugi za `ncc0.S01`, `ncc1.S01` i `S_AXI_HP0`,
gde ide sav burst saobraćaj. Time se zadržava mala površina tamo gde je važna.

**Provera:** jedna iteracija `run_impl.tcl` (~40 min) pa JTAG test iz `BUGS.md`
(`cdma_probe.tcl`, BTT=16). Ako prođe, povratak na DMA je **jedna linija** —
`NCC_USE_CDMA 1` u `src/vitis/app/ncc_hw.c`.

**Rizik:** dva interkonekta troše više LUT-ova od jednog i mogu pogoršati tajming; zato
STRATEGY=2 (pun krosbar) i nije upotrebljen (WNS −3,608 ns). Meriti pre nego se prihvati.

Ideja sa istrage bug-a (26.08.2026).
