library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ncc_accel_slave_full_v1_0_S01_AXI is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of ID for for write address, write data, read address and read data
		C_S_AXI_ID_WIDTH	: integer	:= 1;
		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 17;
		-- Width of optional user defined signal in write address channel
		C_S_AXI_AWUSER_WIDTH	: integer	:= 0;
		-- Width of optional user defined signal in read address channel
		C_S_AXI_ARUSER_WIDTH	: integer	:= 0;
		-- Width of optional user defined signal in write data channel
		C_S_AXI_WUSER_WIDTH	: integer	:= 0;
		-- Width of optional user defined signal in read data channel
		C_S_AXI_RUSER_WIDTH	: integer	:= 0;
		-- Width of optional user defined signal in write response channel
		C_S_AXI_BUSER_WIDTH	: integer	:= 0
	);
	port (
		-- Users to add ports here
		mem_addr_o  : out std_logic_vector(16 downto 0);
		mem_wdata_o : out std_logic_vector(31 downto 0);
		mem_we_o    : out std_logic;
		mem_rdata_i : in  std_logic_vector(31 downto 0);
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global Clock Signal
		S_AXI_ACLK	: in std_logic;
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN	: in std_logic;
		-- Write Address ID
		S_AXI_AWID	: in std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
		-- Write address
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Burst length. The burst length gives the exact number of transfers in a burst
		S_AXI_AWLEN	: in std_logic_vector(7 downto 0);
		-- Burst size. This signal indicates the size of each transfer in the burst
		S_AXI_AWSIZE	: in std_logic_vector(2 downto 0);
		-- Burst type. The burst type and the size information, 
    -- determine how the address for each transfer within the burst is calculated.
		S_AXI_AWBURST	: in std_logic_vector(1 downto 0);
		-- Lock type. Provides additional information about the
    -- atomic characteristics of the transfer.
		S_AXI_AWLOCK	: in std_logic;
		-- Memory type. This signal indicates how transactions
    -- are required to progress through a system.
		S_AXI_AWCACHE	: in std_logic_vector(3 downto 0);
		-- Protection type. This signal indicates the privilege
    -- and security level of the transaction, and whether
    -- the transaction is a data access or an instruction access.
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		-- Quality of Service, QoS identifier sent for each
    -- write transaction.
		S_AXI_AWQOS	: in std_logic_vector(3 downto 0);
		-- Region identifier. Permits a single physical interface
    -- on a slave to be used for multiple logical interfaces.
		S_AXI_AWREGION	: in std_logic_vector(3 downto 0);
		-- Optional User-defined signal in the write address channel.
		S_AXI_AWUSER	: in std_logic_vector(C_S_AXI_AWUSER_WIDTH-1 downto 0);
		-- Write address valid. This signal indicates that
    -- the channel is signaling valid write address and
    -- control information.
		S_AXI_AWVALID	: in std_logic;
		-- Write address ready. This signal indicates that
    -- the slave is ready to accept an address and associated
    -- control signals.
		S_AXI_AWREADY	: out std_logic;
		-- Write Data
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Write strobes. This signal indicates which byte
    -- lanes hold valid data. There is one write strobe
    -- bit for each eight bits of the write data bus.
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		-- Write last. This signal indicates the last transfer
    -- in a write burst.
		S_AXI_WLAST	: in std_logic;
		-- Optional User-defined signal in the write data channel.
		S_AXI_WUSER	: in std_logic_vector(C_S_AXI_WUSER_WIDTH-1 downto 0);
		-- Write valid. This signal indicates that valid write
    -- data and strobes are available.
		S_AXI_WVALID	: in std_logic;
		-- Write ready. This signal indicates that the slave
    -- can accept the write data.
		S_AXI_WREADY	: out std_logic;
		-- Response ID tag. This signal is the ID tag of the
    -- write response.
		S_AXI_BID	: out std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
		-- Write response. This signal indicates the status
    -- of the write transaction.
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		-- Optional User-defined signal in the write response channel.
		S_AXI_BUSER	: out std_logic_vector(C_S_AXI_BUSER_WIDTH-1 downto 0);
		-- Write response valid. This signal indicates that the
    -- channel is signaling a valid write response.
		S_AXI_BVALID	: out std_logic;
		-- Response ready. This signal indicates that the master
    -- can accept a write response.
		S_AXI_BREADY	: in std_logic;
		-- Read address ID. This signal is the identification
    -- tag for the read address group of signals.
		S_AXI_ARID	: in std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
		-- Read address. This signal indicates the initial
    -- address of a read burst transaction.
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Burst length. The burst length gives the exact number of transfers in a burst
		S_AXI_ARLEN	: in std_logic_vector(7 downto 0);
		-- Burst size. This signal indicates the size of each transfer in the burst
		S_AXI_ARSIZE	: in std_logic_vector(2 downto 0);
		-- Burst type. The burst type and the size information, 
    -- determine how the address for each transfer within the burst is calculated.
		S_AXI_ARBURST	: in std_logic_vector(1 downto 0);
		-- Lock type. Provides additional information about the
    -- atomic characteristics of the transfer.
		S_AXI_ARLOCK	: in std_logic;
		-- Memory type. This signal indicates how transactions
    -- are required to progress through a system.
		S_AXI_ARCACHE	: in std_logic_vector(3 downto 0);
		-- Protection type. This signal indicates the privilege
    -- and security level of the transaction, and whether
    -- the transaction is a data access or an instruction access.
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		-- Quality of Service, QoS identifier sent for each
    -- read transaction.
		S_AXI_ARQOS	: in std_logic_vector(3 downto 0);
		-- Region identifier. Permits a single physical interface
    -- on a slave to be used for multiple logical interfaces.
		S_AXI_ARREGION	: in std_logic_vector(3 downto 0);
		-- Optional User-defined signal in the read address channel.
		S_AXI_ARUSER	: in std_logic_vector(C_S_AXI_ARUSER_WIDTH-1 downto 0);
		-- Write address valid. This signal indicates that
    -- the channel is signaling valid read address and
    -- control information.
		S_AXI_ARVALID	: in std_logic;
		-- Read address ready. This signal indicates that
    -- the slave is ready to accept an address and associated
    -- control signals.
		S_AXI_ARREADY	: out std_logic;
		-- Read ID tag. This signal is the identification tag
    -- for the read data group of signals generated by the slave.
		S_AXI_RID	: out std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
		-- Read Data
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Read response. This signal indicates the status of
    -- the read transfer.
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		-- Read last. This signal indicates the last transfer
    -- in a read burst.
		S_AXI_RLAST	: out std_logic;
		-- Optional User-defined signal in the read address channel.
		S_AXI_RUSER	: out std_logic_vector(C_S_AXI_RUSER_WIDTH-1 downto 0);
		-- Read valid. This signal indicates that the channel
    -- is signaling the required read data.
		S_AXI_RVALID	: out std_logic;
		-- Read ready. This signal indicates that the master can
    -- accept the read data and response information.
		S_AXI_RREADY	: in std_logic
	);
