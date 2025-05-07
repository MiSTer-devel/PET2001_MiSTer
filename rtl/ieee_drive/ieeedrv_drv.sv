/*
 * Commodore 4040/8250 IEEE drive implementation
 *
 * Copyright (C) 2024, Erik Scheffers
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
 
module ieeedrv_drv #(parameter SUBDRV=2)
(
   input       [31:0] CLK,

	input              clk_sys,
   input              reset,
	input              ce,
	input              ph2_r,
	input              ph2_f,

	input        [2:0] dev_id,
	output      [NS:0] led_act,
	output             led_err,

   input  st_ieee_bus bus_i,
   output st_ieee_bus bus_o,

	input              drv_type,
	input              dos_16k,

	input       [NS:0] img_mounted,
	input       [NS:0] img_loaded,
	input       [NS:0] img_readonly,
	input        [1:0] img_type[SUBDRV],

	output      [13:0] dos_addr,
	input        [7:0] dos_data,
	output      [10:0] ctl_addr,
	input        [7:0] ctl_data,

	output      [31:0] sd_lba[SUBDRV],
	output       [5:0] sd_blk_cnt[SUBDRV],
	output      [NS:0] sd_rd,
	output      [NS:0] sd_wr,
	input       [NS:0] sd_ack,

	input       [12:0] sd_buff_addr,
	input        [7:0] sd_buff_dout,
	output       [7:0] sd_buff_din[SUBDRV],
	input              sd_buff_wr
);

localparam NS = SUBDRV-1;

// ====================================================================
// Reset
// ====================================================================

reg [23:0] drv_reset_cnt;

always @(posedge clk_sys) begin
	reg drv_type_l;

	drv_type_l <= drv_type;
	if (reset || drv_type_l != drv_type)
		drv_reset_cnt <= '1;
	else if (drv_reset_cnt && ce)
		drv_reset_cnt <= drv_reset_cnt - 1'b1;
end

wire drv_reset = |drv_reset_cnt;

// ====================================================================
// Leds
// ====================================================================

generate
	genvar s;
	for (s=0; s<SUBDRV; s=s+1) begin :led_acts
		assign led_act[s] = (|led_act_o[s] | sd_busy[s]) & ~drv_reset;
	end
endgenerate

assign led_err = led_err_o & ~drv_reset;

// ====================================================================
// Logic
// ====================================================================

wire        drv_sel;
wire [NS:0] drv_mtr;
wire  [1:0] drv_step[SUBDRV];
wire  [1:0] drv_spd;
wire        drv_hd;
wire        drv_rw;

wire  [7:0] drv_dat_i;
wire        drv_sync_i;
wire        drv_ready;
wire        drv_brdy_n;

wire  [7:0] drv_dat_o;
wire        drv_sync_o;
wire        drv_error;

wire [NS:0] led_act_o;
wire        led_err_o;

ieeedrv_logic #(.SUBDRV(SUBDRV)) drv_logic
(
	.clk_sys(clk_sys),
	.reset(drv_reset),
	.ph2_r(ph2_r),
	.ph2_f(ph2_f),

	.drv_type({drv_type, ~drv_type}),
	.dos_16k(dos_16k),

	.dev_id(dev_id),
	.led_act(led_act_o),
	.led_err(led_err_o),

	.bus_i(bus_i),
	.bus_o(bus_o),

	.img_mounted(img_mounted),
	.img_loaded(img_loaded),
	.img_readonly(img_readonly),

	.dos_addr(dos_addr),
	.dos_data(dos_data),
	.ctl_addr(ctl_addr),
	.ctl_data(ctl_data),

	.drv_sel(drv_sel),
	.drv_mtr(drv_mtr),
	.drv_step(drv_step),
	.drv_spd(drv_spd),
	.drv_hd(drv_hd),
	.drv_rw(drv_rw),

	.drv_error(drv_error),
	.drv_ready(drv_ready),
	.drv_brdy_n(drv_brdy_n),

	.drv_dat_i(drv_dat_i),
	.drv_sync_i(drv_sync_i),

	.drv_dat_o(drv_dat_o),
	.drv_sync_o(drv_sync_o)
);

// ====================================================================
// Track
// ====================================================================

wire [NS:0] save_track;

wire  [6:0] track[SUBDRV];
wire        drv_act;
reg  [15:0] dsk_id[SUBDRV];
reg   [7:0] drv_sd_buff_din;
wire        drv_we;

wire [12:0] DIR_SECTOR = drv_type ? 13'd357 : 13'd1102;

reg  [NS:0] id_loaded;

generate
	genvar i;
	for (i=0; i<SUBDRV; i=i+1) begin :subdrive
		ieeedrv_step drv_stepper (
			.clk_sys(clk_sys),
			.reset(drv_reset),

			.drv_type(drv_type),

			.we(drv_we & (drv_ready | drv_sync_o) & drv_mtr[i] & (drv_sel == i)),

			.img_mounted(img_mounted[i]),
			.act(led_act[i] & (drv_sel == i)),

			.mtr(drv_mtr[i]),
			.stp(drv_step[i]),

			.save_track(save_track[i]),
			.track(track[i])
		);

		always @(posedge clk_sys) begin
			if (img_mounted[i])
				id_loaded[i] <= 0;

			if (!id_loaded[i] && sd_busy[i] && sd_lba[i] == DIR_SECTOR && sd_buff_wr)
				case (sd_buff_addr)
					'h18: if (!img_type[i][1]) dsk_id[i][7:0]  <= sd_buff_dout;
					'h19: if (!img_type[i][1]) dsk_id[i][15:8] <= sd_buff_dout;
					'hA2: if ( img_type[i][1]) dsk_id[i][7:0]  <= sd_buff_dout;
					'hA3: if ( img_type[i][1]) dsk_id[i][15:8] <= sd_buff_dout;
					'hFF: id_loaded[i] <= 1;
					default: ;
				endcase

			if (id_wr && drv_act == i) begin
				dsk_id[i] <= id_hdr;
				id_loaded[i] <= 1;
			end
		end

		assign sd_buff_din[i] = drv_sd_buff_din;
	end
endgenerate

wire [NS:0] sd_busy, busy;
wire  [7:0] ltrack;

ieeedrv_sync #(SUBDRV) busy_sync(clk_sys, busy, sd_busy);

ieeedrv_track #(SUBDRV) drv_track
(
	.clk_sys(clk_sys),
	.reset(drv_reset),
	.ce(ce),

	.drv_type(drv_type),

	.mounted(img_mounted),
	.loaded(img_loaded),

	.drv_mtr(drv_mtr),
	.drv_sel(drv_sel),
	.drv_act(drv_act),
	.drv_hd(drv_hd),

	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),

	.save_track(save_track),
	.track(track),
	.ltrack(ltrack),

	.busy(busy)
);

reg  [15:0] id_hdr;
reg         id_wr;

ieeedrv_trkgen #(SUBDRV) drv_trkgen
(
	.CLK(CLK),

	.clk_sys(clk_sys),

	.reset(drv_reset),

	.drv_type(drv_type),
	.img_type(img_type[drv_act]),

	.drv_act(drv_act),
	.drv_hd(drv_hd),
	.mtr(drv_mtr[drv_act]),
	.freq(drv_spd),
	.track(ltrack),
	.busy(sd_busy[drv_act] | ~id_loaded[drv_act]),
	.wprot(img_readonly[drv_act]),
	.rw(drv_rw),

	.we(drv_we),
	.byte_n(drv_ready),
	.brdy_n(drv_brdy_n),
	.error(drv_error),

	.sync_rd_n(drv_sync_i),
	.byte_rd(drv_dat_i),

	.sync_wr(drv_sync_o),
	.byte_wr(drv_dat_o),

	.loaded(img_loaded[drv_act]),
	.sd_clk(clk_sys),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(drv_sd_buff_din),
	.sd_buff_wr(|sd_ack & sd_buff_wr),

	.id(dsk_id[drv_act]),
	.id_hdr(id_hdr),
	.id_wr(id_wr)
);

endmodule
