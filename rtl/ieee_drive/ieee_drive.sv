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
 
 module ieee_drive #(
	parameter DRIVES=1,
	parameter SUBDRV=2,
	parameter PAUSE_CTL=0  // 1=pause controller while SD is busy (prevents timeouts if SD is slow)
)(
	input       [31:0] CLK,

	input              clk_sys,
	input       [ND:0] reset,

	input              pause,

	output      [ND:0] led,

	input  st_ieee_bus bus_i,
	output st_ieee_bus bus_o,

	input       [ND:0] drv_type,

	input       [NB:0] img_mounted,
	input       [31:0] img_size,
	input              img_readonly,

	output      [31:0] sd_lba[NBD],
	output       [5:0] sd_blk_cnt[NBD],
	output      [NB:0] sd_rd,
	output      [NB:0] sd_wr,
	input       [NB:0] sd_ack,
	input       [12:0] sd_buff_addr,
	input        [7:0] sd_buff_dout,
	output       [7:0] sd_buff_din[NBD],
	input              sd_buff_wr,

	input              rom_wr,
	input              rom_sel,
	input       [14:0] rom_addr,
	input        [7:0] rom_data
);

localparam NDR = (DRIVES < 1) ? 1 : (DRIVES > 4) ? 4 : DRIVES;  // number of drives
localparam NSD = (SUBDRV < 1) ? 1 : (SUBDRV > 2) ? 2 : SUBDRV;  // number of subunits per drive
localparam NBD = NDR*NSD;                                       // number of block devices

localparam ND  = NDR - 1;
localparam NS  = NSD - 1;
localparam NB  = NBD - 1;

reg ce;
always @(posedge clk_sys) begin
	int sum = 0;

	ce <= 0;
	sum = sum + 16_000_000;
	if(sum >= CLK) begin
		sum = sum - CLK;
		ce <= 1;
	end
end

reg [NB:0] img_loaded;
reg [NB:0] img_readonly_l;
reg  [1:0] img_type[NBD];

always @(posedge clk_sys)
	for(int i=0; i<NBD; i=i+1)
		if (img_mounted[i]) begin
			img_loaded[i]     <= |img_size;
			img_type[i]       <= {drv_type[i >> NS], img_size[31:8] >= 4166};
			img_readonly_l[i] <= img_readonly;
		end

st_ieee_bus drv_bus_i;
st_ieee_bus drv_bus_o[NDR];
st_ieee_bus drv_bus[NDR];

ieeedrv_bus_sync bus_sync(clk_sys, bus_i, drv_bus_i);

wire [NS:0] led_act[NDR];
wire [ND:0] led_err;
wire        blink_err = err_count[21];

reg [21:0] err_count;
always @(posedge clk_sys) begin
	// when led_err is high, blink MiSTer led
	if (ce) begin
		if (|led_err)
			err_count <= err_count + 1'd1;
		else
			err_count <= '1;
	end
end

assign bus_o = drv_bus[NDR-1];

// ====================================================================
// Clock
// ====================================================================

reg ph2_r;
reg ph2_f;
always @(posedge clk_sys) begin
	reg [3:0] div;
	reg       ena, ena1;

	ena1 <= ~pause;
	if(div[2:0]) ena <= ena1;

	ph2_r <= 0;
	ph2_f <= 0;
	if(ce) begin
		div <= div + 1'd1;
		ph2_r <= ena && !div[3] && !div[2:0];
		ph2_f <= ena &&  div[3] && !div[2:0];
	end
end

// ====================================================================
// DOS ROM
// ====================================================================

wire [13:0] dos_addr[NDR];
wire  [7:0] dos_data[NDR], dos4040_data, dos8250_data;

wire  [1:0] dos_select;
wire [13:0] dos_rom_addr;

ieeedrv_rom #(8,14,16384,"rtl/ieee_drive/roms/c4040_dos.mif") c4040_dos_rom
(
	.clock_a(clk_sys),
	.address_a(dos_rom_addr),
	.q_a(dos4040_data),

	.clock_b(clk_sys),
	.wren_b(rom_wr && rom_sel && !rom_addr[14]),
	.address_b(rom_addr[13:0]),
	.data_b(rom_data)
);

ieeedrv_rom #(8,14,16384,"rtl/ieee_drive/roms/c8250_dos.mif") c8250_dos_rom
(
	.clock_a(clk_sys),
	.address_a(dos_rom_addr),
	.q_a(dos8250_data),

	.clock_b(clk_sys),
	.wren_b(rom_wr && !rom_sel && !rom_addr[14]),
	.address_b(rom_addr[13:0]),
	.data_b(rom_data)
);

