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
   input            clk_sys,
   input            reset,

	input            drv_type,

   input            we,

   input            img_mounted,
   input            act,

   input            mtr,
   input      [1:0] stp,

   output reg       save_track,
   output     [6:0] track
);

// For 4040 "6530-34 RIOT DOS 2" part #901466-04 
// and 8520 "6530-47 RIOT DOS 2.7 Micropolis" part #901885-04
// (some other RIOT versions for other drive types use different step motor control signals)

wire [8:0] MAX_HTRACK = 9'(drv_type ? 42*2 : 76*4);
wire [8:0] DIR_HTRACK = 9'(drv_type ? 17*2 : 38*4);

reg  [8:0] htrack;

assign track = drv_type ? htrack[7:1] :  htrack[8:2];

always @(posedge clk_sys) begin
	reg       track_modified;
	reg [1:0] move, stp_old;

	stp_old <= stp;
	move <= stp - stp_old;

	if (we)          track_modified <= 1;
	if (img_mounted) track_modified <= 0;

	if (reset) begin
		htrack <= DIR_HTRACK;
		track_modified <= 0;
	end
   else begin
		if (mtr && move[0]) begin
			if (!move[1] && htrack < MAX_HTRACK) htrack <= htrack + 1'b1;
			if ( move[1] && htrack > 0         ) htrack <= htrack - 1'b1;
			if (track_modified) save_track <= ~save_track;
			track_modified <= 0;
		end

		if (track_modified && !act) begin // stopping activity or changing drives
			save_track <= ~save_track;
			track_modified <= 0;
		end
	end
end

endmodule
