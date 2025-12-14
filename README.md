# Hardware-Software Co-Design with RISC-V & FPGA

A complete RISC-V processor implementation on FPGA with interrupt support, memory-mapped peripherals, HDMI output, and comprehensive testing infrastructure. This project implements a custom RISC-V processor (RV32I base ISA) with:
- **Two-stage CPU architecture** (Program Counter + Datapath/Operations)
- **Interrupt support** via PLIC (Platform-Level Interrupt Controller) and CLINT (Core-Local Interruptor)
- **Memory-mapped peripherals**: LEDs, switches, timers, HDMI controller
- **HDMI video output** with AXI bus interface
- **Automated testing** for all RV32I instructions with mutant verification
- **Dual compilation modes**: bare-metal assembly and C with libfemto



##  Prerequisites

- **Xilinx Zynq-7000 (xc7z010clg400-1)** FPGA
- **GNU Make** 
- **RISC-V GCC Toolchain**: `riscv32-unknown-elf-*` (with `-march=rv32i -mabi=ilp32` support)
- **Xilinx Vivado 2019.1** (for synthesis, simulation, and FPGA programming)
  - Must source: `/bigsoft/Xilinx/Vivado/2019.1/settings64.sh`


## Understanding the Build System

**There is no default build target** - you must specify which program to compile using `PROG=<name>`.

Available programs:
- Assembly tests: `program/autotest/*.s` (e.g., `add`, `lui`, `jal`)
- Demo programs: `program/*.s` (e.g., `chenillard_rotation`, `compteur`)
- C programs: `program/invaders/invaders.c` (requires `LIB=libfemto`)

### Build and Compile

```bash
# Step 1: Compile a program (generates .mem files for simulation/FPGA)
make compile PROG=add

# Compile assemblycompiles + opens Vivado waveform viewer)
make simulation PROG=lui

# Command-line simulation with custom duration
make simulation_cli PROG=add TIME=5000ns

# Compile + synthesize (no programming)
make synthesis PROG=compteur
```

**Note**: Simulation targets automatically compile the program first.

### Run Automated Tests

```bash
# Run all RISC-V instruction tests (compiles + simulates all tests)
make autotest

# Results appear in:
#   - autotest.res (detailed per-test results)
#   - tag.res (summary by instruction category)
```

### Build and Program FPGA

```bash
# Complete FPGA workflow: compile → synthesize → program board
make fpga PROG=chenillard_rotation

# This will:
# 1. Compile the program to .mem file
# 2. Synthesize HDL to bitstream
# 3. Program the FPGA via JTAG

```bash
# Run all RISC-V instruction tests
make autotest

# Results appear in:
#   - autotest.res (detailed per-test results)
#   - tag.res (summary by instruction category)
```

### Synthesize and Program FPGA

```bash
# Synthesize bitstream and program FPGA
make fpga PROG=chenillard_rotation
```


### Hardware Components

```
PROC (Top-level)
├── CPU
│   ├── CPU_PC  (Program Counter & Control)
│   ├── CPU_PO  (Datapath & Operations)
│   ├── CPU_CND (Condition evaluator)
│   └── CPU_CSR (Control/Status Registers)
├── RAM (32-bit dual-port)
├── PROC_bus (Memory-mapped peripheral interconnect)
└── Peripherals
    ├── IP_LED    (LEDs, switches, buttons)
    ├── IP_Timer  (Programmable timer)
    ├── IP_PLIC   (Interrupt controller)
    ├── IP_CLINT  (Core-local interrupts)
    └── HDMI_*    (Video output subsystem)
