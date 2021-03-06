-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-------------------------------------------------------------------------------
-- This file is part of the Queens@TUD solver suite
-- for enumerating and counting the solutions of an N-Queens Puzzle.
--
-- Copyright (C) 2008-2015
--      Thomas B. Preusser <thomas.preusser@utexas.edu>
-------------------------------------------------------------------------------
-- This design is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this design.  If not, see <http://www.gnu.org/licenses/>.
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;

entity enframe is
  generic (
    SENTINEL : std_logic_vector(7 downto 0)  -- Start Byte
  );
  port (
    clk : in std_logic;
    rst : in std_logic;

    idat : in  std_logic_vector(7 downto 0);
    ieof : in  std_logic;
    ivld : in  std_logic;
    igot : out std_logic;

    tx_ful : in  std_logic;
    tx_put : out std_logic;
    tx_dat : out std_logic_vector(7 downto 0)
  );
end enframe;


library IEEE;
use IEEE.numeric_std.all;

architecture rtl of enframe is
  -- CRC Table for 0x1D5 (CRC-8)
  type tFCS is array(0 to 255) of std_logic_vector(7 downto 0);
  constant FCS : tFCS := (
    x"00", x"D5", x"7F", x"AA", x"FE", x"2B", x"81", x"54",
    x"29", x"FC", x"56", x"83", x"D7", x"02", x"A8", x"7D",
    x"52", x"87", x"2D", x"F8", x"AC", x"79", x"D3", x"06",
    x"7B", x"AE", x"04", x"D1", x"85", x"50", x"FA", x"2F",
    x"A4", x"71", x"DB", x"0E", x"5A", x"8F", x"25", x"F0",
    x"8D", x"58", x"F2", x"27", x"73", x"A6", x"0C", x"D9",
    x"F6", x"23", x"89", x"5C", x"08", x"DD", x"77", x"A2",
    x"DF", x"0A", x"A0", x"75", x"21", x"F4", x"5E", x"8B",
    x"9D", x"48", x"E2", x"37", x"63", x"B6", x"1C", x"C9",
    x"B4", x"61", x"CB", x"1E", x"4A", x"9F", x"35", x"E0",
    x"CF", x"1A", x"B0", x"65", x"31", x"E4", x"4E", x"9B",
    x"E6", x"33", x"99", x"4C", x"18", x"CD", x"67", x"B2",
    x"39", x"EC", x"46", x"93", x"C7", x"12", x"B8", x"6D",
    x"10", x"C5", x"6F", x"BA", x"EE", x"3B", x"91", x"44",
    x"6B", x"BE", x"14", x"C1", x"95", x"40", x"EA", x"3F",
    x"42", x"97", x"3D", x"E8", x"BC", x"69", x"C3", x"16",
    x"EF", x"3A", x"90", x"45", x"11", x"C4", x"6E", x"BB",
    x"C6", x"13", x"B9", x"6C", x"38", x"ED", x"47", x"92",
    x"BD", x"68", x"C2", x"17", x"43", x"96", x"3C", x"E9",
    x"94", x"41", x"EB", x"3E", x"6A", x"BF", x"15", x"C0",
    x"4B", x"9E", x"34", x"E1", x"B5", x"60", x"CA", x"1F",
    x"62", x"B7", x"1D", x"C8", x"9C", x"49", x"E3", x"36",
    x"19", x"CC", x"66", x"B3", x"E7", x"32", x"98", x"4D",
    x"30", x"E5", x"4F", x"9A", x"CE", x"1B", x"B1", x"64",
    x"72", x"A7", x"0D", x"D8", x"8C", x"59", x"F3", x"26",
    x"5B", x"8E", x"24", x"F1", x"A5", x"70", x"DA", x"0F",
    x"20", x"F5", x"5F", x"8A", x"DE", x"0B", x"A1", x"74",
    x"09", x"DC", x"76", x"A3", x"F7", x"22", x"88", x"5D",
    x"D6", x"03", x"A9", x"7C", x"28", x"FD", x"57", x"82",
    x"FF", x"2A", x"80", x"55", x"01", x"D4", x"7E", x"AB",
    x"84", x"51", x"FB", x"2E", x"7A", x"AF", x"05", x"D0",
    x"AD", x"78", x"D2", x"07", x"53", x"86", x"2C", x"F9"
  );

  -- State Machine
  type tState is (Idle, Transmit, WriteCRC);
  signal State     : tState := Idle;
  signal NextState : tState;

  signal CRC       : std_logic_vector(7 downto 0) := (others => '-');
  signal InitCRC   : std_logic;
  signal UpdateCRC : std_logic;

begin

  -- State
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        State <= Idle;
        CRC   <= (others => '-');
      else
        State <= NextState;

        if InitCRC = '1' then
          CRC <= FCS(255);
        elsif UpdateCRC = '1' then
          CRC <= FCS(to_integer(unsigned(CRC xor idat)));
        end if;
      end if;
    end if;
  end process;

  process(State, tx_ful, ivld, ieof, idat, CRC)
  begin
    NextState <= State;

    InitCRC   <= '0';
    UpdateCRC <= '0';

    tx_dat <= (others => '-');
    tx_put <= '0';

    igot <= '0';

    if tx_ful = '0' then
      case State is
        when Idle =>
          if ivld = '1' then
            InitCRC   <= '1';
            tx_dat    <= SENTINEL;
            tx_put    <= '1';
            NextState <= Transmit;
          end if;

        when Transmit =>
          if ivld = '1' then
            UpdateCRC <= '1';
            tx_dat    <= idat;
            tx_put    <= '1';
            igot      <= '1';
            if ieof = '1' then
              NextState <= WriteCRC;
            end if;
          end if;

        when WriteCRC =>
          tx_dat    <= CRC;
          tx_put    <= '1';
          NextState <= Idle;

      end case;
    end if;
  end process;

end rtl;
