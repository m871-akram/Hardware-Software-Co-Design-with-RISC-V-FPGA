-- =============================================================================
-- unisim_mock.vhd
-- Simulation stubs for Xilinx Unisim primitives needed by this design.
-- Compile as library 'unisim':
--   ghdl -a --std=08 --work=unisim --workdir=ghdl_work/unisim vhd/sim/unisim_mock.vhd
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Package vcomponents: component declarations (mirrors the real unisim pkg)
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

package vcomponents is

    -- Mixed-Mode Clock Manager
    component MMCME2_BASE is
        generic (
            CLKFBOUT_MULT_F  : real    := 5.0;
            CLKIN1_PERIOD    : real    := 10.0;
            CLKOUT0_DIVIDE_F : real    := 1.0;
            CLKOUT1_DIVIDE   : integer := 1;
            CLKOUT2_DIVIDE   : integer := 1;
            CLKOUT1_PHASE    : real    := 0.0;
            CLKOUT2_PHASE    : real    := 0.0;
            DIVCLK_DIVIDE    : integer := 1;
            REF_JITTER1      : real    := 0.01
        );
        port (
            CLKIN1   : in  std_logic;
            CLKFBIN  : in  std_logic;
            PWRDWN   : in  std_logic;
            RST      : in  std_logic;
            CLKOUT0  : out std_logic;
            CLKOUT1  : out std_logic;
            CLKOUT2  : out std_logic;
            CLKFBOUT : out std_logic;
            LOCKED   : out std_logic
        );
    end component MMCME2_BASE;

    -- Global clock buffer
    component BUFG is
        port (
            I : in  std_logic;
            O : out std_logic
        );
    end component BUFG;

    -- Differential output buffer
    component OBUFDS is
        generic (
            IOSTANDARD : string := "LVDS_25"
        );
        port (
            I  : in  std_logic;
            O  : out std_logic;
            OB : out std_logic
        );
    end component OBUFDS;

    -- Output serializer/deserializer (10-bit DDR, used by HDMI TMDS)
    component OSERDESE2 is
        generic (
            DATA_RATE_OQ   : string  := "DDR";
            DATA_RATE_TQ   : string  := "SDR";
            DATA_WIDTH     : integer := 4;
            SERDES_MODE    : string  := "MASTER";
            TRISTATE_WIDTH : integer := 4
        );
        port (
            CLK       : in  std_logic;
            CLKDIV    : in  std_logic;
            D1        : in  std_logic;
            D2        : in  std_logic;
            D3        : in  std_logic;
            D4        : in  std_logic;
            D5        : in  std_logic;
            D6        : in  std_logic;
            D7        : in  std_logic;
            D8        : in  std_logic;
            T1        : in  std_logic;
            T2        : in  std_logic;
            T3        : in  std_logic;
            T4        : in  std_logic;
            TCE       : in  std_logic;
            OCE       : in  std_logic;
            TBYTEIN   : in  std_logic;
            RST       : in  std_logic;
            SHIFTIN1  : in  std_logic;
            SHIFTIN2  : in  std_logic;
            OQ        : out std_logic;
            OFB       : out std_logic;
            TQ        : out std_logic;
            TFB       : out std_logic;
            SHIFTOUT1 : out std_logic;
            SHIFTOUT2 : out std_logic
        );
    end component OSERDESE2;

end package vcomponents;


