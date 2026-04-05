# Simulation Plan: Space Invaders on RISC-V via GHDL

Goal: compile Space Invaders C code → produce RISC-V .mem → run GHDL hardware simulation → dump VRAM writes → render PNG frames.

---

## Phase 1: Environment Setup

- [ ] **1.1** Install GHDL with LLVM backend: `brew install ghdl`
- [ ] **1.2** Verify GHDL supports VHDL-2008: `ghdl --version` (need ≥ 1.0)
- [ ] **1.3** Verify RISC-V toolchain: `which riscv64-unknown-elf-gcc` → must be `/opt/homebrew/bin/`
- [ ] **1.4** Locate libgcc for RV32I (needed for 64-bit arithmetic helpers like `__lshrdi3`):
         `riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -print-libgcc-file-name`
- [ ] **1.5** Install Python renderer dependency: `pip3 install Pillow`

---

## Phase 2: C Code Fix and Compilation (without libfemto)

### Why no libfemto?
`libfemto` is a university-installed C runtime at `/opt/homebrew/lib/cep_riscv/`. It is not a standard Homebrew package. Since `invaders.c` defines its own `_start` and uses no libc functions (no printf, malloc, etc.), we can compile without it. We only need `libgcc.a` for 64-bit shift/multiply helpers required by the timer code (`(uint64_t)period >> 8` etc.).

### Changes to existing files