```

**Key Design Details:**
- **Type System**: All signals use strongly-typed VHDL from `PKG.vhd` (`w32`, `waddr`, enumerated types)
- **CPU Communication**: Record types `PO_CMD` (PC→PO) and `PO_STATUS` (PO→PC)
- **Mutant Testing**: Generic `mutant` parameter throughout hierarchy for automated verification


**Bare-Metal Assembly** (`LIB=` default):
- Uses `config/link.ld` linker script
- Direct linking with `riscv32-unknown-elf-ld`
- Perfect for autotests and simple demos

**C with libfemto** (`LIB=libfemto`):
- Uses `config/libfemto.ld` linker script
- Links with GCC frontend
- Enables complex programs like Space Invaders (`invaders.c`)

##  Project Structure

```
├── vhd/                    # VHDL sources
│   ├── CPU*.vhd           # Processor components
│   ├── PKG.vhd            # Type definitions and constants
│   ├── PROC*.vhd          # Top-level and bus
│   ├── IP_*.vhd           # Memory-mapped peripherals
│   ├── bench/             # Testbenches
│   └── hdmi/              # HDMI video subsystem
├── program/               # Software
│   ├── autotest/          # One test per RISC-V instruction
│   ├── invaders/          # Space Invaders game (C)
│   └── *.s                # Demo assembly programs
├── config/                # Build system
│   ├── *.mk               # Makefiles
│   ├── *.ld               # Linker scripts
│   ├── *.tcl              # Vivado scripts
│   └── *.xdc              # FPGA constraints
└── bin/                   # Shell scripts for test automation
```



### Autotest Format

Each test in `program/autotest/` follows this structure:

```assembly
# TAG = add
    .text
    lui x1, 0x12345
    add x2, x1, x0
    
    # max_cycle 50
    # pout_start
    # 00000000
    # 12345000
    # pout_end
```

- **TAG**: Instruction category (matched in `program/sequence_tag`)
- **pout_start/pout_end**: Expected outputs (hex values)
- **max_cycle**: Simulation timeout

### Debug Mechanism

Tests use `pout`/`pout_valid` signals as a "printf" for hardware:
- Software writes to special debug port
- Testbench compares against expected values in comments
- Mismatches reported in `autotest.res`

### Viewing Results

```b� Build System Details

### Makefile Targets

| Target | Description | Example |
|--------|-------------|---------|
| `compile` | Compile program to `.mem` | `make compile PROG=add` |
| `simulation` | Compile + run GUI simulation | `make simulation PROG=lui` |
| `simulation_cli` | Compile + run CLI simulation | `make simulation_cli PROG=add TIME=5000ns` |
| `synthesis` | Compile + synthesize bitstream | `make synthesis PROG=compteur` |
| `fpga` | Full flow: compile + synthesize + program FPGA | `make fpga PROG=chenillard_rotation` |
| `autotest` | Run all instruction tests | `make autotest` |
| `clean` | Remove build artifacts | `make clean` |
| `help` | Show available targets | `make help` |

### Variables

- `PROG`: Program name (mandatory for most targets)
- `LIB`: Library to link (`libfemto` for C programs)
- `TIME`: Simulation duration (default: 10000ns)
- `TOP`: Top-level entity (default: PROC)

### Build Artifacts

├── mem/           # Compiled .mem files (memory initialization)
├── sim/           # Simulation working directories
├── autotest.res   # Automated test results
└── tag.res        # Test results by instruction category


## �ash
make autotest

# Check summary
cat tag.res

# Detailed results
cat autotest.res
```

##  Development 

### Adding a New Instruction

1. **Decode** in `CPU_PC.vhd`: Populate `cmd` signals based on instruction bits
2. **Execute** in `CPU_PO.vhd`: Implement datapath operations
3. **Type definitions** in `PKG.vhd`: Add new operation types if needed
4. **Test** in `program/autotest/<inst>.s`: Create test with TAG and expected output
5. **Verify**: Run `make autotest`

### Adding a Memory-Mapped Peripheral

1. Create `IP_<NAME>.vhd` with standard interface:
   - Inputs: `clk`, `rst`, `addr`, `size`, `datai`, `we`, `ce`
   - Output: `datao`
2. Declare component in `PKG.vhd`
3. Instantiate in `PROC.vhd`
4. Add address decoding in `PROC_bus.vhd`

### Debugging Tips

- **Waveforms**: `config/tb_PROC_xsim_beh.wcfg` contains pre-configured signal groups
- **pout debugging**: Add writes to debug port in your assembly/C code
- **Mutant testing**: Use `mutant` parameter to inject faults for testing robustness

## Full RV32I base ISA implementation


- **Arithmetic**: ADD, ADDI, SUB
- **Logical**: AND, ANDI, OR, ORI, XOR, XORI
- **Shifts**: SLL, SLLI, SRL, SRLI, SRA, SRAI
- **Comparison**: SLT, SLTI, SLTU, SLTIU
- **Branches**: BEQ, BNE, BLT, BLTU, BGE, BGEU
- **Jumps**: JAL, JALR
- **Loads**: LW, LH, LHU, LB, LBU
- **Stores**: SW, SH, SB
- **Upper Immediate**: LUI, AUIPC
- **CSR**: CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI
- **Interrupts**: MRET (machine return)

##  Demo Programs

```bash
# LED chaser (minimal)
make fpga PROG=chenillard_minimaliste

