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

module ieeedrv_track #(
	parameter SUBDRV=2
)(
	input             clk_sys,
	input             reset,
	input             ce,
	input             halt,

	input             drv_type,

	input      [NS:0] mounted,

	input      [NS:0] drv_mtr,
	input             drv_sel,
	input             drv_hd,

	output            drv_act,
	output            drv_changing,

	output     [31:0] sd_lba[SUBDRV],
	output      [5:0] sd_blk_cnt[SUBDRV],
	output reg [NS:0] sd_rd,
	output reg [NS:0] sd_wr,
	input      [NS:0] sd_ack,

	input      [NS:0] save_track,
	input       [7:0] track[SUBDRV],
	output      [7:0] ltrack,

	output reg [NS:0] busy
);

localparam NS = SUBDRV-1;

wire [NS:0] mounted_s;
wire        reset_s, drv_sel_s, save_track_s;

ieeedrv_sync #(SUBDRV) mounted_sync (clk_sys, mounted,             mounted_s);
ieeedrv_sync #(1)      sel_sync     (clk_sys, drv_sel && SUBDRV>1, drv_sel_s);
ieeedrv_sync #(1)      save_sync    (clk_sys, ^save_track,         save_track_s);
ieeedrv_sync #(1)      reset_sync   (clk_sys, reset,               reset_s);

wire [12:0] START_SECTOR[2][155] = '{
	'{   0,  29,  58,  87, 116, 145, 174, 203, 232, 261, 290, 319, 348, 377, 406, 435, // 0-15
	   464, 493, 522, 551, 580, 609, 638, 667, 696, 725, 754, 783, 812, 841, 870, 899, // 16-31
	   928, 957, 986,1015,1044,1073,1102,1131,1158,1185,1212,1239,1266,1293,1320,1347, // 32-47
	  1374,1401,1428,1455,1482,1509,1534,1559,1584,1609,1634,1659,1684,1709,1734,1759, // 48-63
	  1784,1807,1830,1853,1876,1899,1922,1945,1968,1991,2014,2037,2060,2083,2112,2141, // 64-79
	  2170,2199,2228,2257,2286,2315,2344,2373,2402,2431,2460,2489,2518,2547,2576,2605, // 80-95
	  2634,2663,2692,2721,2750,2779,2808,2837,2866,2895,2924,2953,2982,3011,3040,3069, // 96-111
	  3098,3127,3156,3185,3214,3241,3268,3295,3322,3349,3376,3403,3430,3457,3484,3511, // 112-127
	  3538,3565,3592,3617,3642,3667,3692,3717,3742,3767,3792,3817,3842,3867,3890,3913, // 128-143
	  3936,3959,3982,4005,4028,4051,4074,4097,4120,4143,4166                           // 144-154
	},
	'{   0,  21,  42,  63,  84, 105, 126, 147, 168, 189, 210, 231, 252, 273, 294, 315, // 0-15
		336, 357, 376, 395, 414, 433, 452, 471, 490, 508, 526, 544, 562, 580, 598, 615, // 16-31
		632, 649, 666, 683, 700, 717, 734, 751, 768, 768, 768, 768, 768, 768, 768, 768, // 32-47
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 48-63
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 64-79
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 80-95
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 96-111
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 112-127
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768, // 128-143
		768, 768, 768, 768, 768, 768, 768, 768, 768, 768, 768                           // 144-154
	}
};

wire [7:0] INIT_TRACK  = 8'(drv_type  ? 18 : 39);

reg [10:0] chg_count = 0;

assign drv_changing = &chg_count[10:2];
wire   drv_change   = &chg_count;

always @(posedge clk_sys) begin
	if (SUBDRV == 1 || drv_sel_s == drv_act)
		chg_count <= 0;
	else if (~&chg_count && ce && !halt)
		chg_count <= chg_count + 1'd1;
	end

`define select_track(drv, strack) \
	busy[drv]       <= 1; \
	ltrack          <= strack; \
	sd_blk_cnt[drv] <= 6'(START_SECTOR[drv_type][strack] - START_SECTOR[drv_type][strack - 1'd1] - 1); \
	sd_lba[drv]     <= START_SECTOR[drv_type][strack - 1'd1];

`define init_track(drv) \
	`select_track(drv, INIT_TRACK); \
	sd_rd[drv] <= 1;

`define read_track(drv) \
	if (drv != drv_act || track[drv] != ltrack) begin \
		`select_track(drv, track[drv]); \
		sd_rd[drv] <= 1; \
	end

`define write_track(drv) \
	`select_track(drv, ltrack); \
	sd_wr[drv] <= 1;


always @(posedge clk_sys) begin
	reg [NS:0] old_mounted, update;
	reg        old_ack;
	reg        old_save_track = 0;
	reg        resetting = 0;

	old_mounted <= mounted_s;
	for (integer cd=0; cd<SUBDRV; cd=cd+1)
		if (~old_mounted[cd] & mounted_s[cd]) update[cd] <= 1;

	old_ack <= sd_ack[drv_act];
	if (sd_ack[drv_act]) begin
		sd_rd[drv_act] <= 0;
		sd_wr[drv_act] <= 0;
	end

	if (reset_s) begin
		busy      <= '0;
		sd_rd     <= '0;
		sd_wr     <= '0;
		resetting <= 1;
		drv_act   <= 0;
	end
	else if (resetting) begin
		if (!drv_sel_s || SUBDRV==1) begin
			resetting    <= 0;
			update       <= '1;
			ltrack       <= '1;
		end
	end
	else if (!busy[drv_act] || (old_ack && !sd_ack[drv_act])) begin
		busy[drv_act] <= 0;
		old_save_track <= save_track_s;

		if ((old_save_track != save_track_s) && ~&ltrack) begin
			`write_track(drv_act);
		end
		else if (drv_change) begin
			drv_act <= drv_sel_s;

			if (update[drv_sel_s]) begin
				update[drv_sel_s] <= 0;
				`init_track(drv_sel_s);
			end
			else begin
				`read_track(drv_sel_s);
			end
		end
		else if (update[drv_act]) begin
			update[drv_act] <= 0;
			`init_track(drv_act);
		end
		else begin
			`read_track(drv_act);
		end
	end
end

endmodule