- [ ] **2.1** `program/invaders/invaders.c` line 305: rename `void *memset(...)` → `void *custom_memset(...)`.
  - This function is defined but never called (it's dead code), however it will cause a duplicate-symbol linker error if libgcc or any future library also defines `memset`.
  - No call sites need updating — `clear_screen` calls `memset_32b`, which is a separate function.

- [ ] **2.2** Add an `ENV_SIM` timer frequency to `program/invaders/cep_platform.h`:
  ```c
  #elif defined(ENV_SIM)
  #define TIMER_FREQ  50000   // ~1000x faster; each game loop waits ~780 ticks = 15µs @ 50MHz
  #define TIMER_RATIO 200
  ```
  Without this, `timer_set_and_wait(TIMER_FREQ=100000000, 4)` would require simulating ~1.5 million clock cycles per game-loop iteration — hours of GHDL wall-clock time.

- [ ] **2.3** *(Optional but recommended for simulation speed)* Reduce display size in `program/invaders/invaders.c` (lines 18–19):
  ```c
  // Original: 1280 × 720 = 921,600 pixels per clear_screen
  // For sim:   320 × 240 =  76,800 pixels per clear_screen (12× faster)
  #define DISPLAY_WIDTH  320
  #define DISPLAY_HEIGHT 240
  ```
  Also update `MAX_X` and the `#if DISPLAY_HEIGHT == 720` block accordingly. This changes the sprite placement but keeps gameplay logic intact.

### New file: `config/invaders_sim.ld`

Bare-metal C linker script. Replaces `libfemto.ld` without requiring `crt.o`, `setup.o`, or `libfemto.a`:

```ld
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  ram (wxa!ri): ORIGIN = 0x1000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    *(.text.init) *(.text .text.*)
  } > ram

  .rodata : {
    *(.rodata .rodata.*)
  } > ram

  .data : {
    . = ALIGN(4);
    *(.sdata .sdata.*) *(.data .data.*)
  } > ram

  .bss : {
    . = ALIGN(4);
    *(.sbss .sbss.*) *(.bss .bss.*)
  } > ram

  PROVIDE(_memory_start = ORIGIN(ram));
  PROVIDE(_memory_end   = ORIGIN(ram) + LENGTH(ram));
}
```

### New file: `Makefile.sim` (or add a target to main Makefile)

```makefile
CC      := /opt/homebrew/bin/riscv64-unknown-elf-gcc
OBJDUMP := /opt/homebrew/bin/riscv64-unknown-elf-objdump

CFLAGS_SIM := -Os -march=rv32i -mabi=ilp32 -mcmodel=medany \
              -ffunction-sections -fdata-sections \
              -DENV_FPGA=1 -DENV_SIM=1 \
              -Iprogram/invaders

LDFLAGS_SIM := -nostartfiles -nodefaultlibs \
               -T config/invaders_sim.ld \
               -Wl,--gc-sections

compile_invaders_sim:
	$(CC) $(CFLAGS_SIM) $(LDFLAGS_SIM) \
	    -o mem/invaders_sim.elf \
	    program/invaders/invaders.c \
	    -lgcc
	$(OBJDUMP) --section=.text --section=.data --section=.rodata \
	           --section=.bss --section=.sdata -s mem/invaders_sim.elf \
	    | awk -f bin/objtomem.awk > mem/invaders_sim.mem
```

**Key gotcha:** `-nodefaultlibs` strips libgcc, but the timer code (`(uint64_t)period >> 8`) compiles to `__lshrdi3`. Add `-lgcc` explicitly at the end of the link command to pull in only the 64-bit math helpers, not the full C library.

- [ ] **2.4** Run the compile and verify `mem/invaders_sim.mem` is non-empty and starts near address `0x1000`.

---

## Phase 3: VHDL Mocking for GHDL

GHDL has no built-in Xilinx libraries. We must provide three sets of mocks:

### 3.1 `vhd/sim/unisim_mock.vhd` → compiled as library `unisim`

Used by: `PROC.vhd`, `ClockGen.vhd`, `ClockGenApprox.vhd`, `HDMI_simple.vhd`, `HDMI_ENV.vhd`, `OutputSERDES.vhd`.

Components to mock:

| Primitive | Used in | Mock behaviour |
|-----------|---------|----------------|
| `MMCME2_BASE` | PROC, ClockGen, ClockGenApprox | Pass `CLKIN1 → CLKOUT0`, `CLKOUT1`, `CLKOUT2`; drive `LOCKED='1'` after 100 ns. `CLKFBOUT <= CLKIN1`. This means the CPU clock equals the testbench clock directly. |
| `BUFG` | PROC, ClockGen, HDMI_ENV | Simple wire: `O <= I` |
| `OBUFDS` | HDMI_simple | Differential stub: `O <= I; OB <= not I` |
| `OSERDESE2` | OutputSERDES | Stub: `OQ <= D1; SHIFTOUT1 <= '0'; SHIFTOUT2 <= '0'` — we never need actual TMDS serialisation in simulation |

This file must use `package vcomponents` inside `library unisim` so that `use unisim.vcomponents.all` compiles.

### 3.2 `vhd/sim/xpm_mock.vhd` → compiled as library `xpm`

Used by: `RAM32.vhd` (`XPM_MEMORY_SPRAM`) and `RAM16DP.vhd` (`XPM_MEMORY_TDPRAM`).

**`XPM_MEMORY_SPRAM`** — this is the critical one. The RISC-V CPU fetches and stores instructions/data through this RAM. It must work correctly:
- Generics that matter: `MEMORY_SIZE` (bits), `ADDR_WIDTH_A`, `BYTE_WRITE_WIDTH_A=8`, `WRITE_DATA_WIDTH_A=32`, `READ_LATENCY_A=1`, `MEMORY_INIT_FILE`
- Use an `impure function init_ram(file_name : string) return mem_array_t` that reads the `.mem` file line-by-line via VHDL `textio` / `hread` (the file is one 32-bit hex word per line)
- Byte-write enable: `weA` is 4 bits; each bit enables one byte lane
- 1-cycle read latency: register the output on rising `clkA`

**`XPM_MEMORY_TDPRAM`** — used by HDMI internals; can be a simpler dual-port RAM stub (not critical for game correctness since we bypass the HDMI output path).

**Important:** First, read `bin/objtomem.awk` to confirm the exact `.mem` file format before implementing the init function. If the file has `@address` markers (Verilog `$readmemh` style), the reader must skip them or handle sparse layout.

### 3.3 `vhd/sim/PS_Link_sim.vhd` → compiled as `work` (provides `entity PS_Link`)

`PS_Link` is a Xilinx Zynq Processing System IP block (not a standard HDL file in the repo). In hardware it manages DDR3 and reads back framebuffer data for HDMI. In simulation we replace it with a write logger.

Port interface (must exactly match the `component PS_Link` declaration in `PROC.vhd`):
- Inputs: all DDR/FIXED_IO inout ports (left open/high-Z in testbench), `axi_clk`, `axi_rst`, `hdmi_ddr_ack`, `hdmi_pixel_clk`, `hdmi_reset_mem`, `ddr_axi_addr[31:0]`, `ddr_din[31:0]`, `ddr_we`
- Outputs: `hdmi_r[7:0]`, `hdmi_g[7:0]`, `hdmi_b[7:0]`, `hdmi_ddr_valid`, `hdmi_reset_mem_ack`

Behaviour:
1. On every rising `axi_clk` where `ddr_we='1'`: append `"ADDR DATA\n"` (hex) to `sim/vram_writes.txt` using `textio`
2. Insert a `FRAME_START N` marker when `ddr_axi_addr` drops back near `0x80000000` (framebuffer rewind → new frame starting)
3. Drive `hdmi_ddr_valid <= '0'` (we're not feeding the HDMI encoder), `hdmi_reset_mem_ack <= '1'`, `hdmi_r/g/b <= (others => '0')`

**Why log writes instead of spying on HDMI signals?** The `hdmi_r/g/b` signals in the actual HDMI pipeline are in the TMDS pixel-clock domain (74 MHz) and represent pixels in scan order mixed with HDMI blanking/sync intervals. Reconstructing a frame from them requires full knowledge of 720p timing. Intercepting the raw DDR writes is far simpler: each write is `(address − 0x80000000) / 4 = pixel index`, and the 32-bit value is `0x00RRGGBB`.

---

## Phase 4: Testbench — `vhd/bench/tb_video_dump.vhd`

- Instantiates `PROC` using the same entity declaration as `tb_PROC.vhd`, but with:
  - `FILE_PROG => "mem/invaders_sim.mem"` (the compiled game binary)
  - DDR/FIXED_IO inout ports driven to `'Z'`
- Clock: drive at **50 MHz** (20 ns period). With the `MMCME2_BASE` mock passing through, the processor clock = testbench clock = 50 MHz. This matches the intended hardware frequency.
- Reset: assert for 10 cycles, then release
- Push buttons: hold `push = "000"` (no input) — the game initialises itself in `initialize()` without needing button presses. Button simulation can be added later to make the spaceship move.
- Termination: the testbench just runs; use GHDL's `--stop-time` flag to set simulation duration

**Simulation time budget** (with ENV_SIM and 320×240 display):
- `initialize()` → `clear_screen(0x0)`: 76,800 writes × ~4 cycles each ≈ 307K cycles ≈ 6 ms
- Each game loop iter: timer wait (~780 cycles) + ~7 sprites × 64 × 16 writes ≈ 8,192 write cycles
- 10 game loops ≈ ~90K cycles ≈ 2 ms
- Total for ~10 frames: ≈ 1M cycles = 20 ms simulation time
- GHDL speed on M1: roughly 1–5M cycles/sec for this design complexity → ~0.2–1 second wall-clock time per 1M simulated cycles

---

## Phase 5: GHDL Build Script — `scripts/run_sim.sh`

Compile all VHDL, elaborate, and run. GHDL's `--work` and `-P` (library path) flags handle multi-library compilation:

```bash
#!/bin/bash
set -e
GHDL=ghdl
STD="--std=08"
WD=ghdl_work   # working directory for compiled .cf files

mkdir -p $WD/unisim $WD/xpm $WD/work $WD/sim_out

# 1. Compile Xilinx primitive mocks into named libraries
$GHDL -a $STD --work=unisim --workdir=$WD/unisim vhd/sim/unisim_mock.vhd
$GHDL -a $STD --work=xpm   --workdir=$WD/xpm   vhd/sim/xpm_mock.vhd

# 2. Compile design files into 'work' (in dependency order from PROC.prj)
WFLAGS="$STD --work=work --workdir=$WD/work -P$WD/unisim -P$WD/xpm"
$GHDL -a $WFLAGS vhd/PKG.vhd
$GHDL -a $WFLAGS vhd/CPU_PO.vhd
$GHDL -a $WFLAGS vhd/CPU_CSR.vhd
$GHDL -a $WFLAGS vhd/CPU_CND.vhd
$GHDL -a $WFLAGS vhd/CPU_PC.vhd
$GHDL -a $WFLAGS vhd/CPU.vhd
$GHDL -a $WFLAGS vhd/RAM32.vhd
$GHDL -a $WFLAGS vhd/RAM16DP.vhd
$GHDL -a $WFLAGS vhd/IP_LED.vhd
$GHDL -a $WFLAGS vhd/IP_PIN.vhd
$GHDL -a $WFLAGS vhd/IP_PLIC.vhd
$GHDL -a $WFLAGS vhd/IP_CLINT.vhd
$GHDL -a $WFLAGS vhd/PROC_bus.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_pkg.vhd
$GHDL -a $WFLAGS vhd/hdmi/ControlEncoder.vhd
$GHDL -a $WFLAGS vhd/hdmi/TERC4Encoder.vhd
$GHDL -a $WFLAGS vhd/hdmi/TMDSEncoder.vhd
$GHDL -a $WFLAGS vhd/hdmi/VideoEncoder.vhd
$GHDL -a $WFLAGS vhd/hdmi/VIC_Interpreter.vhd
$GHDL -a $WFLAGS vhd/hdmi/GeneRGB.vhd
$GHDL -a $WFLAGS vhd/hdmi/Debug_Switch_Sel.vhd
$GHDL -a $WFLAGS vhd/hdmi/OutputSERDES.vhd
$GHDL -a $WFLAGS vhd/hdmi/ClockGen.vhd
$GHDL -a $WFLAGS vhd/hdmi/ClockGenApprox.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_PC.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_PO.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_Controller.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_simple.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_AXI_Master.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_AXI.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_AXI_Slave.vhd
$GHDL -a $WFLAGS vhd/hdmi/HDMI_ENV.vhd
$GHDL -a $WFLAGS vhd/axi/PROC_AXI_Master.vhd
$GHDL -a $WFLAGS vhd/axi/PROC_AXI.vhd
$GHDL -a $WFLAGS vhd/sim/PS_Link_sim.vhd    # must come before PROC.vhd
$GHDL -a $WFLAGS vhd/PROC.vhd
$GHDL -a $WFLAGS vhd/bench/tb_video_dump.vhd

# 3. Elaborate
$GHDL -e $STD --work=work --workdir=$WD/work \
      -P$WD/unisim -P$WD/xpm tb_video_dump

# 4. Run (generates sim/vram_writes.txt)
mkdir -p sim
$GHDL -r $STD --work=work --workdir=$WD/work \
      -P$WD/unisim -P$WD/xpm tb_video_dump \
      --stop-time=50ms
```

---

## Phase 6: Python Frame Renderer — `scripts/render_frames.py`

Reads `sim/vram_writes.txt`, reconstructs the framebuffer, writes PNG files.

**Pixel format**: The game stores pixels as `0x00RRGGBB` (e.g., `0x0000FF` = blue spaceship, `0x00FF00` = green alien). Extract: R = `(word >> 16) & 0xFF`, G = `(word >> 8) & 0xFF`, B = `word & 0xFF`.

**Frame detection strategy**: The PS_Link_sim inserts `FRAME_START N` markers. The renderer also creates intermediate "snapshot" PNGs at configurable intervals even without explicit markers (useful if markers fire incorrectly).

```python
# Pseudocode
from PIL import Image

WIDTH, HEIGHT = 320, 240   # must match compile-time defines

framebuffer = [0] * (WIDTH * HEIGHT)
frame_num = 0

with open("sim/vram_writes.txt") as f:
    for line in f:
        if line.startswith("FRAME_START"):
            save_frame(framebuffer, frame_num)
            frame_num += 1
        else:
            addr_s, data_s = line.split()
            pixel_idx = (int(addr_s, 16) - 0x80000000) // 4
            if 0 <= pixel_idx < len(framebuffer):
                framebuffer[pixel_idx] = int(data_s, 16)

save_frame(framebuffer, frame_num)  # final partial frame

def save_frame(fb, n):
    img = Image.new("RGB", (WIDTH, HEIGHT))
    pixels = [( (v>>16)&0xFF, (v>>8)&0xFF, v&0xFF ) for v in fb]
    img.putdata(pixels)
    img.save(f"frames/frame_{n:03d}.png")
```

- [ ] **6.1** Implement and test `scripts/render_frames.py`
- [ ] **6.2** Create `frames/` output directory in the script

---

## Dependency Map / Order of Execution

```
Phase 1 (env)
    └─► Phase 2 (C compile) ──► mem/invaders_sim.mem
    └─► Phase 3 (VHDL mocks) ──► vhd/sim/*.vhd
    └─► Phase 4 (testbench) ──► vhd/bench/tb_video_dump.vhd
Phase 2 + 3 + 4 ──► Phase 5 (run_sim.sh) ──► sim/vram_writes.txt
Phase 5 ──► Phase 6 (render_frames.py) ──► frames/*.png
```

---

## Known Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `.mem` file format mismatch (XPM vs objtomem) | Read `bin/objtomem.awk` before implementing the RAM init function; format is likely plain hex, one 32-bit word per line |
| 64-bit shifts in invaders.c need libgcc (`__lshrdi3`) | Explicitly link `-lgcc` at end of compile command |
| `FRAME_BUFFER_CTRL_MODE_REG = 0x70000000` write is unmapped | PROC_bus silently ignores it (no slave at that address); CPU proceeds normally |
| GHDL simulation speed for large display | Use 320×240 for development; switch to 1280×720 for final run |
| HDMI_simple `ack` never asserted (OSERDESE2 stub) | CPU never waits for HDMI ack; DDR writes are fire-and-forget from CPU perspective |
| `RAM16DP` (XPM_MEMORY_TDPRAM) used by HDMI internals | Can stub the dual-port RAM for HDMI; only RAM32 correctness is critical |
