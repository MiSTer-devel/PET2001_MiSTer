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

module ieeedrv_logic #(
	parameter SUBDRV=2
)(
   input              clk_sys,
   input              reset,

	input              ph2_r,
	input              ph2_f,

	input              halt_ctl,

	input        [1:0] drv_type,   // 00=8050, 01=8250, 10=4040
	input              dos_16k,

	input        [2:0] dev_id,
	output      [NS:0] led_act,
	output             led_err,

   input  st_ieee_bus bus_i,
   output st_ieee_bus bus_o,

	input       [NS:0] img_mounted,
	input       [NS:0] img_loaded,
	input       [NS:0] img_readonly,

	output      [13:0] dos_addr,
	input        [7:0] dos_data,
	output      [10:0] ctl_addr,
	input        [7:0] ctl_data,

	output             drv_sel,
	output      [NS:0] drv_mtr,
	output       [1:0] drv_step[SUBDRV],
	output       [1:0] drv_spd,
	output             drv_hd,
	output             drv_rw,

	input              drv_error,
	input              drv_ready,
	input              drv_brdy_n,
	output             drv_pllsyn,

	input        [7:0] drv_dat_i,
	input              drv_sync_i,
	output       [7:0] drv_dat_o,
	output             drv_sync_o
);

localparam NS = SUBDRV-1;

assign dos_addr = un1_a[13:0];
assign ctl_addr = uc3_a[10:0];

wire ph2_r_dos = ph2_r;
wire ph2_f_dos = ph2_f;
wire ph2_r_ctl = ph2_r && !halt_ctl;
wire ph2_f_ctl = ph2_f && !halt_ctl;

// ====================================================================
// CPU DOS (6502) UN1
// ====================================================================

wire uf1_cs     = dos_16k ? un1_a[15:12] == 0 && un1_a[7] == 0              : un1_a[14:12] == 0 && un1_a[7] == 0;     // RIOT1
wire ue1_cs     = dos_16k ? un1_a[15:12] == 0 && un1_a[7] == 1              : un1_a[14:12] == 0 && un1_a[7] == 1;     // RIOT2
wire un1_ram_cs = dos_16k ? un1_a[15:12] >= 1 && un1_a[15:12] < 5           : un1_a[14:12] >= 1 && un1_a[14:12] < 5;  // RAM
wire un1_rom_cs = dos_16k ? un1_a[15] || (drv_type[1] && un1_a[14:12] >= 5) : un1_a[14:12] >= 5;                      // ROM

wire  [7:0] un1_di =
	!un1_rw     ? un1_do :
	 uf1_cs     ? uf1_data :
	 ue1_cs     ? ue1_data :
	 un1_ram_cs ? un1_ram_data :
	 un1_rom_cs ? dos_data :
	 8'hFF;

wire [23:0] un1_a;
wire  [7:0] un1_do;
wire        un1_rw;

