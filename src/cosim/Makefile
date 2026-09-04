
CPP_SOURCES = sc_main_cosim.cpp ncc_target_rtl.cpp ../ncc.cpp ../bram.cpp

VHDL_SOURCES = ../vhdl/ncc_pkg.vhd ../vhdl/ncc_core.vhd

INCLUDE_PATHS = -I..

# -v200x (VHDL-2008) ide kroz -xmvhdl_args -- nije fleg xmsc_run-a.
# Treba nam zbog `process (all)` u ncc_core.vhd.
# SC_INCLUDE_DYNAMIC_PROCESSES je u ../common.hpp, ne ovde: tlm_utils socketi
# ga traze PRE #include <systemc>, a -D na komandnoj liniji je lako pogresno
# napisati i greska se ne prijavljuje.
XMSC_OPTIONS = -sc_main -xmvhdl_args,-v200x

all:
	xmsc_run $(XMSC_OPTIONS) $(INCLUDE_PATHS) $(CPP_SOURCES) $(VHDL_SOURCES)

clean:
	rm -rf xcelium.d INCA_libs *.log *.history
