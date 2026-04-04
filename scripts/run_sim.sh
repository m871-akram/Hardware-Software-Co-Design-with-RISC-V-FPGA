#!/bin/bash
# =============================================================================
# scripts/run_sim.sh
# Compile all VHDL with GHDL, elaborate, and simulate Space Invaders.
# Output: sim/vram_writes.txt  (VRAM writes logged by PS_Link_sim)
#
# Prerequisites:
#   brew install ghdl        (LLVM backend, VHDL-2008)
#   make compile_invaders_sim  (produces mem/invaders_sim.mem)
#
# Usage:
#   bash scripts/run_sim.sh [--stop-time=Xms]
# Default stop time: 50ms simulated (captures ~25 game frames at 50 MHz)
# =============================================================================
set -e

GHDL=${GHDL:-ghdl}
STD="--std=08"
WD=ghdl_work
STOP_TIME=${1:---stop-time=50ms}

# Verify prerequisites
if ! command -v "$GHDL" &>/dev/null; then
    echo "ERROR: ghdl not found. Install with: brew install ghdl"
    exit 1
fi
if [ ! -f mem/invaders_sim.mem ]; then
    echo "ERROR: mem/invaders_sim.mem not found. Run: make compile_invaders_sim"
    exit 1
fi

echo "=== GHDL version ==="
"$GHDL" --version | head -1

# Create output directories
mkdir -p "$WD/unisim" "$WD/xpm" "$WD/work" sim

echo ""
echo "=== Phase 1: Compile Xilinx primitive mocks ==="

"$GHDL" -a $STD --work=unisim --workdir="$WD/unisim" \
    vhd/sim/unisim_mock.vhd

"$GHDL" -a $STD --work=xpm --workdir="$WD/xpm" \
    vhd/sim/xpm_mock.vhd

echo ""
echo "=== Phase 2: Compile design sources ==="

WFLAGS="$STD --work=work --workdir=$WD/work -P$WD/unisim -P$WD/xpm"

# Core
"$GHDL" -a $WFLAGS vhd/PKG.vhd
"$GHDL" -a $WFLAGS vhd/CPU_PO.vhd
"$GHDL" -a $WFLAGS vhd/CPU_CSR.vhd
"$GHDL" -a $WFLAGS vhd/CPU_CND.vhd
"$GHDL" -a $WFLAGS vhd/CPU_PC.vhd
"$GHDL" -a $WFLAGS vhd/CPU.vhd
"$GHDL" -a $WFLAGS vhd/RAM32.vhd
"$GHDL" -a $WFLAGS vhd/RAM16DP.vhd
"$GHDL" -a $WFLAGS vhd/IP_LED.vhd
"$GHDL" -a $WFLAGS vhd/IP_PIN.vhd
"$GHDL" -a $WFLAGS vhd/IP_PLIC.vhd
"$GHDL" -a $WFLAGS vhd/IP_CLINT.vhd
"$GHDL" -a $WFLAGS vhd/IP_Timer.vhd 2>/dev/null || true   # optional
"$GHDL" -a $WFLAGS vhd/PROC_bus.vhd

# HDMI subsystem
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_pkg.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/ControlEncoder.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/TERC4Encoder.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/TMDSEncoder.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/VideoEncoder.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/VIC_Interpreter.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/GeneRGB.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/Debug_Switch_Sel.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/OutputSERDES.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/ClockGen.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/ClockGenApprox.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_PC.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_PO.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_Controller.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_simple.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_AXI_Master.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_AXI.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_AXI_Slave.vhd
"$GHDL" -a $WFLAGS vhd/hdmi/HDMI_ENV.vhd

# AXI
"$GHDL" -a $WFLAGS vhd/axi/PROC_AXI_Master.vhd
"$GHDL" -a $WFLAGS vhd/axi/PROC_AXI.vhd

# PS_Link simulation stub (must precede PROC.vhd)
"$GHDL" -a $WFLAGS vhd/sim/PS_Link_sim.vhd

# Top level and testbench
"$GHDL" -a $WFLAGS vhd/PROC.vhd
"$GHDL" -a $WFLAGS vhd/bench/tb_video_dump.vhd

echo ""
echo "=== Phase 3: Elaborate ==="
"$GHDL" -e $STD --work=work --workdir="$WD/work" \
    -P"$WD/unisim" -P"$WD/xpm" \
    tb_video_dump

echo ""
echo "=== Phase 4: Simulate ($STOP_TIME) ==="
echo "Output: sim/vram_writes.txt"
"$GHDL" -r $STD --work=work --workdir="$WD/work" \
    -P"$WD/unisim" -P"$WD/xpm" tb_video_dump \
    --max-stack-alloc=512 \
    --ieee-asserts=disable \
    $STOP_TIME

echo ""
NWRITES=$(grep -c "^[0-9a-fA-F]" sim/vram_writes.txt 2>/dev/null || echo 0)
NFRAMES=$(grep -c "^FRAME_TICK" sim/vram_writes.txt 2>/dev/null || echo 0)
echo "Done. $NWRITES pixel writes, $NFRAMES frame ticks."
echo "Run: python3 scripts/render_frames.py"