# LED rotation pattern
make fpga PROG=chenillard_rotation

# Counter display
make fpga PROG=compteur

# Space Invaders (requires HDMI display)
make fpga PROG=invaders LIB=libfemto
```

##  This project provides hands-on experience with


- **Processor microarchitecture**: Pipeline design, control/datapath separation
- **ISA implementation**: RISC-V instruction decoding and execution
- **Hardware/software interface**: Memory-mapped I/O, interrupts, CSRs
- **FPGA toolchains**: Vivado synthesis, timing constraints, bitstream generation
- **Automated testing**: Mutant testing, regression suites, CI/CD for hardware
- **VHDL best practices**: Strong typing, component hierarchies, generic parameters



## Instruction Status

### Métadonnées

[![timestamp status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//timestamp.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//timestamp.svg)

Fichier de [log](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//log.txt)
### Arithmetiques

[![ADDI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ADDI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ADDI.svg)
[![ADD status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ADD.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ADD.svg)
[![SUB status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SUB.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SUB.svg)
### Basiques

[![REBOUCLAGE status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//REBOUCLAGE.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//REBOUCLAGE.svg)
[![LUI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LUI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LUI.svg)
### Divers

[![AUIPC status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//AUIPC.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//AUIPC.svg)
### Logiques

[![OR status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//OR.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//OR.svg)
[![ORI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ORI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ORI.svg)
[![AND status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//AND.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//AND.svg)
[![ANDI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ANDI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//ANDI.svg)
[![XOR status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//XOR.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//XOR.svg)
[![XORI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//XORI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//XORI.svg)
### Décalages

[![SLL status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLL.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLL.svg)
[![SLLI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLLI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLLI.svg)
[![SRA status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRA.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRA.svg)
[![SRAI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRAI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRAI.svg)
[![SRL status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRL.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRL.svg)
[![SRLI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRLI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SRLI.svg)
### Sets

[![SLT status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLT.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLT.svg)
[![SLTI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTI.svg)
[![SLTIU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTIU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTIU.svg)
[![SLTU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SLTU.svg)
### Branchements

[![BEQ status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BEQ.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BEQ.svg)
[![BGE status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BGE.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BGE.svg)
[![BGEU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BGEU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BGEU.svg)
[![BLT status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BLT.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BLT.svg)
[![BLTU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BLTU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BLTU.svg)
[![BNE status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BNE.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//BNE.svg)
### Sauts

[![JAL status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//JAL.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//JAL.svg)
[![JALR status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//JALR.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//JALR.svg)
### Loads

[![LB status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LB.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LB.svg)
[![LBU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LBU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LBU.svg)
[![LH status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LH.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LH.svg)
[![LHU status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LHU.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LHU.svg)
[![LW status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LW.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//LW.svg)
### Stores

[![SB status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SB.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SB.svg)
[![SH status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SH.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SH.svg)
[![SW status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SW.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//SW.svg)
### Interruptions

[![CSRRC status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRC.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRC.svg)
[![CSRRCI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRCI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRCI.svg)
[![CSRRS status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRS.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRS.svg)
[![CSRRSI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRSI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRSI.svg)
[![CSRRW status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRW.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRW.svg)
[![CSRRWI status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRWI.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//CSRRWI.svg)
[![IT status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//IT.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/Eval/bennassa_lrhorfim_eval//IT.svg)

## Travail evalué en présence des enseignants

[![compteur status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/compteur_bennassa_lrhorfim.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/compteur_bennassa_lrhorfim.svg)
[![chenillard_minimaliste status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/chenillard_minimaliste_bennassa_lrhorfim.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/chenillard_minimaliste_bennassa_lrhorfim.svg)
[![chenillard_rotation status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/chenillard_rotation_bennassa_lrhorfim.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/chenillard_rotation_bennassa_lrhorfim.svg)
[![invaders status](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/invaders_bennassa_lrhorfim.svg)](https://CEP_Deploy.pages.ensimag.fr/CEP_Projet_G1_2024_2025/overview/manual/invaders_bennassa_lrhorfim.svg)



