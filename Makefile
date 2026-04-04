## Parameters
#PROG ?= lui # no more default value here
TOP  ?= PROC
TIME ?= 10000ns
VERB ?= 0
SEQUENCE  ?= program/sequence_tag
TESTS_DIR ?= program/autotest/
LOG ?= log


.PHONY: compile simulation synthesis fpga autotest clean realclean check_PROG compile_invaders_sim

## Main rule
all: help

## Directories
include config/directory.mk

# Sub Makefiles
SIMULATION_MK:=config/simulation.mk
SYNTHESIS_MK:=config/synthesis.mk
AUTOTEST_MK:=config/autotest.mk
COMPILE_MK:=config/compile_RISCV.mk

## Rules

# Check that the PROG variable is correctly set
check_PROG:
	@if [ -z "$$PROG" ]; then \
		echo "ERROR: variable PROG undefined"; \
		exit 1; \
	fi

# Compile
compile: export PROG:=$(PROG)
compile: export LOG:=$(LOG)
compile: check_PROG |clean_log
	@$(MAKE) -s -f $(COMPILE_MK)

# Simulation with GUI
simulation: export TOP:=$(TOP)
simulation: export LOG:=$(LOG)
simulation: compile | clean_log
	@bash -c 'source /bigsoft/Xilinx/Vivado/2019.1/settings64.sh && $(MAKE) -s -f $(SIMULATION_MK) GUI'
	

# Simulation whithout gui
simulation_cli: export TIME:=$(TIME)
simulation_cli: export TOP:=$(TOP)
simulation_cli: export LOG:=$(LOG)
simulation_cli: compile |clean_log
	@$(MAKE) -s -f $(SIMULATION_MK) run trace

# Synthesis 
synthesis: export TOP:=$(TOP)
synthesis: export LOG:=$(LOG)
synthesis: compile |clean_log
	@$(MAKE) -s -f $(SYNTHESIS_MK)

# Loads on FPGA
fpga: export TOP:=$(TOP)
fpga: export LOG:=$(LOG)
fpga: compile
	@$(MAKE) -s -f $(SYNTHESIS_MK) run


# Autotests
autotest: export SEQUENCE_TAG:=$(SEQUENCE)
autotest: export TESTS_DIR:=$(TESTS_DIR)
autotest: export LOG:=$(LOG)
autotest: |clean_log
	@$(MAKE) -s -f $(AUTOTEST_MK) print


clean_log:
	rm -f $(LOG)

clean: export LOG:=$(LOG)
clean:
	@$(MAKE) -s -f $(COMPILE_MK) clean
	@$(MAKE) -s -f $(AUTOTEST_MK) clean
	@$(MAKE) -s -f $(SYNTHESIS_MK) clean
	@$(MAKE) -s -f $(SIMULATION_MK) clean

clean_femto: export LOG:=$(LOG)
clean_femto:
	@$(MAKE) -s -f $(COMPILE_MK) clean_femto

realclean: export LOG:=$(LOG)
realclean:
	@$(MAKE) -s -f $(COMPILE_MK) realclean
	@$(MAKE) -s -f $(AUTOTEST_MK) realclean
	@$(MAKE) -s -f $(SYNTHESIS_MK) realclean
	@$(MAKE) -s -f $(SIMULATION_MK) realclean

## --- GHDL simulation targets ---

CC_SIM      := /opt/homebrew/bin/riscv64-unknown-elf-gcc
OBJDUMP_SIM := /opt/homebrew/bin/riscv64-unknown-elf-objdump
OBTOMEM     := bin/objtomem.awk

CFLAGS_SIM  := -Os -march=rv32i -mabi=ilp32 -mcmodel=medany \
               -ffunction-sections -fdata-sections \
               -fno-builtin \
               -DENV_FPGA=1 -DENV_SIM=1 \
               -Iprogram/invaders

LDFLAGS_SIM := -nostartfiles -nodefaultlibs \
               -T config/invaders_sim.ld \
               -Wl,--gc-sections

# Compile Space Invaders for GHDL simulation (320x240, fast timer, no libfemto)
compile_invaders_sim: mem/invaders_sim.mem

mem/invaders_sim.elf: program/invaders/invaders.c program/invaders/invaders.h \
                      program/invaders/cep_platform.h config/invaders_sim.ld
	@mkdir -p mem
	$(CC_SIM) $(CFLAGS_SIM) $(LDFLAGS_SIM) \
	    -o $@ program/invaders/invaders.c -lgcc

mem/invaders_sim.mem: mem/invaders_sim.elf
	$(OBJDUMP_SIM) --section=.text --section=.data --section=.rodata \
	               --section=.bss --section=.sdata -s $< \
	    | awk -f $(OBTOMEM) > $@
	@echo "Generated $@ (size: $$(wc -l < $@) lines)"

# Help message
help:
	@echo "Usage:"
	@echo "  make <target> [<variable>]"
	@echo ""
	@echo "Targets:"
	@echo "  help            Affiche cette aide."
	@echo "  clean           Suppression des fichiers générés."
	@echo "  simulation      Lance la simulation."
	@echo "  autotest        Lance les autotests."
	@echo "  synthesis       Lance la synthèse."
	@echo "  fpga            Lance la synthèse et programme le FPGA."
	@echo ""
	@echo "Variables:"
	@echo "  TOP=<top>       Definit le top design à synthétiser ou simuler."
	@echo "  PROG=<prog>     Definit le programme RISCV à executer."
	@echo "  TIME=<time>     Définit le temps de simulation maximum. (Exemple: TIME=100ns)"
	@echo "  SEQUENCE=<seq>  Définit une séquence de tests pour autotest."
	@echo ""
	@echo "Exemples:"
	@echo "make simulation PROG=counter TIME=1000ns"
	@echo "make autotest SEQUENCE=program/sequence_test0"
	@echo ""
