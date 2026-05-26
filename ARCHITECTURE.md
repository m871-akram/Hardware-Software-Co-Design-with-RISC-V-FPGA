# RISC-V FPGA Processor Architecture

**Target**: Xilinx Zynq-7000 (xc7z010clg400-1) | **ISA**: RV32I | **Clock**: 50 MHz (from 125 MHz via MMCM)

---

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                        PROC (Top-Level)                       │
│                                                               │
│  ┌───────────┐    ┌────────────────────────────────────────┐ │
│  │  CPU      │◄──►│  PROC_bus (address-decoded mux)        │ │
│  │ (2-stage) │    │                                        │ │
│  └─────┬─────┘    ├─► RAM     32 KB  @ 0x0000_1000        │ │
│        │ IRQ      ├─► IP_CLINT 48 KB @ 0x0200_0000        │ │
│  ┌─────▼─────┐    ├─► IP_PLIC  64 MB @ 0x0C00_0000        │ │
│  │ IP_PLIC   │    ├─► IP_LED        @ 0x3000_0000        │ │
│  │ IP_CLINT  │    ├─► IP_PIN        @ 0x3000_0008        │ │
│  └───────────┘    └─► DDR    256 MB @ 0x8000_0000        │ │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐   │
│  │  HDMI Subsystem: HDMI_PC/PO → TMDS Encoder → SERDES  │   │
│  └───────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

**Key specs**: 32-bit data/address · 2-stage pipeline · 32×32b register file · PLIC + CLINT interrupts

---

## CPU Architecture

### Structure

```
┌─────────────────────────────────────────────────┐
│                      CPU                         │
│  ┌──────────────┐  cmd   ┌──────────────────┐   │
│  │   CPU_PC     │───────►│     CPU_PO        │   │
│  │ Control Unit │◄───────│   Datapath        │   │
│  │              │ status │                   │   │
│  │ • FSM        │        │ • Register file   │   │
│  │ • Decoder    │        │ • ALU / Logical   │   │
│  │ • Ctrl sigs  │        │ • Shifter         │   │
│  └──────────────┘        │ • Memory I/F      │   │
│                           │ • CSR (CPU_CSR)   │   │
│  ┌──────────────┐         └──────────────────┘   │
│  │   CPU_CND    │  Branch condition evaluation    │
│  └──────────────┘                                │
└─────────────────────────────────────────────────┘
```

### CPU_PC — Control Unit (`vhd/CPU_PC.vhd`)

State machine with **37 states**: `S_Init` → `S_Pre_Fetch` → `S_Fetch` → `S_Decode` → `S_<INST>` → `S_Pre_Fetch`.  
Special states: `S_IT` (interrupt entry), `S_Error` (illegal instruction).

Responsibilities: opcode decode, state transitions, control signal generation into `PO_CMD`.

### CPU_PO — Datapath (`vhd/CPU_PO.vhd`)

| Unit | Operations |
|------|------------|
| Register file | 32×32b, x0 hardwired to 0, dual-read / single-write |
| ALU | ADD, SUB |
| Logical | AND, OR, XOR |
| Shifter | SLL, SRL, SRA (register or immediate shift) |
| Memory I/F | Byte / half-word / word, sign/zero extension |
| CPU_CSR | Machine-mode CSRs, interrupt enable/status |

Result written back via `DATA_select` mux: `DATA_from_{alu, logical, mem, pc, slt, shifter, csr}`.

### CPU_CND — Branch Conditions (`vhd/CPU_CND.vhd`)

Evaluates BEQ/BNE (equality), BLT/BGE (signed), BLTU/BGEU (unsigned). Outputs boolean `JCOND` to `PO_STATUS`.

---

## Memory System

### Memory Map

| Address Range | Size | Device | Notes |
|---|---|---|---|
| `0x0000_1000 – 0x0000_8FFF` | 32 KB | RAM | Code + data + stack |
| `0x0200_0000 – 0x0200_BFFF` | 48 KB | IP_CLINT | Timer & software IRQ |
| `0x0C00_0000 – 0x0FFF_FFFF` | 64 MB | IP_PLIC | External IRQ controller |
| `0x3000_0000` | 4 B | IP_LED | LEDs (W) / switches (R) |
| `0x3000_0008` | 1 B | IP_PIN | Push buttons + switches |
| `0x8000_0000 – 0x8FFF_FFFF` | 256 MB | DDR3 | External framebuffer |

### PROC_bus (`vhd/PROC_bus.vhd`)

Address-decoded multiplexer: for each cycle, base/high range comparison selects one slave, drives its `ce`/`we`, and OR-reduces the read bus. Single-cycle decode latency.

### RAM32 (`vhd/RAM32.vhd`)

32 KB BRAM, initialized from `.mem` file. Synchronous, single-cycle. Layout: `.text` at `0x1000`, stack grows down from top.

---

## Interrupt System

### Flow

