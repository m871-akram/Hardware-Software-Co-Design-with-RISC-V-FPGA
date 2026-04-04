-- =============================================================================
-- tb_video_dump.vhd
-- Testbench for running Space Invaders on the RISC-V processor via GHDL.
-- Instantiates PROC with the invaders_sim.mem binary, drives a 50 MHz clock,
-- and lets PS_Link_sim log all DDR (VRAM) writes to sim/vram_writes.txt.
--
-- Usage (via scripts/run_sim.sh):
--   ghdl -r ... tb_video_dump --stop-time=50ms
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_video_dump is
end entity tb_video_dump;

architecture bench of tb_video_dump is

    component PROC is
        generic (
            FILE_PROG : string  := "../mem/prog.mem";
            mutant    : integer := 0
        );
        port (
            clk    : in  std_logic;
            reset  : in  std_logic;

            switch : in  unsigned(3 downto 0);
            push   : in  unsigned(2 downto 0);
            led    : out unsigned(3 downto 0);

            -- HDMI differential outputs
            channel_n : out std_logic_vector(2 downto 0);
            channel_p : out std_logic_vector(2 downto 0);
            clk_p     : out std_logic;
            clk_n     : out std_logic;
            cec       : in  std_logic;
            hpd       : in  std_logic;
            out_en    : out std_logic;
            scl       : out std_logic;
            sda       : out std_logic;

            -- DDR / FIXED_IO (Zynq PS7)
            DDR_addr          : inout std_logic_vector(14 downto 0);
            DDR_ba            : inout std_logic_vector(2 downto 0);
            DDR_cas_n         : inout std_logic;
            DDR_ck_n          : inout std_logic;
            DDR_ck_p          : inout std_logic;
            DDR_cke           : inout std_logic;
            DDR_cs_n          : inout std_logic;
            DDR_dm            : inout std_logic_vector(3 downto 0);
            DDR_dq            : inout std_logic_vector(31 downto 0);
            DDR_dqs_n         : inout std_logic_vector(3 downto 0);
            DDR_dqs_p         : inout std_logic_vector(3 downto 0);
            DDR_odt           : inout std_logic;
            DDR_ras_n         : inout std_logic;
            DDR_reset_n       : inout std_logic;
            DDR_we_n          : inout std_logic;
            FIXED_IO_ddr_vrn  : inout std_logic;
            FIXED_IO_ddr_vrp  : inout std_logic;
            FIXED_IO_mio      : inout std_logic_vector(53 downto 0);
            FIXED_IO_ps_clk   : inout std_logic;
            FIXED_IO_ps_porb  : inout std_logic;
            FIXED_IO_ps_srstb : inout std_logic
        );
    end component PROC;

    -- Clock: 50 MHz = 20 ns period
    constant CLK_PERIOD : time := 20 ns;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';

    -- Buttons/switches held at 0 (game initialises without input)
    signal switch : unsigned(3 downto 0) := (others => '0');
    signal push   : unsigned(2 downto 0) := (others => '0');
    signal led    : unsigned(3 downto 0);

    -- HDMI outputs (ignored in simulation)
    signal channel_n : std_logic_vector(2 downto 0);
    signal channel_p : std_logic_vector(2 downto 0);
    signal clk_p     : std_logic;
    signal clk_n     : std_logic;
    signal out_en    : std_logic;
    signal scl       : std_logic;
    signal sda       : std_logic;

    -- DDR / FIXED_IO (open / high-Z in testbench)
    signal DDR_addr          : std_logic_vector(14 downto 0) := (others => 'Z');
    signal DDR_ba            : std_logic_vector(2 downto 0)  := (others => 'Z');
    signal DDR_cas_n         : std_logic := 'Z';
    signal DDR_ck_n          : std_logic := 'Z';
    signal DDR_ck_p          : std_logic := 'Z';
    signal DDR_cke           : std_logic := 'Z';
    signal DDR_cs_n          : std_logic := 'Z';
    signal DDR_dm            : std_logic_vector(3 downto 0)  := (others => 'Z');
    signal DDR_dq            : std_logic_vector(31 downto 0) := (others => 'Z');
    signal DDR_dqs_n         : std_logic_vector(3 downto 0)  := (others => 'Z');
    signal DDR_dqs_p         : std_logic_vector(3 downto 0)  := (others => 'Z');
    signal DDR_odt           : std_logic := 'Z';
    signal DDR_ras_n         : std_logic := 'Z';
    signal DDR_reset_n       : std_logic := 'Z';
    signal DDR_we_n          : std_logic := 'Z';
    signal FIXED_IO_ddr_vrn  : std_logic := 'Z';
    signal FIXED_IO_ddr_vrp  : std_logic := 'Z';
    signal FIXED_IO_mio      : std_logic_vector(53 downto 0) := (others => 'Z');
    signal FIXED_IO_ps_clk   : std_logic := 'Z';
    signal FIXED_IO_ps_porb  : std_logic := 'Z';
    signal FIXED_IO_ps_srstb : std_logic := 'Z';

begin

    -- 50 MHz clock generator
    clk_gen : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_gen;

    -- Reset: active for 10 clock cycles, then release
    reset_gen : process
    begin
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait;
    end process reset_gen;

    -- Design under test
    DUT : PROC
        generic map (
            FILE_PROG => "mem/invaders_sim.mem",
            mutant    => 0
        )
        port map (
            clk    => clk,
            reset  => reset,
            switch => switch,
            push   => push,
            led    => led,

            channel_n => channel_n,
            channel_p => channel_p,
            clk_p     => clk_p,
            clk_n     => clk_n,
            cec       => '0',
            hpd       => '0',
            out_en    => out_en,
            scl       => scl,
            sda       => sda,

            DDR_addr          => DDR_addr,
            DDR_ba            => DDR_ba,
            DDR_cas_n         => DDR_cas_n,
            DDR_ck_n          => DDR_ck_n,
            DDR_ck_p          => DDR_ck_p,
            DDR_cke           => DDR_cke,
            DDR_cs_n          => DDR_cs_n,
            DDR_dm            => DDR_dm,
            DDR_dq            => DDR_dq,
            DDR_dqs_n         => DDR_dqs_n,
            DDR_dqs_p         => DDR_dqs_p,
            DDR_odt           => DDR_odt,
            DDR_ras_n         => DDR_ras_n,
            DDR_reset_n       => DDR_reset_n,
            DDR_we_n          => DDR_we_n,
            FIXED_IO_ddr_vrn  => FIXED_IO_ddr_vrn,
            FIXED_IO_ddr_vrp  => FIXED_IO_ddr_vrp,
            FIXED_IO_mio      => FIXED_IO_mio,
            FIXED_IO_ps_clk   => FIXED_IO_ps_clk,
            FIXED_IO_ps_porb  => FIXED_IO_ps_porb,
            FIXED_IO_ps_srstb => FIXED_IO_ps_srstb
        );

end architecture bench;