ieee_rommux #(NDR,14) dos_rom_mux (
	.clk(clk_sys),
	.ph2(ph2_f),
	.drv_addr(dos_addr),
	.drv_select(dos_select),
	.rom_addr(dos_rom_addr),
	.rom_q(drv_type[dos_select] ? dos4040_data : dos8250_data),
	.drv_data(dos_data)
);

reg c4040_dos_16k = 0;
always @(posedge clk_sys) begin
	if (rom_wr && rom_sel && !rom_addr)
		c4040_dos_16k <= 0;

	if (rom_wr && rom_sel && ~|rom_addr[14:12] && |rom_data && ~&rom_data)
		c4040_dos_16k <= 1;
end

// ====================================================================
// Controller ROM
// ====================================================================

wire [10:0] ctl_addr[NDR];
wire  [7:0] ctl_data[NDR], ctl4040_data, ctl8250_data;

wire  [1:0] ctl_select;
wire [10:0] ctl_rom_addr;

ieeedrv_rom #(8,11,2048,"rtl/ieee_drive/roms/c4040_ctl.mif") c4040_controller_rom
(
	.clock_a(clk_sys),
	.address_a(ctl_rom_addr),
	.q_a(ctl4040_data),

	.clock_b(clk_sys),
	.wren_b(rom_wr && rom_sel && rom_addr[14:11] == 'b1000),
	.address_b(rom_addr[10:0]),
	.data_b(rom_data)
);

ieeedrv_rom #(8,11,2048,"rtl/ieee_drive/roms/c8250_ctl.mif") c8250_controller_rom
(
	.clock_a(clk_sys),
	.address_a(ctl_rom_addr),
	.q_a(ctl8250_data),

	.clock_b(clk_sys),
	.wren_b(rom_wr && !rom_sel && rom_addr[14:11] == 'b1000),
	.address_b(rom_addr[10:0]),
	.data_b(rom_data)
);

ieee_rommux #(NDR,11) controller_rom_mux (
	.clk(clk_sys),
	.ph2(ph2_r),
	.drv_addr(ctl_addr),
	.drv_select(ctl_select),
	.rom_addr(ctl_rom_addr),
	.rom_q(drv_type[ctl_select] ? ctl4040_data : ctl8250_data),
	.drv_data(ctl_data)
);

generate
	genvar d;
	for (d=0; d<NDR; d=d+1) begin :drive
		assign drv_bus[d] = d==0 ? drv_bus_o[d] : drv_bus_o[d] & drv_bus[d-1];
		assign led[d] = |led_act[d] | (led_err[d] & blink_err);

		localparam I0 = d*NSD;
		localparam I1 = d*NSD+NS;

		ieeedrv_drv #(
			.SUBDRV(SUBDRV), 
			.PAUSE_CTL(PAUSE_CTL)
		) drv (
			.CLK(CLK),
			.ce(ce),
			.ph2_f(ph2_f),
			.ph2_r(ph2_r),

			.clk_sys(clk_sys),
			.reset(reset[d] | rom_wr),

			.dev_id(3'(d)),
			.bus_i(drv_bus_i & bus_o),
			.bus_o(drv_bus_o[d]),

			.led_act(led_act[d]),
			.led_err(led_err[d]),

			.drv_type(drv_type[d]),
			.dos_16k(c4040_dos_16k | ~drv_type[d]),

			.dos_addr(dos_addr[d]),
			.dos_data(dos_data[d]),
			.ctl_addr(ctl_addr[d]),
			.ctl_data(ctl_data[d]),

			.img_mounted(img_mounted[I1:I0]),
			.img_loaded(img_loaded[I1:I0]),
			.img_readonly(img_readonly_l[I1:I0]),
			.img_type(img_type[I0:I1]),

			.sd_lba(sd_lba[I0:I1]),
			.sd_blk_cnt(sd_blk_cnt[I0:I1]),
			.sd_rd(sd_rd[I1:I0]),
			.sd_wr(sd_wr[I1:I0]),
			.sd_ack(sd_ack[I1:I0]),
			.sd_buff_addr(sd_buff_addr),
			.sd_buff_dout(sd_buff_dout),
			.sd_buff_din(sd_buff_din[I0:I1]),
			.sd_buff_wr(sd_buff_wr)
		);
	end
endgenerate

endmodule
