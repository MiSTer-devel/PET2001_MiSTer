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

module ieeedrv_trkgen #(parameter SUBDRV=2)
(
   input      [31:0] CLK,

	input             clk_sys,
	input             reset,

	input             drv_type,
	input       [1:0] img_type,

	input             halt,
	input             invalid,
	input             drv_act,
	input             drv_hd,
	input             mtr,
	input       [1:0] freq,

	input       [7:0] track,
	input      [15:0] id,
	output     [15:0] id_hdr,
	output            id_wr,
	input             wprot,
	output reg        we,

	input             rw,
	output            byte_n,
	output            brdy_n,
	output            error,

	output            sync_rd_n,
	output      [7:0] byte_rd,

	input             sync_wr,
	input       [7:0] byte_wr,

	input             loaded,
	input             sd_clk,
	input      [12:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din,
	input             sd_buff_wr
);

wire [4:0] sector_max = drv_type ? (
									(track < 18) ? 5'd20 :
									(track < 25) ? 5'd18 :
									(track < 31) ? 5'd17 :
														5'd16
								) : (
									(track <  40) ? 5'd28 :
									(track <  54) ? 5'd26 :
									(track <  65) ? 5'd24 :
  									(track <  78) ? 5'd22 :
									(track < 117) ? 5'd28 :
									(track < 131) ? 5'd26 :
									(track < 142) ? 5'd24 :
  									                5'd22
								);

wire [8:0] SYNC_SIZE = 9'd3;
wire [8:0] GAP1 = 9'(drv_type ? 9 : 20);
wire [8:0] GAP2 = drv_type ? (
							9'd2
						) : (
							(track <  40) ? 9'd25 :
							(track <  54) ? 9'd24 :
							(track <  65) ? 9'd27 :
							(track <  78) ? 9'd33 :
							(track < 117) ? 9'd25 :
							(track < 131) ? 9'd24 :
							(track < 142) ? 9'd27 :
												 9'd33
						);
wire [8:0] GAP3 = drv_type ? (
							9'd28
						) : (
							(track <  40) ? 9'd37 :
							(track <  54) ? 9'd39 :
							(track <  65) ? 9'd25 :
							(track <  78) ? 9'd25 :
							(track < 117) ? 9'd37 :
							(track < 131) ? 9'd39 :
							(track < 142) ? 9'd25 :
												 9'd25
						);

wire [8:0] SECTORLEN = 9'(SYNC_SIZE + 1 + 5 + GAP1 + 1 + SYNC_SIZE + 1 + 256 + 1 + GAP2);

localparam HEADER_SYNC_CODE = 8'h08;
localparam DATA_SYNC_CODE   = 8'h07;
localparam TEST_SYNC_CODE   = 8'h0F;

reg bit_clk_en;
always @(posedge clk_sys) begin
	int       sum = 0;

	reg [3:0] bit_clk_cnt;
	reg       rw_r;

	bit_clk_en <= 0;

	sum = sum + (drv_type ? 4_000_000 : 6_000_000);
	if (sum >= CLK) begin
		sum = sum - CLK;

		rw_r <= rw;
		if (rw_r != rw || !mtr)
			bit_clk_cnt <= 4'(freq);
		else if (!halt) begin
			bit_clk_cnt <= bit_clk_cnt + 1'b1;

			if (&bit_clk_cnt) begin
				bit_clk_en <= 1;
				bit_clk_cnt <= 4'(freq);
			end
		end
	end
end

ieeedrv_mem #(8,13) buffer
(
	.clock_a(sd_clk),
	.address_a(sd_buff_addr),
	.data_a(sd_buff_dout),
	.wren_a(sd_buff_wr),
	.q_a(sd_buff_din),

	.clock_b(clk_sys),
	.address_b({sector[drv_act], buff_addr}),
	.data_b(buff_di),
	.wren_b(we),
	.q_b(buff_do)
);

reg trk_reset, trk_reset_ack;
always @(posedge clk_sys) begin
	reg       drv_act_l;
	reg [7:0] track_l;

	drv_act_l <= drv_act;
	track_l   <= track;

	if (reset || !loaded || img_type[1] != drv_type || (!img_type[0] && drv_hd) || drv_act != drv_act_l || track != track_l)
		trk_reset <= 1;
	else if (trk_reset_ack)
		trk_reset <= 0;
end

reg  [7:0] buff_addr;
wire [7:0] buff_do;
reg  [7:0] buff_di;

reg  [4:0] sector[SUBDRV];

typedef enum bit[3:0] {RW_RESET, RW_IDLE, R_SYNCHDR, R_SYNCDATA, R_SYNCTEST, R_HEADER, R_DATA, R_TAIL, R_TEST, W_SYNC, W_HEADER, W_DATA} rwState_t;

always @(posedge clk_sys) begin
	reg [3:0] bit_cnt;
	reg [8:0] byte_cnt;
	reg [2:0] hdr_cnt;
	reg [7:0] chk;
	reg [7:0] old_track;
	reg       rw_l;

	rwState_t rwState = RW_RESET;

	buff_di <= 8'h00;
	we <= 0;
	id_wr <= 0;

	if (bit_clk_en) begin
		bit_cnt <= bit_cnt + 1'b1;
		brdy_n  <= 1;
		byte_n  <= 1;

		if (sync_rd_n) begin
			if (bit_cnt == 0) brdy_n <= 0;
			if (bit_cnt == 1) byte_n <= 0;
		end

		if (bit_cnt == 9) begin
			bit_cnt   <= 0;
			byte_rd   <= 8'h0f;
			sync_rd_n <= 1;
			error     <= 0;
			old_track <= track;
			rw_l      <= rw;

			if (~&byte_cnt || rwState == RW_IDLE)
				byte_cnt <= byte_cnt + 1'b1;

			trk_reset_ack <= trk_reset;

			case(rwState)
				RW_RESET:
					begin
						buff_addr <= 0;
						chk       <= 0;
						error     <= 1;

						if (!trk_reset)
							rwState <= RW_IDLE;
					end

				RW_IDLE: 
					begin
						buff_addr <= 0;
						chk       <= 0;

						if (sector[drv_act] > sector_max)
							sector[drv_act] <= 0;

						if (trk_reset)
							rwState <= RW_RESET;
						else begin
							if (rw) begin
								byte_cnt <= 0;
								rwState <= R_SYNCHDR;
							end
							else if (sync_wr && !wprot) begin
								byte_cnt <= 0;
								rwState  <= W_SYNC;
							end
						end
					end

				R_SYNCHDR, R_SYNCDATA, R_SYNCTEST:
					begin
						buff_addr <= 0;
						chk       <= 0;

						if (!rw || trk_reset) begin
							byte_cnt <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else if (byte_cnt < SYNC_SIZE) begin
							sync_rd_n <= 0;
							byte_rd   <= 8'h42;
						end
						else begin
							byte_cnt <= 0;
							case(rwState)
								R_SYNCHDR:
									begin 
										rwState <= R_HEADER;
										byte_rd <= HEADER_SYNC_CODE;
									end
								R_SYNCDATA:
									begin 
										rwState <= R_DATA;
										byte_rd <= DATA_SYNC_CODE;
									end
								R_SYNCTEST:
									begin 
										rwState <= R_TEST;
										byte_rd <= drv_type ? TEST_SYNC_CODE : 8'h00;
										sector[drv_act] <= 0;
									end
								default: 
									rwState <= RW_IDLE;
							endcase
						end
					end

				R_HEADER:
					begin
						buff_addr <= 0;
						chk <= 0;

						if (!rw || trk_reset) begin
							byte_cnt <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else 
							case(byte_cnt)
								0: byte_rd <= sector[drv_act] ^ track ^ id[15:8] ^ id[7:0];
								1: byte_rd <= sector[drv_act];
								2: byte_rd <= track;
								3: byte_rd <= id[15:8];
								4: byte_rd <= id[7:0];
								default: 
									begin
										byte_rd <= 8'h00;
										if (byte_cnt == 4+GAP1) begin
											byte_cnt <= 0;
											rwState  <= R_SYNCDATA;
										end
									end
							endcase
					end

				R_DATA:
					begin
						buff_addr <= buff_addr + 1'b1;
						chk       <= chk ^ buff_do;
						byte_rd   <= buff_do;

						if (!rw || trk_reset) begin
							buff_addr <= 0;
							chk       <= 0;
							byte_cnt  <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else if (byte_cnt == 'hFF) begin
							buff_addr <= 0;
							byte_cnt  <= 0;
							rwState   <= R_TAIL;
						end
					end

				R_TAIL:
					begin
						buff_addr <= 0;
						chk       <= 0;
						byte_rd   <= chk;

						if ((rw_l && !rw) || (!rw && sync_wr && !wprot) || trk_reset) begin
							byte_cnt <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else if ((sector[drv_act] < sector_max && byte_cnt == GAP2-1) || byte_cnt == (GAP2+GAP3-1)) begin
							byte_cnt <= 0;
							sector[drv_act] <= sector[drv_act] + 1'b1;
							rwState <= RW_IDLE;
						end
					end

				R_TEST:
					begin
						buff_addr <= 0;
						chk       <= 0;
						byte_rd   <= 8'h00;

						if ((rw_l && !rw) || (!rw && sync_wr && !wprot) || track != old_track || trk_reset) begin
							byte_cnt <= 0;
							sector[drv_act] <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else if (byte_cnt == SECTORLEN && sector[drv_act] <= sector_max) begin
							byte_cnt <= 0;
							sector[drv_act] <= sector[drv_act] + 1'b1;
						end
						else if (byte_cnt == GAP3 && sector[drv_act] > sector_max) begin
							byte_cnt <= 0;
							sector[drv_act] <= 0;
							rwState <= R_SYNCTEST;
						end
					end

				W_SYNC:
					begin
						buff_addr <= 0;
						chk       <= 0;

						if (wprot || trk_reset) begin
							byte_cnt <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else
								rwState <= RW_IDLE;
						end
						else if (!sync_wr || rw) begin
							byte_cnt <= 0;

							if (rw || byte_wr == TEST_SYNC_CODE) begin
								rwState <= R_TEST;
								sector[drv_act] <= 0;
							end
							else if (byte_wr == HEADER_SYNC_CODE)
								rwState <= W_HEADER;
							else if (byte_wr == DATA_SYNC_CODE)
								rwState <= W_DATA;
							else
								rwState <= RW_IDLE;
						end
					end

				W_HEADER:
					begin
						buff_addr <= 0;
						chk       <= 0;

						if (rw || wprot || trk_reset || sync_wr) begin
							byte_cnt <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= RW_IDLE;
						end
						else
							case(byte_cnt)
								1: sector[drv_act] <= byte_wr[4:0];
								3: id_hdr[15:8] <= byte_wr;
								4: begin
										byte_cnt	   <= 0;
										id_hdr[7:0] <= byte_wr;
										id_wr       <= 1;
										rwState     <= RW_IDLE;
									end
								default: ;
							endcase
					end

				W_DATA:
					begin
						chk <= 0;

						if (rw || wprot || trk_reset || sync_wr || byte_cnt[8]) begin
							buff_addr <= 0;
							byte_cnt  <= 0;

							if (trk_reset)
								rwState <= RW_RESET;
							else if (!rw && sync_wr && !wprot)
								rwState <= W_SYNC;
							else
								rwState <= R_TAIL;
						end
						else begin
							buff_addr <= 8'((byte_cnt == 0) ? 0 : buff_addr + 1);
							buff_di   <= byte_wr;
							we        <= 1;
						end
					end
			endcase

			if (invalid) begin
				error     <= 1;
				byte_rd   <= 8'h0f;
				sync_rd_n <= 1;
				we        <= 0;
			end
		end
	end
end

endmodule
