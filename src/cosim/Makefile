CPP_SOURCES = sc_main_cosim.cpp ncc_target_rtl.cpp ncc.cpp bram.cpp

VHDL_SOURCES = ncc_pkg.vhd ncc_core.vhd

XMSC_OPTIONS = -sc_main -xmvhdl_args,-v200x

all:
	xmsc_run $(XMSC_OPTIONS) $(CPP_SOURCES) $(VHDL_SOURCES)

clean:
	rm -rf xcelium.d INCA_libs *.log *.history
