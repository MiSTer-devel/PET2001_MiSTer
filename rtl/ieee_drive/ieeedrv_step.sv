/*
 * Commodore 4040/8250 IEEE drive implementation
 *
 * Copyright (C) 2024, Erik Scheffers (https://github.com/eriks5)
 *
 * This file is part of PET2001_MiSTer.
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 2.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

module ieeedrv_step (
	input        clk_sys,
	input        reset,
	input        ce,

	input        drv_type,

	input        mounted,
	input        selected,
	input        active,
	input        changing,

	input        mtr,
	input  [1:0] stp,
	input        we,
	input        rw,
	input        hd,

	output reg   save_track,
	output [7:0] track,
	output       track_changing
);

// For 4040 "6530-34 RIOT DOS 2" part #901466-04 
// and 8520 "6530-47 RIOT DOS 2.7 Micropolis" part #901885-04
// (some other RIOT versions for other drive types use different step motor control signals)

// Track constants
localparam SIDE0_START = 1;
localparam SIDE1_START = 78;
wire [8:0] MAX_HTRACK = 9'(drv_type ? 42*2 : 76*4);  // Max half/quarter track number
wire [8:0] DIR_HTRACK = 9'(drv_type ? 17*2 : 38*4);  // Directory half/quarter track number

// `ce` pulses to wait after drive stops writing before flushing buffer if controller is idle
localparam SAVE_DELAY = 8_000_000;  // 0.5 seconds = 2.5 rotations at 300 RPM

// max `ce` pulses between stepper pulses
wire [18:0] CHANGE_DELAY = 19'(drv_type ? 'h4_0000 : 'h2_0000);

// max `ce` pulses between random `hd` signal changes
localparam HD_CHANGE_DELAY = 1023;

assign track_changing = |change_cnt;
assign track = track_changing ? track_r 
										: (drv_type ? 8'(htrack[7:1] + SIDE0_START)
														: 8'(htrack[8:2] + (hd ? SIDE1_START : SIDE0_START)));

reg  [8:0] htrack;
reg  [7:0] track_r;
reg [18:0] change_cnt;

always @(posedge clk_sys) begin
	reg [22:0] save_cnt;
	reg  [9:0] hd_cnt;
	reg        track_modified;
	reg  [1:0] move, stp_old;
	reg        hd_old, rw_old;

	track_r  <= track;
	stp_old  <= stp;
	move     <= stp - stp_old;

	if (reset || selected) begin
		hd_old <= hd;
		rw_old <= rw;
	end

	if (change_cnt && ce)
		change_cnt <= change_cnt - 1'b1;

	if (save_cnt && ce)
		save_cnt <= save_cnt - 1'b1;

	if (hd_cnt && ce)
		hd_cnt <= hd_cnt - 1'b1;

	if (reset || mounted) begin
		htrack <= DIR_HTRACK;
		track_modified <= 0;
		change_cnt <= 0;
	end
	else begin
		if (move[0]) begin
			if (!move[1] && htrack < MAX_HTRACK) begin
				htrack     <= htrack + 1'b1;
				change_cnt <= CHANGE_DELAY;
			end
			if (move[1] && htrack > 0) begin
				htrack     <= htrack - 1'b1;
				change_cnt <= CHANGE_DELAY;
			end
		end

		if (selected) begin
			if (we)
				track_modified <= 1;

			if (hd == hd_old)
				hd_cnt <= 10'(HD_CHANGE_DELAY);
			else
				change_cnt <= CHANGE_DELAY;

			if (rw_old && !rw)
				change_cnt <= 0;

			if (!track_modified || we)
				save_cnt <= 23'(SAVE_DELAY);
		end

		if (track_modified && (changing || move[0] || (selected && (!mtr || !hd_cnt || !save_cnt)))) begin
			track_modified <= 0;
			save_track     <= ~save_track;
			save_cnt       <= 23'(SAVE_DELAY);
		end
	end
end

endmodule
