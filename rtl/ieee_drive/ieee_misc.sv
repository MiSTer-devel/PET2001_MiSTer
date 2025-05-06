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

module ieeedrv_sync #(parameter WIDTH = 1)
(
	input                  clk,
	input      [WIDTH-1:0] in,
	output reg [WIDTH-1:0] out
);

reg [WIDTH-1:0] s1,s2;
always @(posedge clk) begin
	s1 <= in;
	s2 <= s1;
	if(s1 == s2) out <= s2;
end

endmodule

module ieeedrv_bus_sync
(
	input              clk,
	input  st_ieee_bus in,
	output st_ieee_bus out
);

st_ieee_bus s1,s2;
always @(posedge clk) begin
	s1 <= in;
	s2 <= s1;
	if(s1 == s2) out <= s2;
end

endmodule

module ieeedrv_rom #(
	parameter DATAWIDTH,
	parameter ADDRWIDTH,
	parameter NUMWORDS,
	parameter INITFILE="UNUSED"
)(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

altsyncram altsyncram_component (
	.clock0 (clock_a),
	.address_a (address_a),
	.addressstall_a (1'b0),
	.byteena_a (1'b1),
	.data_a (data_a),
	.rden_a (1'b1),
	.wren_a (wren_a),
	.q_a (q_a),

	.clock1 (clock_b),
	.address_b (address_b),
	.addressstall_b (1'b0),
	.byteena_b (1'b1),
	.data_b (data_b),
	.rden_b (1'b1),
	.wren_b (wren_b),
	.q_b (q_b)
);

defparam
	altsyncram_component.byte_size = DATAWIDTH,
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
	altsyncram_component.lpm_type = "altsyncram",
	altsyncram_component.init_file = INITFILE,

	altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
	altsyncram_component.power_up_uninitialized = "FALSE",

	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.outdata_reg_a = "CLOCK0",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.width_a = DATAWIDTH,
	altsyncram_component.numwords_a = NUMWORDS,

	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.outdata_reg_b = "CLOCK1",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_b = ADDRWIDTH,
	altsyncram_component.width_b = DATAWIDTH,
	altsyncram_component.numwords_b = NUMWORDS;

endmodule

module ieeedrv_mem #(
	parameter DATAWIDTH,
	parameter ADDRWIDTH
)(
	input	                     clock_a,
	input	     [ADDRWIDTH-1:0] address_a,
	input	     [DATAWIDTH-1:0] data_a,
	input	                     wren_a,
	output reg [DATAWIDTH-1:0] q_a,

	input	                     clock_b,
	input	     [ADDRWIDTH-1:0] address_b,
	input	     [DATAWIDTH-1:0] data_b,
	input	                     wren_b,
	output reg [DATAWIDTH-1:0] q_b
);

altsyncram altsyncram_component (
	.clock0 (clock_a),
	.address_a (address_a),
	.addressstall_a (1'b0),
	.byteena_a (1'b1),
	.data_a (data_a),
	.rden_a (1'b1),
	.wren_a (wren_a),
	.q_a (q_a),

	.clock1 (clock_b),
	.address_b (address_b),
	.addressstall_b (1'b0),
	.byteena_b (1'b1),
	.data_b (data_b),
	.rden_b (1'b1),
	.wren_b (wren_b),
	.q_b (q_b)
);

defparam
	altsyncram_component.byte_size = DATAWIDTH,
	altsyncram_component.intended_device_family = "Cyclone V",
	altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
	altsyncram_component.lpm_type = "altsyncram",

	altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
	altsyncram_component.power_up_uninitialized = "FALSE",

	altsyncram_component.clock_enable_input_a = "BYPASS",
	altsyncram_component.clock_enable_output_a = "BYPASS",
	altsyncram_component.outdata_reg_a = "CLOCK0",
	altsyncram_component.outdata_aclr_a = "NONE",
	altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_a = ADDRWIDTH,
	altsyncram_component.width_a = DATAWIDTH,

	altsyncram_component.clock_enable_input_b = "BYPASS",
	altsyncram_component.clock_enable_output_b = "BYPASS",
	altsyncram_component.outdata_reg_b = "CLOCK1",
	altsyncram_component.outdata_aclr_b = "NONE",
	altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
	altsyncram_component.widthad_b = ADDRWIDTH,
	altsyncram_component.width_b = DATAWIDTH;

endmodule

module ieee_rommux #(
	parameter NDR = 4,
	parameter ADDRWIDTH = 14
)(
	input                  clk,
	input                  ph2,
	input  [ADDRWIDTH-1:0] drv_addr[NDR],
	output           [1:0] drv_select,
	output [ADDRWIDTH-1:0] rom_addr,
	
	input            [7:0] rom_q,
	output reg       [7:0] drv_data[NDR]
);

localparam OFFSET = 3;

reg [2:0] mux_state;

assign drv_select = mux_state[1:0] - 2'(OFFSET);

always @(posedge clk) begin
	if (~&mux_state) 
		mux_state <= mux_state + 1'd1;
	if (ph2)
		mux_state <= 0;

	if (mux_state < NDR)
		rom_addr <= drv_addr[mux_state[1:0]];
	
	if (mux_state >= OFFSET && mux_state < NDR+OFFSET)
		drv_data[drv_select] <= rom_q;
end

endmodule