```
External event → PLIC/CLINT → irq ──► CPU_CSR ──► PC = mtvec
                                           │
                                    mepc ← PC
                                    mcause ← code
                                    MIE ← 0
                                           │
                                    Handler runs
                                           │
                                    MRET: PC ← mepc, MIE ← MPIE
```

### IP_PLIC (`vhd/IP_PLIC.vhd`)

Sources: UART, push button (edge-triggered).  
Registers at base: `pending` (+0x00), `enable` (+0x04), `claim` (+0x08).  
Protocol: read `claim` → handle → write `claim` (atomic, prevents interrupt loss).

### IP_CLINT (`vhd/IP_CLINT.vhd`)

64-bit `mtime` counter (increments every cycle) + `mtimecmp` comparator.  
`mtip` asserted when `mtime >= mtimecmp`. Priority: external (`mcause=0x8000000B`) > timer (`mcause=0x80000007`).

### CPU_CSR (`vhd/CPU_CSR.vhd`)

| CSR | Address | Key bits |
|-----|---------|----------|
| mstatus | 0x300 | MIE[3], MPIE[7] |
| mie | 0x304 | MTIE[7], MEIE[11] |
| mtvec | 0x305 | Trap vector base |
| mepc | 0x341 | Return address |
| mip | 0x344 | Pending (read-only) |

Operations: CSRRW / CSRRS / CSRRC (+ immediate variants CSRRWI/CSRRSI/CSRRCI).

---

## Peripheral Devices

### IP_LED (`vhd/IP_LED.vhd`) — `0x3000_0000`

Write `[3:0]` → 4 LEDs. Read `[3:0]` → 3 switches. `pout` signal used for simulation verification.

### IP_PIN (`vhd/IP_PIN.vhd`) — `0x3000_0008`

Read-only. Bits `[18:16]` push buttons, `[3:0]` switches. Edge detection for PLIC interrupt.

### HDMI Subsystem (`vhd/hdmi/`)

AXI master reads DDR framebuffer → TMDS 8b/10b encoder → OSERDES 10:1 serializer → HDMI output.  
Clocks: 50 MHz system · 25 MHz pixel (640×480@60 Hz) · 250 MHz TMDS serial.

---

## Type System & Conventions

**Base types** (`vhd/PKG.vhd`):
```vhdl
subtype w32   is unsigned(31 downto 0);
subtype w16   is unsigned(15 downto 0);
subtype waddr is unsigned(31 downto 0);
```

**Key enums**: `ALU_op_type`, `LOGICAL_op_type`, `SHIFTER_op_type`, `PC_select`, `DATA_select`.

**`PO_CMD` record** (PC → PO): bundles all control signals (ALU, logical, shifter, RF write, PC select, mem access, CSR).  
**`PO_STATUS` record** (PO → PC): `IR` (instruction), `JCOND` (branch result), `IT` (interrupt pending).

**Naming**: `_d` = next-state signal, `_q` = registered value. Components prefixed `CPU_`, `IP_`, `HDMI_`.

---

## Design Decisions

| Decision | Rationale |
|---|---|
| 2-stage pipeline | Minimal hazard logic; FPGA-friendly; sufficient for 50 MHz educational target |
| CPU_PC / CPU_PO split | Clean control/datapath boundary; independent testability; easy instruction addition |
| Strong VHDL types | Type safety over `std_logic_vector`; self-documenting enums; no synthesis overhead |
| Memory-mapped I/O | No special instructions; easy peripheral addition; standard RISC-V approach |
| Single-cycle BRAM | Deterministic timing; native FPGA block RAM; no wait-state logic needed |
| PLIC claim/complete | RISC-V privileged spec compliant; atomic; multi-source scalable |
| `mutant` generic | Systematic fault injection for mutation testing throughout the hierarchy |
| x31 debug output | Non-intrusive simulation output; testbench monitors RF writes to x31 |
| External > timer IRQ | Hardware events are typically more urgent; matches RISC-V convention |

---

## Instruction Set (RV32I)

| Category | Instructions |
|---|---|
| Arithmetic | ADD, ADDI, SUB |
| Logical | AND, ANDI, OR, ORI, XOR, XORI |
| Shift | SLL, SLLI, SRL, SRLI, SRA, SRAI |
| Compare | SLT, SLTI, SLTU, SLTIU |
| Branch | BEQ, BNE, BLT, BLTU, BGE, BGEU |
| Jump | JAL, JALR |
| Load | LW, LH, LHU, LB, LBU |
| Store | SW, SH, SB |
| Upper Imm | LUI, AUIPC |
| CSR | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| Privileged | MRET |
| System | EBREAK |

---

## Resource Utilization (Zynq-7010, approx.)

| Resource | Usage | Available | % |
|---|---|---|---|
| LUTs | ~3 500 | 17 600 | ~20% |
| FFs | ~2 000 | 35 200 | ~6% |
| BRAM 18Kb | 32 | 60 | 53% |
| DSP | 0 | 80 | 0% |
| MMCM | 1 | 2 | 50% |
