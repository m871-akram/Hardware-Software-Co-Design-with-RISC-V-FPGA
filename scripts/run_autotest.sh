#!/bin/bash
# =============================================================================
# scripts/run_autotest.sh
# Run all RV32I instruction autotests using GHDL (no Vivado required).
# Generates SVG badges in badges/ reflecting each test result.
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
BADGES_DIR="$PROJECT_ROOT/badges"
RESULTS_TMP=$(mktemp /tmp/autotest_results.XXXXXX)
PASSED=0
FAILED=0
TIMEOUT=0
TOTAL=0
ERRORS=""

# ── SVG badge generator ────────────────────────────────────────────────────
generate_badge() {
    local label="$1"   # e.g. "ADD"
    local status="$2"  # "passing" | "failing" | "timeout"
    local outfile="$3"

    local color
    case "$status" in
        passing) color="#4c1" ;;
        failing) color="#e05d44" ;;
        timeout) color="#e09820" ;;
        *)       color="#9f9f9f" ;;
    esac

    local lw=$(( ${#label} * 7 + 10 ))
    local rw=$(( ${#status} * 7 + 10 ))
    local tw=$(( lw + rw ))
    local lm=$(( lw / 2 ))
    local rm=$(( lw + rw / 2 ))

    mkdir -p "$(dirname "$outfile")"
    cat > "$outfile" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${tw}" height="20">
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r"><rect width="${tw}" height="20" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#r)">
    <rect width="${lw}" height="20" fill="#555"/>
    <rect x="${lw}" width="${rw}" height="20" fill="${color}"/>
    <rect width="${tw}" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="${lm}" y="15" fill="#010101" fill-opacity=".3">${label}</text>
    <text x="${lm}" y="14">${label}</text>
    <text x="${rm}" y="15" fill="#010101" fill-opacity=".3">${status}</text>
    <text x="${rm}" y="14">${status}</text>
  </g>
</svg>
SVG
}

generate_timestamp_badge() {
    local ts
    ts=$(date "+%Y-%m-%d %H:%M")
    local label="tested"
    local lw=$(( ${#label} * 7 + 10 ))
    local rw=$(( ${#ts} * 7 + 10 ))
    local tw=$(( lw + rw ))
    local lm=$(( lw / 2 ))
    local rm=$(( lw + rw / 2 ))

    mkdir -p "$BADGES_DIR"
    cat > "$BADGES_DIR/timestamp.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${tw}" height="20">
  <linearGradient id="s" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <clipPath id="r"><rect width="${tw}" height="20" rx="3" fill="#fff"/></clipPath>
  <g clip-path="url(#r)">
    <rect width="${lw}" height="20" fill="#555"/>
    <rect x="${lw}" width="${rw}" height="20" fill="#007ec6"/>
    <rect width="${tw}" height="20" fill="url(#s)"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="${lm}" y="15" fill="#010101" fill-opacity=".3">${label}</text>
    <text x="${lm}" y="14">${label}</text>
    <text x="${rm}" y="15" fill="#010101" fill-opacity=".3">${ts}</text>
    <text x="${rm}" y="14">${ts}</text>
  </g>
</svg>
SVG
}

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
# TESTS array: "badge_name:filename" pairs
TESTS=()

if [ -n "$1" ]; then
    f="program/autotest/$1.s"
    raw_tag=""
    if [ -f "$f" ]; then
        raw_tag=$(grep -i '^\s*#.*TAG\s*=\s*' "$f" 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d '[:space:]')
    fi
    badge=$(echo "${raw_tag:-$1}" | tr '[:lower:]' '[:upper:]')
    TESTS=("${badge}:$1")
else
    while IFS= read -r tag; do
        tag=$(echo "$tag" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$tag" ] && continue
        tag_lower=$(echo "$tag" | tr '[:upper:]' '[:lower:]')
        tag_upper=$(echo "$tag" | tr '[:lower:]' '[:upper:]')
        for f in program/autotest/*.s; do
            fname=$(basename "$f" .s)
            file_tag=$(grep -i '^\s*#.*TAG\s*=\s*' "$f" 2>/dev/null | head -1 \
                | sed 's/.*=\s*//' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            if [ "$file_tag" = "$tag_lower" ]; then
                TESTS+=("${tag_upper}:${fname}")
            fi
        done
    done < program/sequence_tag
fi

echo "=== Running ${#TESTS[@]} tests ==="
echo ""

# ── Step 3: Run each test ─────────────────────────────────────────────────
for entry in "${TESTS[@]}"; do
    badge_name="${entry%%:*}"
    test="${entry##*:}"
    TOTAL=$((TOTAL + 1))

    if ! make -s compile PROG="$test" > /dev/null 2>&1; then
        printf "  %-25s \033[31mCOMPILE ERROR\033[0m\n" "$test"
        FAILED=$((FAILED + 1))
        ERRORS="$ERRORS  $test: COMPILE ERROR\n"
        echo "$badge_name failing" >> "$RESULTS_TMP"
        continue
    fi

    max_cycle=$(cat "$SIM_DIR/test_default.setup" 2>/dev/null | head -1)
    [ -z "$max_cycle" ] && max_cycle=100
    sim_time=$(( max_cycle * 20 ))
    [ "$sim_time" -lt 10000 ] && sim_time=10000

    TB_BIN="$PROJECT_ROOT/tb_autotest"
    rm -f "$SIM_DIR/test_default.res" "$SIM_DIR/test_default.test"
    cd "$SIM_DIR"
    "$TB_BIN" --max-stack-alloc=512 --ieee-asserts=disable \
        --stop-time="${sim_time}ns" > /dev/null 2>&1 || true
    cd "$PROJECT_ROOT"

    if [ -f "$SIM_DIR/test_default.res" ]; then
        result=$(cat "$SIM_DIR/test_default.res" | tr -d '[:space:]')
    else
        result="TIMEOUT"
    fi

    case "$result" in
        PASSED)
            PASSED=$((PASSED + 1))
            printf "  %-25s \033[32mPASSED\033[0m\n" "$test"
            echo "$badge_name passing" >> "$RESULTS_TMP"
            ;;
        TIMEOUT)
            TIMEOUT=$((TIMEOUT + 1))
            printf "  %-25s \033[33mTIMEOUT\033[0m\n" "$test"
            ERRORS="$ERRORS  $test: TIMEOUT\n"
            echo "$badge_name timeout" >> "$RESULTS_TMP"
            ;;
        *)
            FAILED=$((FAILED + 1))
            printf "  %-25s \033[31mFAILED\033[0m\n" "$test"
            ERRORS="$ERRORS  $test: FAILED\n"
            echo "$badge_name failing" >> "$RESULTS_TMP"
            ;;
    esac

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

# ── Step 5: Generate SVG badges ──────────────────────────────────────────
echo ""
echo "=== Generating badges ==="
mkdir -p "$BADGES_DIR"

while IFS=' ' read -r badge_name status; do
    generate_badge "$badge_name" "$status" "$BADGES_DIR/${badge_name}.svg"
done < "$RESULTS_TMP"

# invaders is verified on hardware, not an autotest
generate_badge "invaders" "passing" "$BADGES_DIR/invaders.svg"

generate_timestamp_badge

rm -f "$RESULTS_TMP"
echo "  Badges written to badges/"

[ "$FAILED" -eq 0 ] && [ "$TIMEOUT" -eq 0 ]
