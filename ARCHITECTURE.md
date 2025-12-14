# RISC-V FPGA Processor Architecture


**Target**: Xilinx Zynq-7000 (xc7z010clg400-1)  
**ISA**: RV32I Base Integer Instruction Set


1. [System Overview](#system-overview)
2. [CPU Architecture](#cpu-architecture)
3. [Memory System](#memory-system)
4. [Interrupt System](#interrupt-system)
5. [Peripheral Devices](#peripheral-devices)
6. [Type System & Conventions](#type-system--conventions)
7. [Data Flows](#data-flows)
8. [Design Decisions](#design-decisions)

---

## System Overview

### High-Level Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                            PROC (Top-Level)                      │
│                                                                   │
│  ┌───────────────┐         ┌─────────────────────────────────┐ │
│  │               │         │       PROC_bus                   │ │
│  │     CPU       │◄────────┤   (Memory Interconnect)          │ │
│  │  (2-stage)    │────────►│                                  │ │
│  │               │         └─────────┬───────────────────────┘ │
│  └───────┬───────┘                   │                          │
│          │                           │                          │
│          │ IRQ                       ├─► RAM (32KB @ 0x1000)   │
│          │                           ├─► IP_LED                 │
│  ┌───────▼───────┐                   ├─► IP_PIN                 │
│  │   IP_PLIC     │                   ├─► IP_PLIC                │
│  │   IP_CLINT    │                   ├─► IP_CLINT               │
│  └───────────────┘                   └─► DDR (256MB @ 0x8000000)│
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              HDMI Subsystem (AXI-based)                   │  │
│  │   ┌──────────┐  ┌──────────┐  ┌────────┐  ┌──────────┐  │  │
│  │   │ HDMI_PC  │  │ HDMI_PO  │  │ TMDS   │  │ SERDES   │  │  │
│  │   └──────────┘  └──────────┘  └────────┘  └──────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Specifications

- **Clock**: 50 MHz (derived from 125 MHz via MMCM)
- **Data Width**: 32-bit
- **Address Width**: 32-bit (4GB address space)
- **Pipeline Depth**: 2 stages (Fetch + Execute)
- **Register File**: 32 × 32-bit registers (x0-x31)
- **Memory**: 32KB on-chip RAM + 256MB DDR3 external
- **Peripherals**: Memory-mapped I/O
- **Interrupts**: PLIC (platform-level) + CLINT (core-local)

---

## CPU Architecture

### Two-Stage Design Philosophy

The processor implements a simplified two-stage architecture:

1. **CPU_PC** (Program Counter & Control): Instruction decode and control signal generation
2. **CPU_PO** (Path of Operations): Datapath execution

This separation provides:
- Clear control/datapath boundary
- Simplified state machine design
- Easy instruction addition
- Efficient mutant testing

### CPU Components

```
┌──────────────────────────────────────────────────────────────┐
│                         CPU Entity                            │
│                                                                │
│  ┌──────────────────┐              ┌────────────────────┐    │
│  │    CPU_PC        │              │     CPU_PO         │    │
│  │  (Control Unit)  │──── cmd ────►│   (Datapath)       │    │
│  │                  │◄── status ───│                    │    │
│  │  • State Machine │              │  • Register File   │    │
│  │  • Decoder       │              │  • ALU             │    │
│  │  • Control Sigs  │              │  • Shifter         │    │
│  └──────────────────┘              │  • Memory I/F      │    │
│                                     │  • CSR Registers   │    │
│                                     └────────────────────┘    │
│                                                                │
│  ┌──────────────────┐              ┌────────────────────┐    │
│  │    CPU_CND       │              │     CPU_CSR        │    │
│  │  (Condition)     │              │  (CSR Management)  │    │
│  │  • Comparisons   │              │  • mstatus         │    │
│  │  • Branch Logic  │              │  • mtvec, mepc     │    │
│  └──────────────────┘              │  • mie, mip        │    │
│                                     └────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

### CPU_PC: Control Unit

**File**: `vhd/CPU_PC.vhd`

**State Machine** (37 states):
- `S_Init`: Reset initialization
- `S_Pre_Fetch`: Prepare fetch
- `S_Fetch`: Instruction fetch
- `S_Decode`: Instruction decode
- `S_<INST>`: One state per instruction type
- `S_IT`: Interrupt handling
- `S_Error`: Invalid instruction trap

**Key Responsibilities**:
1. Instruction decoding (opcode analysis)
2. State transition management
3. Control signal generation via `PO_CMD` record
4. Branch/jump decision coordination

**Instruction Decode Example** (from line 150):
```vhdl
when S_Decode =>
    if status.IR(6 downto 0) = "0110111" then        -- LUI
        state_d <= S_LUI;
    elsif status.IR(6 downto 0) = "0010011" then     -- I-type
        if status.IR(14 downto 12) = "000" then      -- ADDI
            state_d <= S_Addi;
        -- ... more I-type instructions
```

### CPU_PO: Datapath

**File**: `vhd/CPU_PO.vhd`

**Key Components**:

1. **Register File**:
   - 32 registers × 32 bits
   - x0 hardwired to zero
   - Dual-read, single-write ports

2. **ALU (Arithmetic Logic Unit)**:
   - Operations: ADD, SUB
   - Controlled by `ALU_op_type` enum
   - Multiplexed inputs (rs2 or immediate)

3. **Logical Unit**:
   - Operations: AND, OR, XOR
   - Separate from ALU for parallel execution

4. **Shifter**:
   - Operations: SLL, SRL, SRA
   - Variable shift amount (register or immediate)

5. **Memory Interface**:
   - Size-aware (byte, half-word, word)
   - Sign/zero extension support
   - Aligned access handling

6. **CSR Subsystem** (`CPU_CSR`):
   - Machine-mode CSRs
   - Interrupt enable/status
   - Exception handling

**Data Multiplexing**:
```vhdl
type DATA_select is (
    DATA_from_alu,      -- ALU result
    DATA_from_logical,  -- Logical operation result
    DATA_from_mem,      -- Memory load
    DATA_from_pc,       -- PC value (for JAL/JALR)
    DATA_from_slt,      -- Set-less-than result
    DATA_from_shifter,  -- Shifter result
    DATA_from_csr       -- CSR read
);
```

### CPU_CND: Condition Evaluator

**File**: `vhd/CPU_CND.vhd`

**Purpose**: Branch condition evaluation

**Comparisons**:
- Equality (BEQ/BNE)
- Signed comparison (BLT/BGE)
- Unsigned comparison (BLTU/BGEU)

**Output**: Boolean flag used for PC control

---

## Memory System

### Memory Map

| Base Address | End Address  | Size   | Device        | Description                    |
|-------------|-------------|--------|---------------|--------------------------------|
| 0x0000_1000 | 0x0000_8FFF | 32 KB  | RAM           | Program and data memory        |
| 0x0200_0000 | 0x0200_C000 | 48 KB  | IP_CLINT      | Core-local interrupts & timer  |
| 0x0C00_0000 | 0x1000_0000 | 64 MB  | IP_PLIC       | Platform interrupt controller  |
| 0x3000_0000 | 0x3000_0004 | 5 B    | IP_LED        | LEDs, switches, debug          |
| 0x3000_0008 | 0x3000_0008 | 1 B    | IP_PIN        | Push buttons                   |
| 0x8000_0000 | 0x8FFF_FFFF | 256 MB | DDR           | External DDR3 memory           |

### PROC_bus: Memory Interconnect

**File**: `vhd/PROC_bus.vhd`

**Architecture**: Address-decoded multiplexer

**Features**:
- Parameterized slave count
- Base/high address ranges per slave
- Single-cycle address decode
- Registered chip-enable signals
- OR-reduced read data bus

**Address Decoding Logic**:
```vhdl
for i in 0 to N_SLAVE-1 loop
    if CPU_addr >= base(i) and CPU_addr <= high(i) then
        ce_d(i) <= CPU_ce;
        we(i)   <= CPU_we;
    end if;
end loop;
```

**Data Multiplexing**:
- Only selected slave's data propagates
- OR reduction ensures no bus conflicts
- Single-cycle read latency

### RAM32: Program Memory

**File**: `vhd/RAM32.vhd`

**Configuration**:
- Size: 32,768 bytes (32 KB)
- Initialization: From `.mem` file
- Access: Word, half-word, byte
- Timing: Single-cycle synchronous

**Memory Layout**:
```
0x1000: .text section (code)
0x????:  .data section (initialized data)
0x????:  .bss section (uninitialized)
0x8FFF: Stack top (grows down)
```

---

## Interrupt System

### Overview

Two-level interrupt architecture following RISC-V Privileged Specification:

1. **PLIC** (Platform-Level Interrupt Controller): External interrupts
2. **CLINT** (Core-Local Interruptor): Software & timer interrupts

### Interrupt Flow

```
External Event → PLIC/CLINT → IRQ Signal → CPU_CSR → PC = mtvec
                                                ↓
                                           Save mepc
                                           Set mcause
                                                ↓
                                         Handler Execution
                                                ↓
                                           MRET → PC = mepc
```

### IP_PLIC: Platform Interrupt Controller

**File**: `vhd/IP_PLIC.vhd`

**Registers**:
- **Pending** (offset 0x00): Interrupt pending bits
- **Enable** (offset 0x04): Interrupt enable mask
- **Claim** (offset 0x08): Claim/complete mechanism

**Interrupt Sources**:
1. UART (external)
2. Push button (edge-triggered)

**Claim/Complete Protocol**:
1. Read `claim`: Returns highest priority pending & enabled interrupt ID
2. Handle interrupt
3. Write `claim`: Complete the interrupt (clear pending bit)

### IP_CLINT: Core-Local Interrupts

**File**: `vhd/IP_CLINT.vhd`

**Registers**:
- **mtime** (offset 0x0000): 64-bit timer counter
- **mtimecmp** (offset 0x0008): 64-bit timer comparator

**Timer Interrupt**:
- Increments every clock cycle
- Generates `mtip` when `mtime >= mtimecmp`
- Used for preemptive scheduling

**Priority Resolution**:
```vhdl
-- In IP_CLINT:
if (mie(11) and meip) = '1' then       -- External interrupt
    irq <= '1'; mcause <= X"8000000B";
elsif (mie(7) and mtip) = '1' then     -- Timer interrupt
    irq <= '1'; mcause <= X"80000007";
end if;
```

### CPU_CSR: Control & Status Registers

**File**: `vhd/CPU_CSR.vhd`

**Machine-Mode CSRs** (addresses in hex):
- **0x300 (mstatus)**: Machine status
  - Bit 3 (MIE): Global interrupt enable
  - Bit 7 (MPIE): Previous interrupt enable
- **0x304 (mie)**: Interrupt enable register
  - Bit 7 (MTIE): Timer interrupt enable
  - Bit 11 (MEIE): External interrupt enable
- **0x305 (mtvec)**: Trap vector base address
- **0x341 (mepc)**: Exception program counter
- **0x344 (mip)**: Interrupt pending (read-only)

**CSR Operations**:
- **CSRRW**: Atomic read/write
- **CSRRS**: Atomic read & set bits
- **CSRRC**: Atomic read & clear bits
- Immediate variants: CSRRWI, CSRRSI, CSRRCI

**Write Modes**:
```vhdl
type CSR_WRITE_mode_type is (
    WRITE_mode_simple,   -- Direct write
    WRITE_mode_set,      -- OR with value
    WRITE_mode_clear     -- AND NOT with value
);
```

---

## Peripheral Devices

### IP_LED: LED & Switch Interface

**File**: `vhd/IP_LED.vhd`

**Address**: 0x3000_0000

**Functionality**:
- **Write**: Drive 4 LEDs
- **Read**: Read 3 switches
- **Debug**: `pout` signal for simulation verification

**Memory Map**:
```
Offset 0x0: [31:4] Reserved
            [3:0]   LED outputs (write) / Switch inputs (read)
```

### IP_PIN: Push Button Interface

**File**: `vhd/IP_PIN.vhd`

**Address**: 0x3000_0008

**Functionality**:
- Read 3 push buttons + 4 switches
- Edge detection for interrupt generation

**Data Format**:
```
[31:19] Reserved
[18:16] Push buttons
[15:4]  Reserved
[3:0]   Switches
```

### HDMI Subsystem

**Files**: `vhd/hdmi/*.vhd`

**Architecture**:
```
┌─────────────────────────────────────────────────┐
│           HDMI_Controller                        │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ HDMI_PC  │  │ HDMI_PO  │  │ AXI Master  │  │
│  │          │  │          │  │ (DDR access)│  │
│  └────┬─────┘  └────┬─────┘  └──────┬──────┘  │
│       │             │               │          │
│  ┌────▼─────────────▼───────────────▼──────┐  │
│  │        Video Encoder & TMDS              │  │
│  │  ┌──────────┐  ┌──────────────────────┐ │  │
│  │  │ RGB Gen  │  │ TMDS Encoder         │ │  │
│  │  └──────────┘  └──────────────────────┘ │  │
│  └──────────────────┬───────────────────────┘  │
│                     │                           │
│  ┌──────────────────▼───────────────────────┐  │
│  │     Output SERDES (10:1 Serialization)   │  │
│  └──────────────────┬───────────────────────┘  │
└────────────────────┬─────────────────────────┘
                      │
              HDMI Physical Output
```

**Key Features**:
- AXI bus master for DDR framebuffer access
- TMDS encoding (8b/10b)
- 10:1 serialization via OSERDES
- Configurable video modes (VIC interpreter)
- Clock generation for pixel/serial clocks

**Clock Domains**:
- 50 MHz: System clock
- 25 MHz: Pixel clock (example for 640×480@60Hz)
- 250 MHz: TMDS serial clock (10× pixel clock)

---

## Type System & Conventions

### Custom Types (from PKG.vhd)

**Base Types**:
```vhdl
subtype w32   is unsigned(31 downto 0);  -- 32-bit word
subtype w16   is unsigned(15 downto 0);  -- 16-bit half-word
subtype waddr is unsigned(31 downto 0);  -- Address type
```

**Enumerated Types**:
```vhdl
type ALU_op_type is (ALU_plus, ALU_minus, UNDEFINED);

type LOGICAL_op_type is (
    LOGICAL_and, LOGICAL_or, LOGICAL_xor, UNDEFINED
);

type SHIFTER_op_type is (
    SHIFT_rl,  -- Right logical
    SHIFT_ra,  -- Right arithmetic
    SHIFT_ll,  -- Left logical
    UNDEFINED
);

type PC_select is (
    PC_from_alu,   -- Branch target
    PC_mtvec,      -- Interrupt vector
    PC_rstvec,     -- Reset vector
    PC_from_pc,    -- Sequential (PC+4)
    PC_from_mepc   -- Interrupt return
);
```

### Command/Status Interface

**PO_CMD Record** (PC → PO):
```vhdl
type PO_cmd is record
    -- ALU control
    ALU_op      : ALU_op_type;
    ALU_Y_sel   : ALU_Y_select;
    
    -- Logical unit control
    LOGICAL_op  : LOGICAL_op_type;
    
    -- Shifter control
    SHIFTER_op  : SHIFTER_op_type;
    SHIFTER_Y_sel : SHIFTER_Y_select;
    
    -- Register file control
    RF_we       : std_logic;
    RF_SIZE_sel : RF_SIZE_select;
    DATA_sel    : DATA_select;
    
    -- PC control
    PC_we       : std_logic;
    PC_sel      : PC_select;
    
    -- Memory control
    mem_we      : std_logic;
    mem_ce      : std_logic;
    ADDR_sel    : ADDR_select;
    
    -- CSR control
    cs          : PO_cs_cmd;
end record;
```

**PO_STATUS Record** (PO → PC):
```vhdl
type PO_status is record
    IR    : w32;        -- Current instruction
    JCOND : boolean;    -- Branch condition result
    IT    : boolean;    -- Interrupt pending
end record;
```

### Naming Conventions

1. **Signals**: `<name>_d` (next state), `<name>_q` (current state)
2. **Types**: PascalCase with `_type` suffix
3. **Constants**: UPPER_CASE
4. **Components**: Prefixed by function (CPU_, IP_, HDMI_)
5. **Registers**: Suffixed by function (_q for current, _d for next)

---

## Data Flows

### Instruction Execution Pipeline

```
Cycle N: Fetch
┌─────────────────────────────────────────┐
│ 1. PC → RAM address                     │
│ 2. RAM → IR (instruction register)      │
│ 3. State: S_Fetch → S_Decode            │
└─────────────────────────────────────────┘

Cycle N+1: Decode & Execute
┌─────────────────────────────────────────┐
│ 1. Decode opcode in CPU_PC              │
│ 2. Generate control signals (PO_CMD)    │
│ 3. Execute in CPU_PO:                   │
│    - Read register file                 │
│    - ALU/Logical/Shifter operation      │
│    - Memory access (if load/store)      │
│    - Write back to register             │
│ 4. Update PC                             │
│ 5. State: S_<INST> → S_Pre_Fetch        │
└─────────────────────────────────────────┘

Cycle N+2: Fetch next instruction
```

### Memory Access Flow

**Load Instruction** (e.g., LW):
```
1. S_Decode → S_Lw
2. Compute address: rs1 + imm
3. State: S_Lw → S_charger_Mem
4. Address output: mem_addr <= AD_q
5. State: S_charger_Mem → S_lecture_Mem
6. Read data: mem_datain → RF
7. State: S_lecture_Mem → S_Pre_Fetch
```

**Store Instruction** (e.g., SW):
```
1. S_Decode → S_Sw
2. Compute address: rs1 + imm
3. State: S_Sw → S_charger_Mem
4. Prepare data: rs2 → mem_dataout
5. State: S_charger_Mem → S_ecriture_Mem
6. Write: mem_we <= '1'
7. State: S_ecriture_Mem → S_Pre_Fetch
```

### Interrupt Handling Flow

```
1. External event → PLIC/CLINT
2. PLIC/CLINT → meip/mtip assertion
3. CPU_CSR checks: (mstatus.MIE) AND (mie.MEIE/MTIE)
4. If enabled:
   a. mepc ← PC (save return address)
   b. mcause ← interrupt code
   c. mstatus.MPIE ← mstatus.MIE
   d. mstatus.MIE ← 0 (disable interrupts)
   e. PC ← mtvec (jump to handler)
5. Handler execution
6. MRET instruction:
   a. PC ← mepc (return)
   b. mstatus.MIE ← mstatus.MPIE
   c. Resume normal execution
```

### Debug Port Flow

**pout Signal** (simulation only):
```
Assembly:         lw x31, 0(x1)
                  ↓
CPU_PO:           pout_d <= RF_d(31)
                  pout_valid_d <= RF_we and (to_integer(rd) = 31)
                  ↓
Testbench:        Compare pout against expected values
                  Report PASSED/FAILED
```

---

## Design Decisions

### 1. Two-Stage vs. Multi-Stage Pipeline

**Decision**: Two-stage architecture (Fetch + Execute)

**Rationale**:
- **Simplicity**: Easier state machine, minimal hazard handling
- **Educational**: Clear separation of concerns
- **FPGA-friendly**: Lower resource usage, simpler timing
- **Testability**: Mutant testing more manageable
- **Performance**: Sufficient for 50 MHz target (educational project)

**Trade-offs**:
- Lower IPC (instructions per cycle) vs. deeper pipelines
- Sequential memory access (no overlap)
- Simpler hazard handling (no forwarding needed)

### 2. Control/Datapath Separation

**Decision**: Separate CPU_PC (control) and CPU_PO (datapath)

**Rationale**:
- **Modularity**: Independent testing and modification
- **Clarity**: Clean interface via PO_CMD/PO_STATUS records
- **Scalability**: Easy to add instructions (modify PC, reuse PO)
- **Debugging**: Isolated signal observation

### 3. Strongly-Typed VHDL

**Decision**: Custom types instead of `std_logic_vector`

**Rationale**:
- **Type safety**: Prevents signal misconnection
- **Readability**: `ALU_plus` vs. magic numbers
- **Maintainability**: Enum changes propagate automatically
- **Synthesis**: No performance impact

**Example**:
```vhdl
-- Bad:
signal alu_op : std_logic_vector(1 downto 0);
alu_op <= "00";  -- What does this mean?

-- Good:
signal alu_op : ALU_op_type;
alu_op <= ALU_plus;  -- Self-documenting
```

### 4. Memory-Mapped I/O

**Decision**: All peripherals on unified address bus

**Rationale**:
- **Simplicity**: No special I/O instructions
- **RISC-V compliance**: Standard approach
- **Flexibility**: Easy to add peripherals
- **Debuggability**: Memory monitor sees all accesses

**Alternative considered**: Dedicated I/O space (rejected for complexity)

### 5. Single-Cycle Memory

**Decision**: Synchronous RAM with single-cycle latency

**Rationale**:
- **FPGA block RAM**: Native single-cycle access
- **Deterministic timing**: No wait states
- **Simplified control**: No memory controller needed

**Limitation**: External DDR requires multi-cycle (handled by HDMI subsystem)

### 6. PLIC Claim/Complete Protocol

**Decision**: Standard RISC-V claim/complete mechanism

**Rationale**:
- **Compliance**: Matches RISC-V privileged spec
- **Atomicity**: Prevents interrupt loss
- **Multi-source**: Scalable to many interrupts

**Flow**:
1. Handler reads claim → Gets interrupt ID, clears pending
2. Handler executes
3. Handler writes claim → Signals completion

### 7. Mutant Testing Integration

**Decision**: Generic `mutant` parameter throughout hierarchy

**Rationale**:
- **Automated testing**: Inject faults systematically
- **Verification**: Ensure tests catch errors
- **Educational**: Demonstrate testing techniques

**Usage**:
```vhdl
generic (mutant : integer := 0);

-- In implementation:
if mutant = 42 then
    -- Intentionally buggy code for testing
else
    -- Correct implementation
end if;
```

### 8. Debug via Register x31

**Decision**: Use x31 writes for simulation output

**Rationale**:
- **Non-intrusive**: Doesn't affect normal program flow
- **Simple**: No special instructions
- **Effective**: Testbench monitors register writes

**Alternative considered**: Memory-mapped debug port (rejected for test simplicity)

### 9. Interrupt Priority

**Decision**: External > Timer

**Rationale**:
- **Hardware events**: External interrupts are typically urgent
- **Preemption**: Allows hardware to interrupt timed tasks
- **RISC-V convention**: Standard priority ordering

---

## Appendices

### A. Complete Instruction Set

**RV32I Base Instructions** (48 total):

| Category       | Instructions                                      |
|----------------|---------------------------------------------------|
| Arithmetic     | ADD, ADDI, SUB                                    |
| Logical        | AND, ANDI, OR, ORI, XOR, XORI                     |
| Shift          | SLL, SLLI, SRL, SRLI, SRA, SRAI                   |
| Compare        | SLT, SLTI, SLTU, SLTIU                            |
| Branch         | BEQ, BNE, BLT, BLTU, BGE, BGEU                    |
| Jump           | JAL, JALR                                         |
| Load           | LW, LH, LHU, LB, LBU                              |
| Store          | SW, SH, SB                                        |
| Upper Imm      | LUI, AUIPC                                        |
| CSR            | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI       |
| Privileged     | MRET                                              |
| System         | EBREAK (for simulation)                           |

### B. Signal Naming Examples

```vhdl
-- Synchronous signals (registered)
signal PC_d, PC_q : w32;           -- Next/Current PC
signal state_d, state_q : State_type;

-- Combinational signals
signal ALU_res : w32;              -- ALU result
signal mem_addr : waddr;           -- Memory address

-- Control signals
signal RF_we : std_logic;          -- Register write enable
signal mem_ce : std_logic;         -- Memory chip enable

-- Array types
signal RF_q : register_file_type;  -- Register file
signal bus_datai : w32_vec;        -- Bus data array
```

### C. Resource Utilization (Typical)

| Resource      | Usage  | Available | Utilization |
|---------------|--------|-----------|-------------|
| LUTs          | ~3,500 | 17,600    | ~20%        |
| FFs           | ~2,000 | 35,200    | ~6%         |
| BRAM (18Kb)   | 32     | 60        | 53%         |
| DSP Slices    | 0      | 80        | 0%          |
| MMCM          | 1      | 2         | 50%         |

*Note: Values approximate, depends on synthesis settings*

