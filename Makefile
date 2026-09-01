PYTHON ?= python3
IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
NODE ?= node
ARCHIFY_ROOT ?= ../archify-main/archify

RTL = rtl/rv32i_pkg.sv rtl/rv32i_alu.sv rtl/rv32i_imm_gen.sv \
      rtl/rv32i_regfile.sv rtl/rv32i_decoder.sv rtl/rv32i_core.sv \
      rtl/rv32i_soc.sv

.PHONY: all programs test test-sv test-cocotb test-cocotb-waves lint-verilator \
	model docs architecture-map architecture-check wave clean

all: test

programs:
	$(PYTHON) sim/build_programs.py

sim/build:
	mkdir -p sim/build

test: test-sv test-cocotb model

test-sv: programs sim/build
	$(IVERILOG) -g2012 -Wall -s tb_alu -o sim/build/tb_alu.vvp $(RTL) tb/tb_alu.sv
	$(VVP) sim/build/tb_alu.vvp
	$(IVERILOG) -g2012 -Wall -s tb_core_directed -o sim/build/tb_core_directed.vvp $(RTL) tb/tb_core_directed.sv
	$(VVP) sim/build/tb_core_directed.vvp
	$(IVERILOG) -g2012 -Wall -s tb_core_traps -o sim/build/tb_core_traps.vvp $(RTL) tb/tb_core_traps.sv
	$(VVP) sim/build/tb_core_traps.vvp

lint-verilator:
	LANG=C LC_ALL=C $(VERILATOR) --lint-only --timing -Wall -Wno-fatal \
		--top-module rv32i_soc $(RTL)

test-cocotb: programs
	$(PYTHON) scripts/run_cocotb.py

test-cocotb-waves: programs
	$(PYTHON) scripts/run_cocotb.py --waves

model: programs
	$(PYTHON) python/rv32i_model.py

docs:
	$(PYTHON) scripts/build_guide_pdfs.py

architecture-map:
	cd "$(ARCHIFY_ROOT)" && "$(NODE)" bin/archify.mjs deliver architecture \
		"$(CURDIR)/docs/archify/rv32i-core.architecture.json" \
		"$(CURDIR)/docs/archify/rv32i-core.architecture.html" \
		--quality showcase --json

architecture-check:
	cd "$(ARCHIFY_ROOT)" && "$(NODE)" bin/archify.mjs validate architecture \
		"$(CURDIR)/docs/archify/rv32i-core.architecture.json" \
		--quality showcase --json
	cd "$(ARCHIFY_ROOT)" && "$(NODE)" bin/archify.mjs visual-check \
		"$(CURDIR)/docs/archify/rv32i-core.architecture.html" --json

wave: test-cocotb-waves
	./scripts/open_wave.sh

clean:
	rm -rf sim/build