end ncc_accel_slave_full_v1_0_S01_AXI;

architecture arch_imp of ncc_accel_slave_full_v1_0_S01_AXI is

	-- AXI4FULL signals
	signal axi_awaddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bid	: std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_buser	: std_logic_vector(C_S_AXI_BUSER_WIDTH-1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rid	: std_logic_vector(C_S_AXI_ID_WIDTH-1 downto 0);
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rlast	: std_logic;
	signal axi_ruser	: std_logic_vector(C_S_AXI_RUSER_WIDTH-1 downto 0);
	signal axi_rvalid	: std_logic;
	-- aw_wrap_en determines wrap boundary and enables wrapping
	signal  aw_wrap_en : std_logic; 
	-- ar_wrap_en determines wrap boundary and enables wrapping
	signal  ar_wrap_en : std_logic;
	-- aw_wrap_size is the size of the write transfer, the
	-- write address wraps to a lower address if upper address
	-- limit is reached
	signal aw_wrap_size : integer;
	-- ar_wrap_size is the size of the read transfer, the
	-- read address wraps to a lower address if upper address
	-- limit is reached
	signal ar_wrap_size : integer;
	-- The axi_awlen_cntr internal write address counter to keep track of beats in a burst transaction
	signal axi_awlen_cntr      : std_logic_vector(7 downto 0);
	--The axi_arlen_cntr internal read address counter to keep track of beats in a burst transaction
	signal axi_arlen_cntr      : std_logic_vector(7 downto 0);
	signal axi_arburst      : std_logic_vector(2-1 downto 0);
	signal axi_awburst      : std_logic_vector(2-1 downto 0);
	signal axi_arlen      : std_logic_vector(8-1 downto 0);
	signal axi_awlen      : std_logic_vector(8-1 downto 0);
	--local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	--ADDR_LSB is used for addressing 32/64 bit registers/memories
	--ADDR_LSB = 2 for 32 bits (n downto 2) 
	--ADDR_LSB = 3 for 64 bits (n downto 3)

	--ADDR_LSB = 4 for 128 bits (n downto 4)

	-- ADDR_LSB koriste adresni brojaci (awaddr/araddr inkrement po reci).
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
	-- low koriste aw_wrap_en / ar_wrap_en.
	constant low : std_logic_vector (C_S_AXI_ADDR_WIDTH - 1 downto 0) := (others => '0');

	-- Napomena (Korak 7): generisani "user logic memory space example" (4x 256 B
	-- byte_ram + mem_data_out) je obrisan -- NCC koristi mem_subsystem preko
	-- mem_addr_o/mem_wdata_o/mem_we_o/mem_rdata_i, a primer je bio mrtav kod.

	 --State machine local parameters
	constant Idle : std_logic_vector(1 downto 0) := "00";
	constant Raddr: std_logic_vector(1 downto 0) := "10";
	constant Rdata: std_logic_vector(1 downto 0) := "11";
	constant Waddr: std_logic_vector(1 downto 0) := "10";
	constant Wdata: std_logic_vector(1 downto 0) := "11";

	--State machine variables
	signal state_read : std_logic_vector(1 downto 0);
	signal state_write: std_logic_vector(1 downto 0);

	-- look-ahead adresa citanja: registrovano dp_bram citanje trazi adresu
	-- jedan takt pre nego sto beat izadje na rdata
	signal araddr_next : std_logic_vector(16 downto 0);
	-- Prihvacen upisni beat (W uz vec prihvacen AW) -- videti komentar uz mem_we_o.
	signal wr_beat     : std_logic;

begin
	-- Staticka zastita (Korak 7): mem_addr_o je fiksno 17-bitni port ka
	-- mem_subsystem-u (regioni slika/sablon/rezultat na 0x00000/0x08000/0x10000),
	-- pa je 17 jedina ispravna sirina adrese. Package IP wizard pakuje 10 (jer mu
	-- "Memory Size" staje na 1024 B) -- bez ove provere S01 tiho dekodira samo 1 KB
	-- i sva tri regiona se preslikaju jedan na drugi.
	-- Ako ovo pukne: pokreni src/vhdl/script/fix_ip_package.tcl
	assert C_S_AXI_ADDR_WIDTH = 17
		report "C_S_AXI_ADDR_WIDTH mora biti 17 (128 KB), dobijeno " &
		       integer'image(C_S_AXI_ADDR_WIDTH) &
		       " -- pokreni src/vhdl/script/fix_ip_package.tcl"
		severity failure;

	-- I/O Connections assignments

	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BUSER	<= axi_buser;
	S_AXI_BVALID	<= axi_bvalid;
	S_AXI_ARREADY	<= axi_arready;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RLAST	<= axi_rlast;
	S_AXI_RUSER	<= axi_ruser;
	S_AXI_RVALID	<= axi_rvalid;
	S_AXI_BID <= axi_bid;
	S_AXI_RID <= axi_rid;
	S_AXI_RDATA	<= mem_rdata_i;
	aw_wrap_size <= ((C_S_AXI_DATA_WIDTH)/8 * to_integer(unsigned(axi_awlen))); 
	ar_wrap_size <= ((C_S_AXI_DATA_WIDTH)/8 * to_integer(unsigned(axi_arlen))); 
	aw_wrap_en <= '1' when (((axi_awaddr AND std_logic_vector(to_unsigned(aw_wrap_size,C_S_AXI_ADDR_WIDTH))) XOR std_logic_vector(to_unsigned(aw_wrap_size,C_S_AXI_ADDR_WIDTH))) = low) else '0';
	ar_wrap_en <= '1' when (((axi_araddr AND std_logic_vector(to_unsigned(ar_wrap_size,C_S_AXI_ADDR_WIDTH))) XOR std_logic_vector(to_unsigned(ar_wrap_size,C_S_AXI_ADDR_WIDTH))) = low) else '0';

	--Implement Write state machine
	--Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
	--
	-- PROTOKOLARNI BUG (dokazan na ploci, Faza 4 -- CDMA burst u S01, cela PL
	-- magistrala se blokira jer je deljena, ni CDMA registri se vise ne mogu
	-- procitati): axi_wready je stajao na '1' od Idle nadalje, a upisni proces
	-- ga nikad nije spustao. AXI4 dozvoljava da W stigne pre AW -- generisani
	-- automat je takav W beat prihvatao (WVALID='1' i WREADY='1') dok je jos
	-- cekao u Waddr, ali ga nigde nije zabelezio jer nije znao kojoj adresi
	-- pripada. Ako je medju tako izgubljenim beat-ovima bio i WLAST, FSM je
	-- posle prihvatanja AW zauvek cekao u Wdata na W koji se vec dogodio i
	-- nece se ponoviti -- BVALID se nikad ne izdaje i master (CDMA/CPU preko
	-- AXI-Full) zauvek visi. Isti obrazac popravljen u S00 (AXI-Lite),
	-- commit 720d162 -- ovde isto resenje, prosireno na burst (WLAST umesto
	-- jednog beat-a).
	--
	-- POPRAVKA: axi_wready se sada dize tek pri ULASKU u Wdata (posle
	-- prihvacenog AW), nikad u Idle/Waddr. Grana koja je zavrsavala upis
	-- odmah u Waddr (AW+W+WLAST u istom taktu) je uklonjena -- sva tri
	-- redosleda (AW pa W, W pa AW, AW+W isti takt) sada idu kroz Wdata, cena
	-- je jedan takt kasnjenja po burstu.
	 process (S_AXI_ACLK)
	   begin
	     if rising_edge(S_AXI_ACLK) then
	       if S_AXI_ARESETN = '0' then
	        --asserting initial values to all 0's during reset
	        axi_awready <= '0';
	        axi_wready <= '0';
	        axi_bvalid <= '0';
	        axi_buser <= (others => '0');
	        axi_awburst <= (others => '0');
	        axi_bid <= (others => '0');
	        axi_awlen <= (others => '0');
	        axi_bresp <= (others => '0');
	        state_write <= Idle;
	       else
	        -- BVALID se brise cim ga master prihvati (BREADY='1'), BEZ OBZIRA na
	        -- stanje automata, PRE case-a. Mora stajati ovde da eventualna
	        -- dodela axi_bvalid <= '1' u Wdata (kad se burst zavrsava u istom
	        -- taktu kad master prihvata prethodni odgovor) ima prioritet --
	        -- inace novi AW koji stigne u istom taktu kad master ceka/prihvata
	        -- BVALID prethodnog upisa ostavlja BVALID zaglavljen na '1' -- master
	        -- vidi drugi BRESP za transakciju koja jos nije zavrsena (ista rupa
	        -- nadjena i popravljena u S00 recenziji).
	        if (axi_bvalid = '1' and S_AXI_BREADY = '1') then
	          axi_bvalid <= '0';
	        end if;
	        case (state_write) is
	          when Idle =>		--Initial state inidicating reset is done and ready to receive read/write transactions
	            if (S_AXI_ARESETN = '1') then
	              axi_awready <= '1';
	              axi_wready <= '0';
	              state_write <= Waddr;
	            else state_write <= state_write;
	            end if;
	          when Waddr =>		--Slave ceka AW; W se NE prihvata ovde (axi_wready='0') da se ne
	                            --bi izgubio W koji stigne pre AW (protokolarni bug, vidi komentar iznad).
	            if (S_AXI_AWVALID = '1' and axi_awready = '1') then
	              axi_awready <= '0';
	              axi_wready  <= '1';
	              state_write <= Wdata;
	              axi_awburst <= S_AXI_AWBURST;
	              axi_awlen <= S_AXI_AWLEN;
	              axi_bid <= S_AXI_AWID;
	           else
	             state_write <= state_write;
	           end if;
	         when Wdata =>		--AW je vec prihvacen (axi_awaddr zapamcen); ceka se W do WLAST.
	                        --Pokriva sva tri redosleda (AW pa W, W pa AW, AW+W isti takt) jer
	                        --se W uvek prihvata tek ovde.
	           if (S_AXI_WVALID = '1' and S_AXI_WLAST = '1') then
	             state_write <= Waddr;
	             axi_bvalid <= '1';
	             axi_wready  <= '0';
	             axi_awready <= '1';
	           else
	             state_write <= state_write;
	           end if;
	         when others =>      --reserved
	           axi_awready <= '0';
	           axi_wready <= '0';
	           axi_bvalid <= '0';
	       end case;
	     end if;
	   end if;
	 end process;
	--Implement Read state machine
	--Outstanding read transactions are not supported by the slave

	 process (S_AXI_ACLK)                                     
	   begin                                     
	     if rising_edge(S_AXI_ACLK) then                                      
	       if S_AXI_ARESETN = '0' then                                     
	         --asserting initial values to all 0's during reset                                     
	         axi_arready <= '0';                                     
	         axi_rvalid <= '0';                                     
	         axi_rlast <= '0';                                     
	         axi_ruser <= (others => '0');                                     
	         axi_arburst <= (others => '0');                                     
	         axi_rid <= (others => '0');                                     
	         axi_arlen <= (others => '0');                                     
	         axi_rresp <= (others => '0');                                     
	         state_read <= Idle;                                     
	       else                                     
	         case (state_read) is                                     
	           when Idle =>		--Initial state inidicating reset is done and ready to receive read/write transactions                                     
	             if (S_AXI_ARESETN = '1') then                                     
	               axi_arready <= '1';                                     
	               state_read <= Raddr;                                     
	             else state_read <= state_read;                                     
	             end if;                                     
	           when Raddr =>		--At this state, slave is ready to receive address along with corresponding control signals                                     
	             if (S_AXI_ARVALID = '1' and axi_arready = '1') then                                     
	               state_read <= Rdata;                                     
	               axi_rvalid <= '1';                                     
	               axi_arready <= '0';                                     
	               if (S_AXI_ARLEN = "00000000") then                                     
	                 axi_rlast <= '1';                                     
	               end if;                                     
	               axi_arburst <= S_AXI_ARBURST;                                     
	               axi_arlen <= S_AXI_ARLEN;                                     
	               axi_rid <= S_AXI_ARID;                                     
	            else                                     
	              state_read <= state_read;                                     
	            end if;                                     
	          when Rdata =>		--At this state, slave is ready to send the data packets until the number of transfers is equal to burst length                                     
	            if ((axi_arlen_cntr = std_logic_vector(unsigned(axi_arlen(7 downto 0))-1)) and axi_rlast = '0' and S_AXI_RREADY = '1') then                                     
	              axi_rlast <= '1';                                     
	            end if;                                     
	            if (axi_rvalid = '1' and S_AXI_RREADY = '1' and axi_rlast = '1') then                                     
	              axi_rvalid <= '0';                                     
	              axi_arready <= '1';                                     
	              axi_rlast <= '0';                                     
	              state_read <= Raddr;                                     
	            else                                     
	              state_read <= state_read;                                     
	            end if;                                     
	          when others =>      --reserved                                     
	            axi_arready <= '0';                                     
	            axi_rvalid <= '0';                                     
	        end case;                                     
	      end if;                                     
	    end if;                                              
	 end process;                                     
	--This always block handles the write address increment
	--
	-- POPRAVKA (ista faza kao gore): stari kod je PRE-inkrementirao adresu/
	-- brojac na osnovu golog S_AXI_WVALID, pretpostavljajuci da se prvi W beat
	-- trosi u ISTOM taktu kad se AW prihvata. Sa novim upisnim automatom
	-- (axi_wready='0' u Waddr) to vise nikad nije tacno -- prvi beat se uvek
	-- trosi kasnije, u Wdata. Pre-inkrement bi tu razisao brojac/adresu za
	-- jedan i burst bi upisivao na pomerene adrese, TIHO, bez ijedne AXI
	-- greske. Zato: pri prihvatanju AW adresa/brojac se pamte BEZ
	-- pre-inkrementa (axi_awlen_cntr<=0, axi_awaddr<=S_AXI_AWADDR), a
	-- inkrement se okida iskljucivo na wr_beat (stvaran handshake W kanala u
	-- Wdata: WVALID='1' i axi_wready='1'), ne na goli S_AXI_WVALID.
	 process (S_AXI_ACLK)
	   begin
	     if rising_edge(S_AXI_ACLK) then
	       if S_AXI_ARESETN = '0' then
	       --both axi_awlen_cntr and axi_awaddr will increment after each successfull data received until the number of the transfers is equal to burst length
	         axi_awaddr <= (others => '0');
	         axi_awlen_cntr <= (others => '0');
	       else
	        if (S_AXI_AWVALID = '1' and axi_awready = '1') then
	          axi_awlen_cntr <= (others => '0');
	          axi_awaddr <= std_logic_vector(unsigned(S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH - 1 downto 0)));
	        elsif((axi_awlen_cntr < axi_awlen) and wr_beat = '1') then
	          axi_awlen_cntr <= std_logic_vector (unsigned(axi_awlen_cntr) + 1);
	          case (axi_awburst) is                             
	            when "00" => -- fixed burst                             
	              -- The write address for all the beats in the transaction are fixed                             
	              axi_awaddr     <= axi_awaddr;       ----for awsize = 4 bytes (010)                             
	            when "01" => --incremental burst                             
	              -- The write address for all the beats in the transaction are increments by awsize                             
	              axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--awaddr aligned to 4 byte boundary            
	              axi_awaddr(ADDR_LSB-1 downto 0)  <= (others => '0');  ----for awsize = 4 bytes (010)                             
	            when "10" => --Wrapping burst                             
	              -- The write address wraps when the address reaches wrap boundary                             
	              if (aw_wrap_en = '1') then                             
	                axi_awaddr <= std_logic_vector (unsigned(axi_awaddr) - (to_unsigned(aw_wrap_size,C_S_AXI_ADDR_WIDTH)));                             
	              else                              
	                axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--awaddr aligned to 4 byte boundary                      
	                axi_awaddr(ADDR_LSB-1 downto 0)  <= (others => '0');  ----for awsize = 4 bytes (010)                             
	              end if;                             
	            when others => --reserved (incremental burst for example)                             
	              axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_awaddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--for awsize = 4 bytes (010)                             
	              axi_awaddr(ADDR_LSB-1 downto 0)  <= (others => '0');                             
	          end case;                                     
	        end if;                             
	      end if;                             
	    end if;                             
	 end process;                              
	--This always block handles the read address increment
	 process (S_AXI_ACLK)                                   
	   begin                                   
	     if rising_edge(S_AXI_ACLK) then                                    
	       if S_AXI_ARESETN = '0' then                                   
	         --both axi_arlen_cntr and axi_araddr will increment after each successfull data received until the number of the transfers is equal to burst length                                   
	         axi_araddr <= (others => '0');                                   
	         axi_arlen_cntr <= (others => '0');                                   
	       else                                   
	         if (S_AXI_ARVALID = '1' and axi_arready = '1') then                                   
	           axi_arlen_cntr <= (others => '0');                                   
	           axi_araddr <= std_logic_vector (unsigned(S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH -1 downto 0)));                                   
	         elsif((axi_arlen_cntr <= axi_arlen) and axi_rvalid = '1' and S_AXI_RREADY = '1') then                                        
	           axi_arlen_cntr <= std_logic_vector (unsigned(axi_arlen_cntr) + 1);                                   
	           case (axi_arburst) is                                   
	             when "00" => -- fixed burst                                   
	               -- The read address for all the beats in the transaction are fixed                                   
	               axi_araddr     <= axi_araddr;       ----for arsize = 4 bytes (010)                                   
	             when "01" => --incremental burst                                   
	               -- The read address for all the beats in the transaction are increments by arsize                                   
	               axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--araddr aligned to 4 byte boundary                                   
	               axi_araddr(ADDR_LSB-1 downto 0)  <= (others => '0');  ----for arsize = 4 bytes (010)                                   
	             when "10" => --Wrapping burst                                   
	               -- The read address wraps when the address reaches wrap boundary                                    
	               if (ar_wrap_en = '1') then                                   
	                 axi_araddr <= std_logic_vector (unsigned(axi_araddr) - (to_unsigned(ar_wrap_size,C_S_AXI_ADDR_WIDTH)));                                   
	               else                                    
	                 axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--araddr aligned to 4 byte boundary                                   
	                 axi_araddr(ADDR_LSB-1 downto 0)  <= (others => '0');  ----for arsize = 4 bytes (010)                                   
	               end if;                                   
	             when others => --reserved (incremental burst for example)                                   
	               axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB) <= std_logic_vector (unsigned(axi_araddr(C_S_AXI_ADDR_WIDTH - 1 downto ADDR_LSB)) + 1);--for arsize = 4 bytes (010)                                   
	               axi_araddr(ADDR_LSB-1 downto 0)  <= (others => '0');                                   
	           end case;                                           
	         end if;                                   
	       end if;                                   
	     end if;                                   
	 end process;                                   

	-- === NCC omotac: veza AXI-Full <-> mem_subsystem ===
	-- dp_bram citanje je registrovano (1 takt), pa adresa mora ici JEDAN TAKT
	-- unaprijed. Prvi beat: adresa na ciklusu prihvata (S_AXI_ARADDR). Beat k>0:
	-- u taktu kad se beat k trosi izdaje se adresa beat-a k+1 (araddr_next).
	-- Pri zastoju (RREADY='0') adresa se drzi pa podatak beat-a k ostaje validan.
	-- INCR uvecava; FIXED zadrzava adresu; WRAP nije podrzan (nije ni bio).
	-- Look-ahead mora da prati ISTU aritmetiku kao brojac axi_araddr (linije nize),
	-- inace se za te tipove bursta vraca ista off-by-one greska zbog koje je ovo i
	-- pisano. Ranije je pokrivao samo INCR, a brojac napreduje i za WRAP i za
	-- rezervisano "11" -- tiha korupcija sa OKAY odgovorom. (code review Koraka 8)
	araddr_next <= axi_araddr(16 downto 0)
	                 when axi_arburst = "00" else                    -- FIXED: adresa stoji
	               std_logic_vector(resize(unsigned(axi_araddr(16 downto 0))
	                                       - to_unsigned(ar_wrap_size, 17), 17))
	                 when (axi_arburst = "10" and ar_wrap_en = '1') else  -- WRAP, na granici
	               std_logic_vector(unsigned(axi_araddr(16 downto 0)) + 4);  -- INCR i WRAP bez omotanja

	-- Upisni beat je validan SAMO u stanju Wdata (posle vec prihvacenog AW) --
	-- sa novim automatom axi_wready je '1' iskljucivo tamo (vidi popravku upisnog
	-- FSM-a gore), pa je grana koja je ovde nekad pokrivala "Waddr + AW+W isti
	-- takt" postala nedostizna po konstrukciji i uklonjena je da ne sugerise da
	-- se upis moze desiti pre nego sto je AW prihvacen (ista simplifikacija kao
	-- u S00, mem_logic).
	wr_beat <= '1' when (state_write = Wdata and S_AXI_WVALID = '1' and axi_wready = '1')
	           else '0';

	-- mem_addr_o za upis je uvek zapamcena axi_awaddr (AW je po konstrukciji vec
	-- prihvacen pre nego sto se udje u Wdata, gde se jedino i pise) -- grana koja
	-- je ovde nekad uzimala S_AXI_AWADDR direktno u stanju Waddr je uklonjena iz
	-- istog razloga kao gore.
	mem_addr_o  <= S_AXI_ARADDR(16 downto 0)
	                 when (S_AXI_ARVALID = '1' and axi_arready = '1') else
	               araddr_next
	                 when (state_read = Rdata and axi_rvalid = '1' and S_AXI_RREADY = '1') else
	               axi_araddr(16 downto 0)
	                 when (state_read = Rdata) else
	               axi_awaddr(16 downto 0);
	mem_wdata_o <= S_AXI_WDATA;
	-- WSTRB(0): mem_subsystem pamti samo donji bajt (1 piksel po 32-bitnoj reci),
	-- pa upis kod koga je bajt-lane 0 iskljucen ne sme da promeni piksel.
	mem_we_o    <= wr_beat and S_AXI_WSTRB(0);
                                 
	-- Add user logic here

 	-- User logic ends 


	-- Add user logic here

	-- User logic ends

end arch_imp;
