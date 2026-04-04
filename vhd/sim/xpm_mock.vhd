-- =============================================================================
-- xpm_mock.vhd
-- Simulation stubs for Xilinx XPM (Xilinx Parameterized Macro) memories.
-- Compile as library 'xpm':
--   ghdl -a --std=08 --work=xpm --workdir=ghdl_work/xpm vhd/sim/xpm_mock.vhd
--
-- Implements:
--   XPM_MEMORY_SPRAM  — single-port RAM (used by RAM32.vhd for program memory)
--   XPM_MEMORY_TDPRAM — true dual-port RAM (used by RAM16DP.vhd for HDMI buffers)
--
-- .mem file format (produced by bin/objtomem.awk):
--   @XXXXXXXX        — set write index to word address XXXXXXXX (hex)
--   YYYYYYYY         — store 32-bit hex word at current index, then increment
--   FFFFFFFF         — section terminator (skip, do not store)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Package vcomponents: component declarations (mirrors the real xpm pkg)
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package vcomponents is

    -- Single-Port RAM
    -- Port widths are parameterised by the component's own generics so that
    -- GHDL can resolve constraints at component-instantiation time.
    component XPM_MEMORY_SPRAM is
        generic (
            MEMORY_SIZE         : integer := 2048;
            MEMORY_PRIMITIVE    : string  := "auto";
            MEMORY_INIT_FILE    : string  := "none";
            MEMORY_OPTIMIZATION : string  := "true";
            USE_MEM_INIT        : integer := 1;
            ECC_MODE            : string  := "no_ecc";
            ADDR_WIDTH_A        : integer := 6;
            BYTE_WRITE_WIDTH_A  : integer := 32;
            WRITE_DATA_WIDTH_A  : integer := 32;
            READ_DATA_WIDTH_A   : integer := 32;
            WRITE_MODE_A        : string  := "read_first";
            READ_LATENCY_A      : integer := 2
        );
        port (
            clkA           : in  std_logic;
            rstA           : in  std_logic;
            sleep          : in  std_logic;
            addrA          : in  std_logic_vector(ADDR_WIDTH_A-1 downto 0);
            enA            : in  std_logic;
            weA            : in  std_logic_vector(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1 downto 0);
            dinA           : in  std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
            doutA          : out std_logic_vector(READ_DATA_WIDTH_A-1 downto 0);
            regceA         : in  std_logic;
            sbiterrA       : out std_logic;
            dbiterrA       : out std_logic;
            injectsbiterrA : in  std_logic;
            injectdbiterrA : in  std_logic
        );
    end component XPM_MEMORY_SPRAM;

    -- True Dual-Port RAM
    component XPM_MEMORY_TDPRAM is
        generic (
            MEMORY_SIZE         : integer := 2048;
            MEMORY_PRIMITIVE    : string  := "auto";
            MEMORY_INIT_FILE    : string  := "none";
            MEMORY_OPTIMIZATION : string  := "true";
            USE_MEM_INIT        : integer := 1;
            ECC_MODE            : string  := "no_ecc";
            ADDR_WIDTH_A        : integer := 6;
            BYTE_WRITE_WIDTH_A  : integer := 16;
            WRITE_DATA_WIDTH_A  : integer := 16;
            READ_DATA_WIDTH_A   : integer := 16;
            WRITE_MODE_A        : string  := "read_first";
            READ_LATENCY_A      : integer := 2;
            ADDR_WIDTH_B        : integer := 6;
            BYTE_WRITE_WIDTH_B  : integer := 16;
            WRITE_DATA_WIDTH_B  : integer := 16;
            READ_DATA_WIDTH_B   : integer := 16;
            WRITE_MODE_B        : string  := "read_first";
            READ_LATENCY_B      : integer := 2
        );
        port (
            clkA           : in  std_logic;
            rstA           : in  std_logic;
            clkB           : in  std_logic;
            rstB           : in  std_logic;
            sleep          : in  std_logic;
            addrA          : in  std_logic_vector(ADDR_WIDTH_A-1 downto 0);
            enA            : in  std_logic;
            weA            : in  std_logic_vector(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1 downto 0);
            dinA           : in  std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
            doutA          : out std_logic_vector(READ_DATA_WIDTH_A-1 downto 0);
            regceA         : in  std_logic;
            sbiterrA       : out std_logic;
            dbiterrA       : out std_logic;
            injectsbiterrA : in  std_logic;
            injectdbiterrA : in  std_logic;
            addrB          : in  std_logic_vector(ADDR_WIDTH_B-1 downto 0);
            enB            : in  std_logic;
            weB            : in  std_logic_vector(WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-1 downto 0);
            dinB           : in  std_logic_vector(WRITE_DATA_WIDTH_B-1 downto 0);
            doutB          : out std_logic_vector(READ_DATA_WIDTH_B-1 downto 0);
            regceB         : in  std_logic;
            sbiterrB       : out std_logic;
            dbiterrB       : out std_logic;
            injectsbiterrB : in  std_logic;
            injectdbiterrB : in  std_logic
        );
    end component XPM_MEMORY_TDPRAM;