-- ---------------------------------------------------------------------------
-- MMCME2_BASE entity+architecture
-- Mock: all clock outputs follow CLKIN1 directly (no division/multiplication).
-- LOCKED asserts '1' after 100 ns, simulating DCM lock time.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity MMCME2_BASE is
    generic (
        CLKFBOUT_MULT_F  : real    := 5.0;
        CLKIN1_PERIOD    : real    := 10.0;
        CLKOUT0_DIVIDE_F : real    := 1.0;
        CLKOUT1_DIVIDE   : integer := 1;
        CLKOUT2_DIVIDE   : integer := 1;
        CLKOUT1_PHASE    : real    := 0.0;
        CLKOUT2_PHASE    : real    := 0.0;
        DIVCLK_DIVIDE    : integer := 1;
        REF_JITTER1      : real    := 0.01
    );
    port (
        CLKIN1   : in  std_logic;
        CLKFBIN  : in  std_logic;
        PWRDWN   : in  std_logic;
        RST      : in  std_logic;
        CLKOUT0  : out std_logic;
        CLKOUT1  : out std_logic;
        CLKOUT2  : out std_logic;
        CLKFBOUT : out std_logic;
        LOCKED   : out std_logic
    );
end entity MMCME2_BASE;

architecture sim of MMCME2_BASE is
begin
    -- Pass the input clock through to all outputs unchanged.
    -- In hardware these would be phase-shifted/divided; in simulation
    -- we just need the CPU to receive a valid clock signal.
    CLKOUT0  <= CLKIN1;
    CLKOUT1  <= CLKIN1;
    CLKOUT2  <= CLKIN1;
    CLKFBOUT <= CLKIN1;

    -- Assert LOCKED after a short simulated lock period.
    -- PROC.vhd holds CPU reset while LOCKED='0', so this
    -- adds a brief startup delay before the processor runs.
    lock_p : process
    begin
        LOCKED <= '0';
        wait for 100 ns;
        LOCKED <= '1';
        wait;
    end process lock_p;
end architecture sim;


-- ---------------------------------------------------------------------------
-- BUFG entity+architecture: simple combinatorial wire
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity BUFG is
    port (
        I : in  std_logic;
        O : out std_logic
    );
end entity BUFG;

architecture sim of BUFG is
begin
    O <= I;
end architecture sim;


-- ---------------------------------------------------------------------------
-- OBUFDS entity+architecture: differential output stub
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity OBUFDS is
    generic (
        IOSTANDARD : string := "LVDS_25"
    );
    port (
        I  : in  std_logic;
        O  : out std_logic;
        OB : out std_logic
    );
end entity OBUFDS;

architecture sim of OBUFDS is
begin
    O  <= I;
    OB <= not I;
end architecture sim;


-- ---------------------------------------------------------------------------
-- OSERDESE2 entity+architecture: TMDS serialiser stub
-- We never need real TMDS output in simulation; just forward D1.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity OSERDESE2 is
    generic (
        DATA_RATE_OQ   : string  := "DDR";
        DATA_RATE_TQ   : string  := "SDR";
        DATA_WIDTH     : integer := 4;
        SERDES_MODE    : string  := "MASTER";
        TRISTATE_WIDTH : integer := 4
    );
    port (
        CLK       : in  std_logic;
        CLKDIV    : in  std_logic;
        D1        : in  std_logic;
        D2        : in  std_logic;
        D3        : in  std_logic;
        D4        : in  std_logic;
        D5        : in  std_logic;
        D6        : in  std_logic;
        D7        : in  std_logic;
        D8        : in  std_logic;
        T1        : in  std_logic;
        T2        : in  std_logic;
        T3        : in  std_logic;
        T4        : in  std_logic;
        TCE       : in  std_logic;
        OCE       : in  std_logic;
        TBYTEIN   : in  std_logic;
        RST       : in  std_logic;
        SHIFTIN1  : in  std_logic;
        SHIFTIN2  : in  std_logic;
        OQ        : out std_logic;
        OFB       : out std_logic;
        TQ        : out std_logic;
        TFB       : out std_logic;
        SHIFTOUT1 : out std_logic;
        SHIFTOUT2 : out std_logic
    );
end entity OSERDESE2;

architecture sim of OSERDESE2 is
begin
    OQ        <= D1;   -- forward first data bit as a stub
    OFB       <= '0';
    TQ        <= '0';
    TFB       <= '0';
    SHIFTOUT1 <= '0';
    SHIFTOUT2 <= '0';
end architecture sim;
