library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ncc_accel is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 6;

		-- Parameters of Axi Slave Bus Interface S01_AXI
		C_S01_AXI_ID_WIDTH	: integer	:= 1;
		C_S01_AXI_DATA_WIDTH	: integer	:= 32;
		C_S01_AXI_ADDR_WIDTH	: integer	:= 17;
		C_S01_AXI_AWUSER_WIDTH	: integer	:= 0;
		C_S01_AXI_ARUSER_WIDTH	: integer	:= 0;
		C_S01_AXI_WUSER_WIDTH	: integer	:= 0;
		C_S01_AXI_RUSER_WIDTH	: integer	:= 0;
		C_S01_AXI_BUSER_WIDTH	: integer	:= 0
	);
	port (
		-- Users to add ports here

		-- User ports ends
		-- Do not modify the ports beyond this line


		-- Ports of Axi Slave Bus Interface S00_AXI
		s00_axi_aclk	: in std_logic;
		s00_axi_aresetn	: in std_logic;
		s00_axi_awaddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_awprot	: in std_logic_vector(2 downto 0);
		s00_axi_awvalid	: in std_logic;
		s00_axi_awready	: out std_logic;
		s00_axi_wdata	: in std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_wstrb	: in std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
		s00_axi_wvalid	: in std_logic;
		s00_axi_wready	: out std_logic;
		s00_axi_bresp	: out std_logic_vector(1 downto 0);
		s00_axi_bvalid	: out std_logic;
		s00_axi_bready	: in std_logic;
		s00_axi_araddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_arprot	: in std_logic_vector(2 downto 0);
		s00_axi_arvalid	: in std_logic;
		s00_axi_arready	: out std_logic;
		s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_rresp	: out std_logic_vector(1 downto 0);
		s00_axi_rvalid	: out std_logic;
		s00_axi_rready	: in std_logic;

		-- Ports of Axi Slave Bus Interface S01_AXI
		s01_axi_aclk	: in std_logic;
		s01_axi_aresetn	: in std_logic;
		s01_axi_awid	: in std_logic_vector(C_S01_AXI_ID_WIDTH-1 downto 0);
		s01_axi_awaddr	: in std_logic_vector(C_S01_AXI_ADDR_WIDTH-1 downto 0);
		s01_axi_awlen	: in std_logic_vector(7 downto 0);
		s01_axi_awsize	: in std_logic_vector(2 downto 0);
		s01_axi_awburst	: in std_logic_vector(1 downto 0);
		s01_axi_awlock	: in std_logic;
		s01_axi_awcache	: in std_logic_vector(3 downto 0);
		s01_axi_awprot	: in std_logic_vector(2 downto 0);
		s01_axi_awqos	: in std_logic_vector(3 downto 0);
		s01_axi_awregion	: in std_logic_vector(3 downto 0);
		s01_axi_awuser	: in std_logic_vector(C_S01_AXI_AWUSER_WIDTH-1 downto 0);
		s01_axi_awvalid	: in std_logic;
		s01_axi_awready	: out std_logic;
		s01_axi_wdata	: in std_logic_vector(C_S01_AXI_DATA_WIDTH-1 downto 0);
		s01_axi_wstrb	: in std_logic_vector((C_S01_AXI_DATA_WIDTH/8)-1 downto 0);
		s01_axi_wlast	: in std_logic;
		s01_axi_wuser	: in std_logic_vector(C_S01_AXI_WUSER_WIDTH-1 downto 0);
		s01_axi_wvalid	: in std_logic;
		s01_axi_wready	: out std_logic;
		s01_axi_bid	: out std_logic_vector(C_S01_AXI_ID_WIDTH-1 downto 0);
		s01_axi_bresp	: out std_logic_vector(1 downto 0);
		s01_axi_buser	: out std_logic_vector(C_S01_AXI_BUSER_WIDTH-1 downto 0);
		s01_axi_bvalid	: out std_logic;
		s01_axi_bready	: in std_logic;
		s01_axi_arid	: in std_logic_vector(C_S01_AXI_ID_WIDTH-1 downto 0);
		s01_axi_araddr	: in std_logic_vector(C_S01_AXI_ADDR_WIDTH-1 downto 0);
		s01_axi_arlen	: in std_logic_vector(7 downto 0);
		s01_axi_arsize	: in std_logic_vector(2 downto 0);
		s01_axi_arburst	: in std_logic_vector(1 downto 0);
		s01_axi_arlock	: in std_logic;
		s01_axi_arcache	: in std_logic_vector(3 downto 0);
		s01_axi_arprot	: in std_logic_vector(2 downto 0);
		s01_axi_arqos	: in std_logic_vector(3 downto 0);
		s01_axi_arregion	: in std_logic_vector(3 downto 0);
		s01_axi_aruser	: in std_logic_vector(C_S01_AXI_ARUSER_WIDTH-1 downto 0);
		s01_axi_arvalid	: in std_logic;
		s01_axi_arready	: out std_logic;
		s01_axi_rid	: out std_logic_vector(C_S01_AXI_ID_WIDTH-1 downto 0);
		s01_axi_rdata	: out std_logic_vector(C_S01_AXI_DATA_WIDTH-1 downto 0);
		s01_axi_rresp	: out std_logic_vector(1 downto 0);
		s01_axi_rlast	: out std_logic;
		s01_axi_ruser	: out std_logic_vector(C_S01_AXI_RUSER_WIDTH-1 downto 0);
		s01_axi_rvalid	: out std_logic;
		s01_axi_rready	: in std_logic
	);
