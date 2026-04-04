#!/bin/bash
# =============================================================================
# scripts/run_autotest.sh
# Run all RV32I instruction autotests using GHDL (no Vivado required).
#
# Usage:
#   bash scripts/run_autotest.sh          # run all tests from sequence_tag
#   bash scripts/run_autotest.sh add      # run single test
# =============================================================================
set -e

GHDL=${GHDL:-ghdl}
STD="--std=08"
WD=$(pwd)/ghdl_work
PROJECT_ROOT=$(pwd)
TMP_DIR="/tmp/$(whoami)/.CEPcache"
SIM_DIR="$TMP_DIR/sim"
PASSED=0
FAILED=0
TIMEOUT=0
TOTAL=0
ERRORS=""

# ── Step 0: Verify prerequisites ──────────────────────────────────────────
if ! command -v "$GHDL" &>/dev/null; then
    echo "ERROR: ghdl not found. Install with: brew install ghdl"
    exit 1
fi

# ── Step 1: Compile VHDL design (once) ────────────────────────────────────
echo "=== Compiling VHDL design ==="
mkdir -p "$WD/unisim" "$WD/xpm" "$WD/work"

"$GHDL" -a $STD --work=unisim --workdir="$WD/unisim" vhd/sim/unisim_mock.vhd
"$GHDL" -a $STD --work=xpm    --workdir="$WD/xpm"    vhd/sim/xpm_mock.vhd

WFLAGS="$STD --work=work --workdir=$WD/work -P$WD/unisim -P$WD/xpm"

"$GHDL" -a $WFLAGS vhd/PKG.vhd
"$GHDL" -a $WFLAGS vhd/bench/txt_util.vhd
"$GHDL" -a $WFLAGS vhd/CPU_PO.vhd
"$GHDL" -a $WFLAGS vhd/CPU_CSR.vhd
"$GHDL" -a $WFLAGS vhd/CPU_CND.vhd
"$GHDL" -a $WFLAGS vhd/CPU_PC.vhd
"$GHDL" -a $WFLAGS vhd/CPU.vhd
"$GHDL" -a $WFLAGS vhd/RAM32.vhd
"$GHDL" -a $WFLAGS vhd/IP_ITPush.vhd
"$GHDL" -a $WFLAGS vhd/IP_PLIC.vhd
"$GHDL" -a $WFLAGS vhd/IP_CLINT.vhd
"$GHDL" -a $WFLAGS vhd/PROC_bus.vhd
"$GHDL" -a $WFLAGS vhd/bench/tb_autotest.vhd

"$GHDL" -e $STD --work=work --workdir="$WD/work" \
    -P"$WD/unisim" -P"$WD/xpm" tb_autotest

echo ""

# ── Step 2: Build test list ───────────────────────────────────────────────
if [ -n "$1" ]; then
    TESTS=("$1")
else
    TESTS=()
    while IFS= read -r tag; do
        tag=$(echo "$tag" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$tag" ] && continue
        tag_lower=$(echo "$tag" | tr '[:upper:]' '[:lower:]')
        for f in program/autotest/*.s; do
            fname=$(basename "$f" .s)
            file_tag=$(grep -i '^\s*#.*TAG\s*=\s*' "$f" 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [ "$file_tag" = "$tag_lower" ]; then
                TESTS+=("$fname")
            fi
        done
    done < program/sequence_tag
fi

echo "=== Running ${#TESTS[@]} tests ==="
echo ""

# ── Step 3: Run each test ─────────────────────────────────────────────────
for test in "${TESTS[@]}"; do
    TOTAL=$((TOTAL + 1))

    # Use existing Makefile to compile test and set up sim directory
    if ! make -s compile PROG="$test" > /dev/null 2>&1; then
        printf "  %-25s \033[31mCOMPILE ERROR\033[0m\n" "$test"
        FAILED=$((FAILED + 1))
        ERRORS="$ERRORS  $test: COMPILE ERROR\n"
        continue
    fi

    # Parse max_cycle for stop-time
    max_cycle=$(cat "$SIM_DIR/test_default.setup" 2>/dev/null | head -1)
    [ -z "$max_cycle" ] && max_cycle=100
    sim_time=$(( max_cycle * 20 ))  # 10ns period, margin x2
    [ "$sim_time" -lt 10000 ] && sim_time=10000

    # Run tb_autotest from sim directory (it reads test_default.* from CWD)
    TB_BIN="$PROJECT_ROOT/tb_autotest"
    rm -f "$SIM_DIR/test_default.res" "$SIM_DIR/test_default.test"
    cd "$SIM_DIR"
    "$TB_BIN" --max-stack-alloc=512 --ieee-asserts=disable \
        --stop-time="${sim_time}ns" > /dev/null 2>&1 || true
    cd "$PROJECT_ROOT"

    # Check result
    if [ -f "$SIM_DIR/test_default.res" ]; then
        result=$(cat "$SIM_DIR/test_default.res" | tr -d '[:space:]')
    else
        result="TIMEOUT"
    fi

    case "$result" in
        PASSED)
            PASSED=$((PASSED + 1))
            printf "  %-25s \033[32mPASSED\033[0m\n" "$test"
            ;;
        TIMEOUT)
            TIMEOUT=$((TIMEOUT + 1))
            printf "  %-25s \033[33mTIMEOUT\033[0m\n" "$test"
            ERRORS="$ERRORS  $test: TIMEOUT\n"
            ;;
        *)
            FAILED=$((FAILED + 1))
            printf "  %-25s \033[31mFAILED\033[0m\n" "$test"
            ERRORS="$ERRORS  $test: FAILED\n"
            ;;
    esac

    # Save per-test result
    mkdir -p "$SIM_DIR/$test"
    cp -f "$SIM_DIR/test_default.res" "$SIM_DIR/$test/" 2>/dev/null || true
    cp -f "$SIM_DIR/test_default.test" "$SIM_DIR/$test/" 2>/dev/null || true
done

# ── Step 4: Summary ──────────────────────────────────────────────────────
echo ""
echo "==========================================="
printf "  Total: %d   " "$TOTAL"
printf "\033[32mPassed: %d\033[0m   " "$PASSED"
printf "\033[31mFailed: %d\033[0m   " "$FAILED"
printf "\033[33mTimeout: %d\033[0m\n" "$TIMEOUT"
echo "==========================================="

if [ -n "$ERRORS" ]; then
    echo ""
    echo "Failures:"
    echo -e "$ERRORS"
fi

[ "$FAILED" -eq 0 ] && [ "$TIMEOUT" -eq 0 ]