end package vcomponents;


-- ---------------------------------------------------------------------------
-- XPM_MEMORY_SPRAM entity+architecture
-- Behavioral single-port RAM with:
--   - File initialisation from .mem (sparse, @addr / hex-word format)
--   - 1-cycle registered read output (READ_LATENCY_A = 1)
--   - Per-byte write enables (BYTE_WRITE_WIDTH_A = 8)
--   - read_first semantics (output is pre-write value on read+write collision)
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity XPM_MEMORY_SPRAM is
    generic (
        MEMORY_SIZE         : integer := 2048;
        MEMORY_PRIMITIVE    : string  := "auto";
        MEMORY_INIT_FILE    : string  := "none";
        MEMORY_OPTIMIZATION : string  := "true";
        USE_MEM_INIT        : integer := 1;
        ECC_MODE            : string  := "no_ecc";
        ADDR_WIDTH_A        : integer := 6;
        BYTE_WRITE_WIDTH_A  : integer := 32;
        WRITE_DATA_WIDTH_A  : integer := 32;
        READ_DATA_WIDTH_A   : integer := 32;
        WRITE_MODE_A        : string  := "read_first";
        READ_LATENCY_A      : integer := 2
    );
    port (
        clkA           : in  std_logic;
        rstA           : in  std_logic;
        sleep          : in  std_logic;
        addrA          : in  std_logic_vector(ADDR_WIDTH_A-1 downto 0);
        enA            : in  std_logic;
        weA            : in  std_logic_vector(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1 downto 0);
        dinA           : in  std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
        doutA          : out std_logic_vector(READ_DATA_WIDTH_A-1 downto 0);
        regceA         : in  std_logic;
        sbiterrA       : out std_logic;
        dbiterrA       : out std_logic;
        injectsbiterrA : in  std_logic;
        injectdbiterrA : in  std_logic
    );
end entity XPM_MEMORY_SPRAM;

