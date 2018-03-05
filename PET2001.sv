//============================================================================
//  PET2001
//
//  Port to MiSTer
//  Copyright (C) 2017,2018 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [43:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_USER  = tape_led | ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

`include "build_id.v" 
localparam CONF_STR = 
{
	"PET2001;;",
	"-;",
	"F,TAPPRG;",
	"O78,TAP mode,Fast,Normal,Normal+Sound;",
	"-;",
	"O9A,CPU Speed,Normal,x2,x4,x8;",
	"O3,Diag,Off,On(needs Reset);",
	"-;",
	"O2,Screen Color,White,Green;",
	"O1,Aspect Ratio,4:3,16:9;",
	"-;",
	"T6,Reset;",
	"V,v0.70.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire pll_locked;
		
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

reg reset = 1;
always @(posedge clk_sys) begin
	integer   initRESET = 20000000;
	reg [3:0] reset_cnt;

	if ((!(RESET | status[0] | buttons[1] | status[6]) && reset_cnt==4'd14) && !initRESET)
		reset <= 0;
	else begin
		if(initRESET) initRESET <= initRESET - 1;
		reset <= 1;
		reset_cnt <= reset_cnt+4'd1;
	end
end

reg  ce_7mp;
reg  ce_7mn;
reg  ce_1m;
wire [6:0] cpu_rates[4] = '{111, 55, 27, 13};

always @(negedge clk_sys) begin
	reg  [4:0] div = 0;
	reg  [6:0] cpu_div = 0;
	reg  [6:0] cpu_rate = 111;

	div <= div + 1'd1;
	ce_7mp  <= !div[3] & !div[2:0];
	ce_7mn  <=  div[3] & !div[2:0];
	
	cpu_div <= cpu_div + 1'd1;
	if(cpu_div == cpu_rate) begin
		cpu_div  <= 0;
		cpu_rate <= (tape_active && !status[8:7]) ? 7'd2 : cpu_rates[status[10:9]];
	end
	ce_1m <= ~(tape_active & ~ram_ready) && !cpu_div;
end


///////////////////////////////////////////////////
// RAM
///////////////////////////////////////////////////

wire ram_ready;
assign DDRAM_CLK = clk_sys;

ddram ram
(
	.*,

	.reset(RESET),
	
	.dout(tape_data),
	.din (ioctl_dout),
	.addr(ioctl_download ? ioctl_addr : tape_addr),
	.we( ioctl_download && ioctl_wr && (ioctl_index == 1)),
	.rd(!ioctl_download && tape_rd),

	.ready(ram_ready)
);

always @(posedge clk_sys) begin
	reg old_ready, old_reset;

	old_ready <= ram_ready;
	old_reset <= reset;

	if(~old_reset && reset) ioctl_wait <= 0;
	if(ioctl_wr && (ioctl_index == 1)) ioctl_wait <= 1;
	else if(ioctl_wait && (~old_ready & ram_ready)) ioctl_wait <= 0;
end


///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
reg         ioctl_wait = 0;
wire [10:0] ps2_key;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);


///////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////

wire [15:0] addr;
wire [7:0] 	cpu_data_out;
wire [7:0] 	cpu_data_in;

wire we;
wire irq;

cpu6502 cpu
(
	.clk(clk_sys),
	.ce(ce_1m),
	.reset(reset),
	.nmi(0),
	.irq(irq),
	.din(cpu_data_in),
	.dout(cpu_data_out),
	.addr(addr),
	.we(we)
);

///////////////////////////////////////////////////
// Commodore Pet hardware
///////////////////////////////////////////////////

wire pix;
wire HSync, VSync;
wire audioDat;

assign VGA_G = {8{pix}};
assign VGA_R = status[2] ? 3'd0 : VGA_G;
assign VGA_B = VGA_R;
assign VGA_HS = HSync;
assign VGA_VS = VSync;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_7mp;

pet2001hw hw
(
	.*,
	.clk(clk_sys),

	.data_out(cpu_data_in),
	.data_in(cpu_data_out),

	.de(VGA_DE),

	.cass_motor_n(),
	.cass_write(tape_write),
	.audio(audioDat),
	.cass_sense_n(0),
	.cass_read(tape_audio),
	.diag_l(!status[3]),

	.dma_addr(dma_off[13:0]+ioctl_addr[13:0]-2'd2),
	.dma_din(ioctl_dout),
	.dma_dout(),
	.dma_we(ioctl_wr && ioctl_download && (ioctl_index == 8'h41) && (ioctl_addr>1)),

	.clk_speed(0),
	.clk_stop(0)
);

reg [15:0] dma_off;
always @(posedge clk_sys) begin
	if(ioctl_wr && ioctl_download && (ioctl_index == 8'h41)) begin
		if(ioctl_addr == 0) dma_off[7:0]  <= ioctl_dout;
		if(ioctl_addr == 1) dma_off[15:8] <= ioctl_dout;
	end
end
 
////////////////////////////////////////////////////////////////////
// Audio 																			//
////////////////////////////////////////////////////////////////////		

wire [1:0] audio = {audioDat ^ tape_write, tape_audio & tape_active & (status[8:7] == 2)};
assign AUDIO_L = {audio, 12'd0};
assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 0;
assign AUDIO_MIX = 0;

wire        tape_audio;
wire        tape_rd;
wire [24:0] tape_addr;
wire  [7:0] tape_data;
wire        tape_pause = 0;
wire        tape_active;
wire        tape_write;

tape tape(.*, .clk(clk_sys), .ioctl_download(ioctl_download && (ioctl_index==1)));

reg [18:0] act_cnt;
wire       tape_led = act_cnt[18] ? act_cnt[17:10] <= act_cnt[7:0] : act_cnt[17:10] > act_cnt[7:0];
always @(posedge clk_sys) if((|status[8:7] ? ce_1m : ce_7mp) && (tape_active || act_cnt[18] || act_cnt[17:0])) act_cnt <= act_cnt + 1'd1; 

//////////////////////////////////////////////////////////////////////
// PS/2 to PET keyboard interface
//////////////////////////////////////////////////////////////////////
wire [7:0] 	keyin;
wire [3:0] 	keyrow;	 
wire        shift_lock;

keyboard keyboard(.*, .clk(clk_sys), .Fn(), .mod());

endmodule

module sram
(
	input        clk,

	input [15:0] addr,
	input  [7:0] din,
	input        we,
	output reg [7:0] dout
);

reg [7:0] data[65536];

always @(posedge clk) begin
	if(we) begin
		data[addr] <= din;
		dout <= din;
	end else begin
		dout <= data[addr];
	end
end

endmodule