end ncc_accel;

architecture arch_imp of ncc_accel is

	-- interni signali kontrole (S00 <-> ncc_core)
	signal rst_s : std_logic;
	signal img_w_s, img_h_s, tmp_w_s, tmp_h_s : std_logic_vector(7 downto 0);
	signal start_s, busy_s, done_s : std_logic;
	-- S01 <-> mem_subsystem
	signal mem_addr_s  : std_logic_vector(16 downto 0);
	signal mem_wdata_s, mem_rdata_s : std_logic_vector(31 downto 0);
	signal mem_we_s    : std_logic;
	-- mem_subsystem <-> ncc_core (port B)
	signal img_addr_s   : std_logic_vector(12 downto 0);
	signal img_dout_s   : std_logic_vector(7 downto 0);
	signal templ_addr_s : std_logic_vector(9 downto 0);
	signal templ_dout_s : std_logic_vector(7 downto 0);
	signal res_addr_s   : std_logic_vector(12 downto 0);
	signal res_din_s    : std_logic_vector(31 downto 0);
	signal res_we_s     : std_logic;
	-- ncc_core integer/typed medjusignali
	signal img_addr_i, res_addr_i : integer range 0 to 8099;
	signal templ_addr_i : integer range 0 to 899;
	signal res_data_u   : unsigned(31 downto 0);