T65 un1
(
	.MODE(2'b00),
	.RES_n(~reset),
	.ENABLE(ph2_f_dos),
	.CLK(clk_sys),
	.IRQ_n(ue1_irq),
	.SO_n(~reset),
	.R_W_n(un1_rw),
	.A(un1_a),
	.DI(un1_di),
	.DO(un1_do)
);

// ====================================================================
// RIOT1 (6532) UF1: IEEE-488 data
// ====================================================================

wire [7:0] uf1_data;
wire [7:0] uf1_pao;
wire [7:0] uf1_pbo;

assign bus_o.data = {8{~atni | reset}} | uf1_pbo;

M6532 uf1
(
	.clk(clk_sys),
	.ce(ph2_r_dos),
	.res_n(~reset),
	.addr(un1_a[6:0]),
	.RW_n(un1_rw),
	.d_in(un1_di),
	.d_out(uf1_data),
	.RS_n(un1_a[9]),
	.CS1(uf1_cs),
	.CS2_n(1'b0),

	.PA_in(uf1_pao & (({8{~atni}} | uf1_pbo) & bus_i.data)),
	.PA_out(uf1_pao),

	.PB_in(uf1_pbo),
	.PB_out(uf1_pbo)
);

// ====================================================================
// RIOT2 (6532) UE1: IEEE-488 control, leds, drive number
// ====================================================================

wire [7:0] ue1_data;
wire       ue1_irq;
wire [7:0] ue1_pao;
wire [7:0] ue1_pbo;

assign     led_err = ue1_pbo[5];
generate
	genvar i1;
	for (i1=0; i1<SUBDRV; i1=i1+1) begin :leds
		assign led_act[i1] = ue1_pbo[4-i1];
	end
endgenerate

wire       atni = bus_i.atn;
wire       eoii = bus_i.eoi;
wire       davi = bus_i.dav;
wire       rdfi = bus_i.nrfd;
wire       daci = bus_i.ndac;

wire       atna = ue1_pao[0];
wire       eoio = ue1_pao[3];
wire       davo = ue1_pao[4];
wire       rfdo = ~(~(atna | atni) | ~(~(atna & atni) & ue1_pao[2]));
wire       daco = ~(~(atna | atni) | ue1_pao[1]);

assign     bus_o.eoi  = eoio | reset;
assign     bus_o.dav  = davo | reset;
assign     bus_o.nrfd = rfdo | reset;
assign     bus_o.ndac = daco | reset;

assign     bus_o.atn  = 1'b1;
assign     bus_o.srq  = 1'b1;
assign     bus_o.ren  = 1'b1;
assign     bus_o.ifc  = 1'b1;

M6532 ue1
(
	.clk(clk_sys),
	.ce(ph2_r_dos),
	.res_n(~reset),
	.addr(un1_a[6:0]),
	.RW_n(un1_rw),
	.d_in(un1_di),
	.d_out(ue1_data),
	.RS_n(un1_a[9]),
	.IRQ_n(ue1_irq),
	.CS1(ue1_cs),
	.CS2_n(1'b0),

	.PA_in(ue1_pao & {~atni, davi, eoii, 5'b11111}),
	.PA_out(ue1_pao),

	.PB_in(ue1_pbo & {rdfi, daci, 3'b111, dev_id}),
	.PB_out(ue1_pbo)
);

// ====================================================================
// CPU drive (6504) UC3
// ====================================================================

wire uc5_cs     = uc3_a[12:10] == 0 && uc3_a[6] == 0;      // RRIOT RAM or I/O
wire ud5_cs     = uc3_a[12:10] == 0 && uc3_a[6] == 1;      // VIA
wire uc3_ram_cs = uc3_a[12:10] >= 1 && uc3_a[12:10] < 5;
wire uc5_rom_cs = uc3_a[12:10] >= 6;                       // RRIOT ROM

wire  [7:0] uc3_di =
	!uc3_rw     ? uc3_do :
	 uc5_cs     ? uc5_data :
	 ud5_cs     ? ud5_data :
	 uc3_ram_cs ? uc3_ram_data :
	 uc5_rom_cs ? ctl_data :
	 8'hFF;

wire [23:0] uc3_a;
wire  [7:0] uc3_do;
wire        uc3_rw;

T65 uc3
(
	.MODE(2'b00),
	.RES_n(~reset),
	.ENABLE(ph2_r_ctl),
	.CLK(clk_sys),
	.IRQ_n(uc5_irq),
	.SO_n(drv_brdy_n | drv_type[1]),
	.R_W_n(uc3_rw),
	.A(uc3_a),
	.DI(uc3_di),
	.DO(uc3_do)
);

// ====================================================================
// RRIOT (6530) UC5
// ====================================================================

wire   [7:0] uc5_data;

wire   [7:0] dat_do;
wire   [7:0] uc5_pbo;

wire         uc5_irq = uc5_pbo[7];

reg   [NS:0] wps;

assign drv_hd  = drv_type[0] & ~uc5_pbo[4];
assign drv_spd = uc5_pbo[2:1];
assign drv_sel = uc5_pbo[0] && (SUBDRV>1);

M6532 #(.RRIOT(1)) uc5
(
	.clk(clk_sys),
	.ce(ph2_f_ctl),
	.res_n(~reset),
	.addr(uc3_a[6:0]),
	.RW_n(uc3_rw),
	.d_in(uc3_di),
	.d_out(uc5_data),
	.RS_n(uc3_a[7]),
	.IOS_n(~uc3_a[7]),
	.CS1(uc5_cs),
	.CS2_n(1'b0),

	.PA_in(drv_dat_o),
	.PA_out(drv_dat_o),

	.PB_in({1'b1, drv_type[1] ? drv_sync_i : ~drv_type[0], 2'b11, wps[drv_sel], 3'b111} & uc5_pbo),
	.PB_out(uc5_pbo)
);

generate
	genvar i2;
	for (i2=0; i2<SUBDRV; i2=i2+1) begin :disk_change
		always @(posedge clk_sys) begin
			reg [21:0] cnt;

			wps[i2] <= ~img_loaded[i2] | img_readonly[i2];

			if (reset) 
				cnt <= 0;
			else if (img_mounted[i2])
				cnt <= '1;
			else if (cnt) begin
				wps[i2] <= ~cnt[21];
				if (ph2_f_ctl) cnt <= cnt - 1'b1;
			end
		end
	end
endgenerate

// ====================================================================
// VIA (6522) UD5
// ====================================================================

wire [7:0] ud5_data;

wire [7:0] ud5_pa_o;
wire [7:0] ud5_pb_o;

assign     drv_pllsyn = ud5_pb_o[6] & ~drv_type[1];

generate
	genvar i3;
	for (i3=0; i3<SUBDRV; i3=i3+1) begin :mtr_step
		assign drv_mtr[i3]  = ~ud5_pb_o[5-i3];
		assign drv_step[i3] = ud5_pb_o[3-i3*2:2-i3*2];
	end
endgenerate

via6522 ud5
(
	.data_out(ud5_data),
	.data_in(uc3_do),
	.addr(uc3_a[3:0]),
	.strobe(ph2_r_ctl & ud5_cs),
	.we(~uc3_rw),

	.porta_out(ud5_pa_o),
	.porta_in(drv_dat_i),

	.portb_out(ud5_pb_o),
	.portb_in({drv_sync_i | drv_type[1], 7'b1111111}),

	.ca1_in(drv_ready),
	.ca2_out(drv_sync_o),
	.ca2_in(1'b0),
	.cb1_out(),
	.cb1_in(drv_error),
	.cb2_out(drv_rw),
	.cb2_in(1'b0),

	.ce(ph2_f_ctl),
	.clk(clk_sys),
	.reset(reset)
);

// ====================================================================
// RAM UD3/UE3
// ====================================================================

// DOS         CONTROLLER  RAM addr
// 1000-13FF   0400-07FF   0400
// 2000-23FF   0800-0BFF   0800
// 3000-33FF   0C00-0FFF   0C00
// 4000-43FF   1000-13FF   0000

wire  [7:0] un1_ram_data;
wire  [7:0] uc3_ram_data;

ieeedrv_mem #(8,12) ieeedrv_ram
(
	.clock_a(clk_sys),
	.address_a({un1_a[13:12], un1_a[9:0]}),
	.wren_a(~un1_rw & un1_ram_cs & ph2_r_dos),
	.data_a(un1_do),
	.q_a(un1_ram_data),

	.clock_b(clk_sys),
	.address_b(uc3_a[11:0]),
	.wren_b(~uc3_rw & uc3_ram_cs & ph2_f_ctl),
	.data_b(uc3_do),
	.q_b(uc3_ram_data)
);

endmodule
