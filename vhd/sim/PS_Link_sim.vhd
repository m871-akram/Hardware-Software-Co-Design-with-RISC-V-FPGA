-- =============================================================================
-- PS_Link_sim.vhd
-- Simulation stub for the Xilinx Zynq Processing System (PS7) wrapper.
-- Compiled into library 'work' (before PROC.vhd in the compile order).
--
-- In hardware, PS_Link manages DDR3 access and feeds pixel data to HDMI.
-- In simulation we:
--   1. Log every DDR write to sim/vram_writes.txt: "ADDR DATA\n" (hex)
--   2. Insert a FRAME_START N marker when the write address wraps back to
--      the framebuffer base (0x80000000), indicating a new frame is beginning.
--   3. Drive hdmi_r/g/b = 0, hdmi_ddr_valid = '0', hdmi_reset_mem_ack = '1'
--      so PROC does not stall waiting for video handshakes.
--
-- Port interface MUST exactly match component PS_Link declared in PROC.vhd.
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity PS_Link is
    port (
        -- Zynq DDR / FIXED_IO (left floating by testbench – inout open)
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
        FIXED_IO_ps_srstb : inout std_logic;

        -- Pixel RGB output to HDMI encoder (driven to 0 in sim)
        hdmi_r : out std_logic_vector(7 downto 0);
        hdmi_g : out std_logic_vector(7 downto 0);
        hdmi_b : out std_logic_vector(7 downto 0);

        -- AXI / handshake
        axi_clk           : in  std_logic;
        axi_rst           : in  std_logic;
        hdmi_ddr_valid    : out std_logic;
        hdmi_ddr_ack      : in  std_logic;
        hdmi_pixel_clk    : in  std_logic;
        hdmi_reset_mem    : in  std_logic;
        hdmi_reset_mem_ack: out std_logic;

        -- Write port from CPU bus
        ddr_axi_addr : in  std_logic_vector(31 downto 0);
        ddr_din      : in  std_logic_vector(31 downto 0);
        ddr_we       : in  std_logic
    );
end entity PS_Link;

architecture sim of PS_Link is

    -- Time-based frame tick: emit FRAME_TICK every TICK_INTERVAL.
    -- The game loop runs at ~4ms per iteration (timer_wait with TIMER_FREQ=50000, period=4).
    -- We emit a tick every 4ms to capture each game frame.
    constant TICK_INTERVAL : time := 4 ms;

    signal frame_count : integer := 0;

begin

    -- Drive outputs that PROC depends on
    hdmi_r            <= (others => '0');
    hdmi_g            <= (others => '0');
    hdmi_b            <= (others => '0');
    hdmi_ddr_valid    <= '0';
    hdmi_reset_mem_ack <= '1';

    -- DDR / FIXED_IO tristate pins: high-Z in simulation
    DDR_addr    <= (others => 'Z');
    DDR_ba      <= (others => 'Z');
    DDR_cas_n   <= 'Z';
    DDR_ck_n    <= 'Z';
    DDR_ck_p    <= 'Z';
    DDR_cke     <= 'Z';
    DDR_cs_n    <= 'Z';
    DDR_dm      <= (others => 'Z');
    DDR_dq      <= (others => 'Z');
    DDR_dqs_n   <= (others => 'Z');
    DDR_dqs_p   <= (others => 'Z');
    DDR_odt     <= 'Z';
    DDR_ras_n   <= 'Z';
    DDR_reset_n <= 'Z';
    DDR_we_n    <= 'Z';
    FIXED_IO_ddr_vrn  <= 'Z';
    FIXED_IO_ddr_vrp  <= 'Z';
    FIXED_IO_mio      <= (others => 'Z');
    FIXED_IO_ps_clk   <= 'Z';
    FIXED_IO_ps_porb  <= 'Z';
    FIXED_IO_ps_srstb <= 'Z';

    -- DDR write logger with time-based frame ticks
    log_p : process(axi_clk)
        file     f         : text;
        variable fst       : file_open_status;
        variable l         : line;
        variable addr      : unsigned(31 downto 0);
        variable data      : unsigned(31 downto 0);
        variable opened    : boolean := false;
        variable next_tick : time    := TICK_INTERVAL;
        variable tick_num  : integer := 0;
    begin
        if rising_edge(axi_clk) then
            -- Open file on first clock edge
            if not opened then
                file_open(fst, f, "sim/vram_writes.txt", write_mode);
                opened := true;
            end if;

            -- Emit frame tick when simulation time crosses a tick boundary
            while now >= next_tick loop
                write(l, string'("FRAME_TICK "));
                write(l, tick_num);
                writeline(f, l);
                tick_num  := tick_num + 1;
                next_tick := next_tick + TICK_INTERVAL;
            end loop;

            -- Log DDR writes
            if ddr_we = '1' then
                addr := unsigned(ddr_axi_addr);
                data := unsigned(ddr_din);

                hwrite(l, std_logic_vector(addr));
                write(l, ' ');
                hwrite(l, std_logic_vector(data));
                writeline(f, l);
            end if;
        end if;
    end process log_p;

end architecture sim;