begin

	rst_s <= not s00_axi_aresetn;

	-- AXI-Lite kontrola
	s00_inst : entity work.ncc_accel_slave_lite_v1_0_S00_AXI
		generic map (
			C_S_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
			C_S_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH
		)
		port map (
			img_w => img_w_s, img_h => img_h_s, tmp_w => tmp_w_s, tmp_h => tmp_h_s,
			start_pulse => start_s, core_busy => busy_s, core_done => done_s,
			S_AXI_ACLK => s00_axi_aclk, S_AXI_ARESETN => s00_axi_aresetn,
			S_AXI_AWADDR => s00_axi_awaddr, S_AXI_AWPROT => s00_axi_awprot,
			S_AXI_AWVALID => s00_axi_awvalid, S_AXI_AWREADY => s00_axi_awready,
			S_AXI_WDATA => s00_axi_wdata, S_AXI_WSTRB => s00_axi_wstrb,
			S_AXI_WVALID => s00_axi_wvalid, S_AXI_WREADY => s00_axi_wready,
			S_AXI_BRESP => s00_axi_bresp, S_AXI_BVALID => s00_axi_bvalid,
			S_AXI_BREADY => s00_axi_bready, S_AXI_ARADDR => s00_axi_araddr,
			S_AXI_ARPROT => s00_axi_arprot, S_AXI_ARVALID => s00_axi_arvalid,
			S_AXI_ARREADY => s00_axi_arready, S_AXI_RDATA => s00_axi_rdata,
			S_AXI_RRESP => s00_axi_rresp, S_AXI_RVALID => s00_axi_rvalid,
			S_AXI_RREADY => s00_axi_rready
		);

	-- AXI-Full podaci
	s01_inst : entity work.ncc_accel_slave_full_v1_0_S01_AXI
		generic map (
			C_S_AXI_ID_WIDTH => C_S01_AXI_ID_WIDTH,
			C_S_AXI_DATA_WIDTH => C_S01_AXI_DATA_WIDTH,
			C_S_AXI_ADDR_WIDTH => C_S01_AXI_ADDR_WIDTH,
			C_S_AXI_AWUSER_WIDTH => C_S01_AXI_AWUSER_WIDTH,
			C_S_AXI_ARUSER_WIDTH => C_S01_AXI_ARUSER_WIDTH,
			C_S_AXI_WUSER_WIDTH => C_S01_AXI_WUSER_WIDTH,
			C_S_AXI_RUSER_WIDTH => C_S01_AXI_RUSER_WIDTH,
			C_S_AXI_BUSER_WIDTH => C_S01_AXI_BUSER_WIDTH
		)
		port map (
			mem_addr_o => mem_addr_s, mem_wdata_o => mem_wdata_s,
			mem_we_o => mem_we_s, mem_rdata_i => mem_rdata_s,
			S_AXI_ACLK => s01_axi_aclk, S_AXI_ARESETN => s01_axi_aresetn,
			S_AXI_AWID => s01_axi_awid, S_AXI_AWADDR => s01_axi_awaddr,
			S_AXI_AWLEN => s01_axi_awlen, S_AXI_AWSIZE => s01_axi_awsize,
			S_AXI_AWBURST => s01_axi_awburst, S_AXI_AWLOCK => s01_axi_awlock,
			S_AXI_AWCACHE => s01_axi_awcache, S_AXI_AWPROT => s01_axi_awprot,
			S_AXI_AWQOS => s01_axi_awqos, S_AXI_AWREGION => s01_axi_awregion,
			S_AXI_AWUSER => s01_axi_awuser, S_AXI_AWVALID => s01_axi_awvalid,
			S_AXI_AWREADY => s01_axi_awready, S_AXI_WDATA => s01_axi_wdata,
			S_AXI_WSTRB => s01_axi_wstrb, S_AXI_WLAST => s01_axi_wlast,
			S_AXI_WUSER => s01_axi_wuser, S_AXI_WVALID => s01_axi_wvalid,
			S_AXI_WREADY => s01_axi_wready, S_AXI_BID => s01_axi_bid,
			S_AXI_BRESP => s01_axi_bresp, S_AXI_BUSER => s01_axi_buser,
			S_AXI_BVALID => s01_axi_bvalid, S_AXI_BREADY => s01_axi_bready,
			S_AXI_ARID => s01_axi_arid, S_AXI_ARADDR => s01_axi_araddr,
			S_AXI_ARLEN => s01_axi_arlen, S_AXI_ARSIZE => s01_axi_arsize,
			S_AXI_ARBURST => s01_axi_arburst, S_AXI_ARLOCK => s01_axi_arlock,
			S_AXI_ARCACHE => s01_axi_arcache, S_AXI_ARPROT => s01_axi_arprot,
			S_AXI_ARQOS => s01_axi_arqos, S_AXI_ARREGION => s01_axi_arregion,
			S_AXI_ARUSER => s01_axi_aruser, S_AXI_ARVALID => s01_axi_arvalid,
			S_AXI_ARREADY => s01_axi_arready, S_AXI_RID => s01_axi_rid,
			S_AXI_RDATA => s01_axi_rdata, S_AXI_RRESP => s01_axi_rresp,
			S_AXI_RLAST => s01_axi_rlast, S_AXI_RUSER => s01_axi_ruser,
			S_AXI_RVALID => s01_axi_rvalid, S_AXI_RREADY => s01_axi_rready
		);

	-- Memorijski podsistem (interne memorije slika/sablon/rezultat)
	--
	-- OGRANICENJE (code review Koraka 8): ceo IP radi na JEDNOM taktu -- ovde je to
	-- s00_axi_aclk. Port A `mem_subsystem`-a hrani s01_inst (koji je nominalno na
	-- s01_axi_aclk), pa `s00_axi_aclk` i `s01_axi_aclk` MORAJU biti isti signal.
	-- IP-XACT ih deklarise kao dva interfejsa, sto formalno dopusta razlicite
	-- taktove -- u tom slucaju bi svaki S01 pristup presao neusinhronizovanu granicu
	-- domena (pogresne reci pri citanju, pogresne adrese pri upisu, bez ikakve greske).
	-- create_bd.tcl oba veze na FCLK_CLK0; isto vazi i za reset (rst_s = not
	-- s00_axi_aresetn, s01_axi_aresetn se ne koristi).
	-- Ako ikada zatreba pravi dvo-taktni rad: dp_bram vec ima odvojene clka/clkb,
	-- pa bi mem_subsystem trebalo prosiriti na dva takta umesto jednog.
	ms_inst : entity work.mem_subsystem
		port map (
			clk => s00_axi_aclk,
			mem_addr_a => mem_addr_s, mem_wdata_a => mem_wdata_s,
			mem_we_a => mem_we_s, mem_rdata_a => mem_rdata_s,
			img_addr_b => img_addr_s, img_dout_b => img_dout_s,
			templ_addr_b => templ_addr_s, templ_dout_b => templ_dout_s,
			result_addr_b => res_addr_s, result_din_b => res_din_s, result_we_b => res_we_s
		);

	-- NCC jezgro (nepromenjeno, iz Koraka 3-5)
	core_inst : entity work.ncc_core
		port map (
			clk => s00_axi_aclk, rst => rst_s, start => start_s,
			busy => busy_s, done => done_s,
			img_w => unsigned(img_w_s), img_h => unsigned(img_h_s),
			tmp_w => unsigned(tmp_w_s), tmp_h => unsigned(tmp_h_s),
			img_addr_o => img_addr_i, img_data_i => unsigned(img_dout_s),
			templ_addr_o => templ_addr_i, templ_data_i => unsigned(templ_dout_s),
			result_addr_o => res_addr_i, result_data_o => res_data_u,
			result_wr_o => res_we_s
		);

	-- konverzija integer/typed -> slv za mem_subsystem port B
	img_addr_s   <= std_logic_vector(to_unsigned(img_addr_i, 13));
	templ_addr_s <= std_logic_vector(to_unsigned(templ_addr_i, 10));
	res_addr_s   <= std_logic_vector(to_unsigned(res_addr_i, 13));
	res_din_s    <= std_logic_vector(res_data_u);

end arch_imp;
