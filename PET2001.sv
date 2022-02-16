//============================================================================
//  PET2001
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//	Extension to Basic v4, 32KB RAM and Loader fix by raparici
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
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
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
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_USER  = tape_led | ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign HDMI_FREEZE = 0;

wire [1:0] ar = status[12:11];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[14:13])
);

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
	"OBC,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O46,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"ODE,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"-;",
	"R0,Reset;",
	"V,v",`BUILD_DATE
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
	integer   initRESET = 10000000;
	reg [3:0] reset_cnt;

	if ((!(RESET | status[0] | buttons[1]) && reset_cnt==4'd14) && !initRESET)
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
wire [6:0] cpu_rates[4] = '{55, 27, 13, 6};

always @(posedge clk_sys) begin
	reg  [2:0] div = 0;
	reg  [6:0] cpu_div = 0;
	reg  [6:0] cpu_rate = 55;

	div <= div + 1'd1;
	ce_7mp  <= !div[2] & !div[1:0];
	ce_7mn  <=  div[2] & !div[1:0];
	
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
wire        forced_scandoubler;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
   .forced_scandoubler(forced_scandoubler),

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
wire  [7:0] cpu_data_out;
wire  [7:0] cpu_data_in;
wire        rnw;

wire we = ~rnw;
wire irq;

T65 cpu
(
    .Mode(0),
    .Res_n(~reset),
    .Enable(ce_1m),
    .Clk(clk_sys),
    .Rdy(1),
    .Abort_n(1),
    .IRQ_n(~irq),
    .NMI_n(1),
    .SO_n(1),
    .R_W_n(rnw),
    .A(addr),
    .DI(cpu_data_in),
    .DO(cpu_data_out)
);


///////////////////////////////////////////////////
// Commodore Pet hardware
///////////////////////////////////////////////////

wire pix;
wire HSync, VSync;
wire audioDat;

assign CLK_VIDEO = clk_sys;
wire HBlank, VBlank;

pet2001hw hw
(
	.*,
	.clk(clk_sys),

	.data_out(cpu_data_in),
	.data_in(cpu_data_out),

	.cass_motor_n(),
	.cass_write(tape_write),
	.audio(audioDat),
	.cass_sense_n(0),
	.cass_read(tape_audio),
	.diag_l(!status[3]),

	.dma_addr(dl_addr),
	.dma_din(dl_data),
	.dma_dout(),
	.dma_we(dl_wr),

	.clk_speed(0),
	.clk_stop(0)
);


////////////////////////////////////////////////////////////////////
// Loading
////////////////////////////////////////////////////////////////////

reg  [15:0] dl_addr;
reg   [7:0] dl_data;
reg         dl_wr;

always @(posedge clk_sys) begin
	reg        old_download = 0;
	reg  [3:0] state = 0;
	reg [15:0] addr;

	dl_wr <= 0;
	old_download <= ioctl_download;

	if(ioctl_download && (ioctl_index == 8'h41)) begin
		state <= 0;
		if(ioctl_wr) begin  
			     if(ioctl_addr == 0) addr[7:0]  <= ioctl_dout;
			else if(ioctl_addr == 1) addr[15:8] <= ioctl_dout;
			else begin
				if(addr<'h8000) begin
					dl_addr <= addr;
					dl_data <= ioctl_dout;
					dl_wr   <= 1;
					addr    <= addr + 1'd1;
				end
			end
		end
	end

	if(old_download && ~ioctl_download && (ioctl_index == 8'h41)) state <= 1;
	if(state) state <= state + 1'd1;

	case(state)
		 1: begin dl_addr <= 16'h2a; dl_data <= addr[7:0];  dl_wr <= 1; end
		 3: begin dl_addr <= 16'h2b; dl_data <= addr[15:8]; dl_wr <= 1; end
	endcase
	
	if(ioctl_download && !ioctl_index) begin
		state <= 0;
		if(ioctl_wr) begin
			if(ioctl_addr>='h0400 && ioctl_addr<'h8000) begin
				dl_addr <= ioctl_addr[15:0] + 16'h8000;
				dl_data <= ioctl_dout;
				dl_wr   <= 1;
			end
		end
	end
end

wire [2:0] scale = status[6:4];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0; 
assign VGA_SL = sl[1:0];
assign VGA_F1 = 0;


////////////////////////////////////////////////////////////////////
// Video
////////////////////////////////////////////////////////////////////	

video_mixer #(.HALF_DEPTH(1)) video_mixer
(
	.*,
	.ce_pix(ce_7mp),
	
	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),
	.gamma_bus(),
	.freeze_sync(),

	.R({4{~status[2] & pix}}),
	.G({4{pix}}),
	.B({4{~status[2] & pix}})
);

 
////////////////////////////////////////////////////////////////////
// Audio
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