architecture sim of XPM_MEMORY_SPRAM is

    constant DEPTH   : integer := MEMORY_SIZE / WRITE_DATA_WIDTH_A;
    constant N_BYTES : integer := WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);

    -- -------------------------------------------------------------------------
    -- Load memory contents from a .mem file (produced by bin/objtomem.awk).
    -- Uses hread() to parse hex directly into std_logic_vector, avoiding
    -- integer overflow for values >= 0x80000000.
    -- Requires --max-stack-alloc=512 at GHDL elaboration (the local mem_v
    -- array is ~256 KB in GHDL's internal std_logic representation).
    -- -------------------------------------------------------------------------
    impure function load_mem(fname : string) return mem_t is
        use std.textio.all;
        use ieee.std_logic_textio.all;
        variable mem_v    : mem_t := (others => (others => '0'));
        file     f        : text;
        variable l        : line;
        variable l_copy   : line;
        variable st       : file_open_status;
        variable cur_idx  : integer := 0;
        variable addr_slv : std_logic_vector(31 downto 0);
        variable data_slv : std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
        variable ch       : character;
        variable good     : boolean;
    begin
        if fname = "none" or fname = "" or USE_MEM_INIT = 0 then
            return mem_v;
        end if;

        file_open(st, f, fname, read_mode);
        if st /= open_ok then
            report "XPM_MEMORY_SPRAM: cannot open " & fname severity warning;
            return mem_v;
        end if;

        while not endfile(f) loop
            readline(f, l);
            next when l'length = 0;

            read(l, ch, good);
            next when not good;

            if ch = '@' then
                hread(l, addr_slv, good);
                if good then
                    cur_idx := to_integer(unsigned(addr_slv));
                end if;
            else
                -- Reconstruct the line (we consumed first char)
                write(l_copy, ch);
                while l'length > 0 loop
                    read(l, ch, good);
                    exit when not good;
                    write(l_copy, ch);
                end loop;
                hread(l_copy, data_slv, good);
                if good then
                    if cur_idx >= 0 and cur_idx < DEPTH then
                        mem_v(cur_idx) := data_slv;
                    end if;
                    cur_idx := cur_idx + 1;
                end if;
            end if;
        end loop;

        file_close(f);
        return mem_v;
    end function;

    signal mem  : mem_t := load_mem(MEMORY_INIT_FILE);
    signal dout : std_logic_vector(READ_DATA_WIDTH_A-1 downto 0) := (others => '0');

begin

    sbiterrA <= '0';
    dbiterrA <= '0';
    doutA    <= dout;

    -- -------------------------------------------------------------------------
    -- Clocked read/write process (read_first, 1-cycle latency).
    -- This is the ONLY process that drives mem, avoiding multi-driver issues.
    -- -------------------------------------------------------------------------
    rw_p : process(clkA)
        variable idx : integer;
    begin
        if rising_edge(clkA) then
            if enA = '1' then
                idx := to_integer(unsigned(addrA));
                -- read_first: latch OLD value before applying any write this cycle
                dout <= mem(idx);
                for b in 0 to N_BYTES-1 loop
                    if weA(b) = '1' then
                        mem(idx)(b * BYTE_WRITE_WIDTH_A + BYTE_WRITE_WIDTH_A - 1
                                 downto b * BYTE_WRITE_WIDTH_A)
                            <= dinA(b * BYTE_WRITE_WIDTH_A + BYTE_WRITE_WIDTH_A - 1
                                    downto b * BYTE_WRITE_WIDTH_A);
                    end if;
                end loop;
            end if;
        end if;
    end process rw_p;

end architecture sim;


-- ---------------------------------------------------------------------------
-- XPM_MEMORY_TDPRAM entity+architecture
-- Behavioural true dual-port RAM.
-- Used by RAM16DP.vhd for HDMI internal buffers; no file init needed.
-- Both ports are independent: read_first, 1-cycle latency.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity XPM_MEMORY_TDPRAM is
    generic (
        MEMORY_SIZE         : integer := 2048;
        MEMORY_PRIMITIVE    : string  := "auto";
        MEMORY_INIT_FILE    : string  := "none";
        MEMORY_OPTIMIZATION : string  := "true";
        USE_MEM_INIT        : integer := 1;
        ECC_MODE            : string  := "no_ecc";
        ADDR_WIDTH_A        : integer := 6;
        BYTE_WRITE_WIDTH_A  : integer := 16;
        WRITE_DATA_WIDTH_A  : integer := 16;
        READ_DATA_WIDTH_A   : integer := 16;
        WRITE_MODE_A        : string  := "read_first";
        READ_LATENCY_A      : integer := 1;
        ADDR_WIDTH_B        : integer := 6;
        BYTE_WRITE_WIDTH_B  : integer := 16;
        WRITE_DATA_WIDTH_B  : integer := 16;
        READ_DATA_WIDTH_B   : integer := 16;
        WRITE_MODE_B        : string  := "read_first";
        READ_LATENCY_B      : integer := 1
    );
    port (
        clkA           : in  std_logic;
        rstA           : in  std_logic;
        clkB           : in  std_logic;
        rstB           : in  std_logic;
        sleep          : in  std_logic;
        addrA          : in  std_logic_vector(ADDR_WIDTH_A-1 downto 0);
        enA            : in  std_logic;
        weA            : in  std_logic_vector(WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-1 downto 0);
        dinA           : in  std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
        doutA          : out std_logic_vector(READ_DATA_WIDTH_A-1 downto 0);
        regceA         : in  std_logic;
        sbiterrA       : out std_logic;
        dbiterrA       : out std_logic;
        injectsbiterrA : in  std_logic;
        injectdbiterrA : in  std_logic;
        addrB          : in  std_logic_vector(ADDR_WIDTH_B-1 downto 0);
        enB            : in  std_logic;
        weB            : in  std_logic_vector(WRITE_DATA_WIDTH_B/BYTE_WRITE_WIDTH_B-1 downto 0);
        dinB           : in  std_logic_vector(WRITE_DATA_WIDTH_B-1 downto 0);
        doutB          : out std_logic_vector(READ_DATA_WIDTH_B-1 downto 0);
        regceB         : in  std_logic;
        sbiterrB       : out std_logic;
        dbiterrB       : out std_logic;
        injectsbiterrB : in  std_logic;
        injectdbiterrB : in  std_logic
    );
end entity XPM_MEMORY_TDPRAM;

architecture sim of XPM_MEMORY_TDPRAM is

    constant DEPTH_A   : integer := MEMORY_SIZE / WRITE_DATA_WIDTH_A;
    constant N_BYTES_A : integer := WRITE_DATA_WIDTH_A / BYTE_WRITE_WIDTH_A;
    constant N_BYTES_B : integer := WRITE_DATA_WIDTH_B / BYTE_WRITE_WIDTH_B;

    -- Shared memory array (port A word width)
    type mem_t is array (0 to DEPTH_A-1) of std_logic_vector(WRITE_DATA_WIDTH_A-1 downto 0);
    signal mem  : mem_t := (others => (others => '0'));

    signal doutA_r : std_logic_vector(READ_DATA_WIDTH_A-1 downto 0) := (others => '0');
    signal doutB_r : std_logic_vector(READ_DATA_WIDTH_B-1 downto 0) := (others => '0');

begin

    sbiterrA <= '0';
    dbiterrA <= '0';
    sbiterrB <= '0';
    dbiterrB <= '0';
    doutA    <= doutA_r;
    doutB    <= doutB_r;

    -- Port A
    process(clkA)
        variable idx : integer;
    begin
        if rising_edge(clkA) then
            if enA = '1' then
                idx := to_integer(unsigned(addrA));
                doutA_r <= mem(idx);
                for b in 0 to N_BYTES_A-1 loop
                    if weA(b) = '1' then
                        mem(idx)(b * BYTE_WRITE_WIDTH_A + BYTE_WRITE_WIDTH_A - 1
                                 downto b * BYTE_WRITE_WIDTH_A)
                            <= dinA(b * BYTE_WRITE_WIDTH_A + BYTE_WRITE_WIDTH_A - 1
                                    downto b * BYTE_WRITE_WIDTH_A);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Port B
    process(clkB)
        variable idx : integer;
    begin
        if rising_edge(clkB) then
            if enB = '1' then
                idx := to_integer(unsigned(addrB));
                doutB_r <= mem(idx);
                for b in 0 to N_BYTES_B-1 loop
                    if weB(b) = '1' then
                        mem(idx)(b * BYTE_WRITE_WIDTH_B + BYTE_WRITE_WIDTH_B - 1
                                 downto b * BYTE_WRITE_WIDTH_B)
                            <= dinB(b * BYTE_WRITE_WIDTH_B + BYTE_WRITE_WIDTH_B - 1
                                    downto b * BYTE_WRITE_WIDTH_B);
                    end if;
                end loop;
            end if;
        end if;
    end process;

end architecture sim;
