# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Prerequisites

- **Xilinx Vivado 2019.1** — source before using simulation/synthesis targets:
  ```bash
  source /bigsoft/Xilinx/Vivado/2019.1/settings64.sh
  ```
- **RISC-V GCC Toolchain** at `/opt/homebrew/bin` — binaries prefixed `riscv64-unknown-elf-*`
- **Target FPGA**: Xilinx Zynq-7000 (`xc7z010clg400-1`)

## Build Commands

There is **no default build target** — `PROG=<name>` is always required.

```bash
# Compile a program to .mem (bare-metal assembly)
make compile PROG=add

# Compile a C program (requires libfemto)
make compile PROG=invaders LIB=libfemto

# Run simulation with GUI (Vivado waveform viewer)
make simulation PROG=add

# Run simulation from CLI with custom duration
make simulation_cli PROG=add TIME=5000ns   # default TIME=10000ns

# Synthesize to bitstream (no FPGA programming)
make synthesis PROG=compteur

# Full flow: compile → synthesize → program FPGA via JTAG
make fpga PROG=chenillard_rotation

# Run all RV32I instruction autotests
make autotest

# Cleanup
make clean        # remove build artifacts
make realclean    # full cleanup including synthesis outputs
make help         # show available targets
```

Autotest results appear in `autotest.res` (per-test) and `tag.res` (by instruction category).

## Architecture

### System Hierarchy

```
PROC (vhd/PROC.vhd)           — top-level: instantiates CPU, RAM, bus, peripherals
├── CPU (vhd/CPU.vhd)         — top-level CPU wrapper
│   ├── CPU_PC (vhd/CPU_PC.vhd)  — control unit: 37-state FSM, fetch/decode/execute
│   ├── CPU_PO (vhd/CPU_PO.vhd)  — datapath: ALU, register file, memory ops
│   ├── CPU_CND (vhd/CPU_CND.vhd)— branch condition evaluator
│   └── CPU_CSR (vhd/CPU_CSR.vhd)— CSR manager (mstatus, mepc, mcause, mtvec…)
├── RAM32 (vhd/RAM32.vhd)     — 32KB on-chip program memory
├── PROC_bus (vhd/PROC_bus.vhd)  — memory-mapped peripheral interconnect
└── Peripherals
    ├── IP_PLIC   — Platform-Level Interrupt Controller
    ├── IP_CLINT  — Core-Local Interruptor (timer/software interrupts)
    ├── IP_LED    — LEDs, switches, debug pout port (x31 writes)
    ├── IP_PIN    — Push buttons
    ├── IP_Timer  — Programmable timer
    └── HDMI subsystem (vhd/hdmi/) — AXI master + video encoder + TMDS
```

### CPU Pipeline (2-stage)

- **Cycle N (Fetch)**: PC → RAM address, instruction read
- **Cycle N+1 (Execute)**: Decode + execute + write-back + PC update

Control is entirely in `CPU_PC` (37-state FSM); computation is entirely in `CPU_PO`. `CPU_CND` evaluates branch conditions; `CPU_CSR` handles machine-mode CSRs and interrupt entry/return.

### Memory Map

| Range | Description |
|-------|-------------|
| `0x0000_1000` | 32KB on-chip RAM |
| `0x3000_0000` | Memory-mapped peripherals (LED, PLIC, CLINT, Timer…) |
| `0x8000_0000` | 256MB external DDR3 (accessed via AXI from HDMI) |

### Type Conventions (vhd/PKG.vhd)

All signals use strongly-typed VHDL enums (e.g., `ALU_op_type`, `LOGICAL_op_type`, `SHIFT_op_type`). This prevents misconnection between control signals. When adding new operations, extend the type in `PKG.vhd` first.

### Adding a New Instruction

1. Add any new control signal types to `vhd/PKG.vhd`
2. Add decode/control logic to `CPU_PC.vhd` (FSM states)
3. Add datapath operation to `CPU_PO.vhd` if needed
4. Write a test in `program/autotest/<insn>.s` following the existing format (TAG, pout_start/end, max_cycle comments)

### Autotest Format

Each `program/autotest/*.s` test file uses comment directives:
```asm
# TAG = <instruction>       # groups results in tag.res
# pout_start
# 0xDEADBEEF               # expected output values (hex, one per line)
# pout_end
# max_cycle 100             # simulation timeout in cycles
```

Output is captured when the program writes to register `x31` (the `pout` debug port via `IP_LED`).

### Software Programs

- `program/autotest/` — 46 per-instruction tests (RV32I coverage)
- `program/*.s` — Demo assembly programs (LED patterns, counters)
- `program/invaders/` — Space Invaders in C (requires `LIB=libfemto`, uses HDMI framebuffer)

Compiled `.mem` files land in `mem/`; simulation working directories land in `sim/<PROG>/`.

### Key Config Files

| File | Purpose |
|------|---------|
| `config/compile_RISCV.mk` | Toolchain flags, assembly/C/link rules |
| `config/link.ld` | Bare-metal linker script |
| `config/libfemto.ld` | C+libfemto linker script |
| `config/PROC_xc7z010clg400-1.xdc` | FPGA pin/timing constraints |
| `config/synthesis.vivado.tcl` | Vivado synthesis automation |
| `config/simulation.xsim.tcl` | xsim simulation automation |
| `bin/objtomem.awk` | Converts ELF object dump → `.mem` hex format |
