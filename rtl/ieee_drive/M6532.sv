// k7800 (c) by Jamie Blanks

// k7800 is licensed under a
// Creative Commons Attribution-NonCommercial 4.0 International License.

// You should have received a copy of the license along with this
// work. If not, see http://creativecommons.org/licenses/by-nc/4.0/.

// Extended to add 6530 RRIOT variant (without ROM) by Erik Scheffers for MiSTer FPGA CBM-II core

module M6532 #(parameter RRIOT=0)
(
	input        clk,       // PHI 2
	input        ce,        // Clock enable
	input        res_n,     // reset
	input  [6:0] addr,      // Address
	input        RW_n,      // 1 = read, 0 = write
	input  [7:0] d_in,
	output [7:0] d_out,
	input        IOS_n,     // I/O select (RRIOT only)
	input        RS_n,      // RAM select
	output       IRQ_n,
	input        CS1,       // Chip select 1, 1 = selected
	input        CS2_n,     // Chip select 2, 0 = selected
	input  [7:0] PA_in,     // Port ins and outs
	output [7:0] PA_out,    // NOTE that port output must be fed back to input
	input  [7:0] PB_in,     // if not altered by a peripheral, in order for
	output [7:0] PB_out,    // the chip to read properly!
	output       oe         // Output enabled (always 8 bits)
);

localparam RAMSIZE = RRIOT ? 64 : 128;

reg [7:0] riot_ram[RAMSIZE];
reg [7:0] out_a, out_b, data;
reg [7:0] dir_a, dir_b;
reg [7:0] interrupt;
reg [7:0] timer;
reg [9:0] prescaler;

reg [1:0] incr;
logic rollover;
reg [1:0] irq_en;
reg edge_detect;

assign IRQ_n = ~((interrupt[7] & irq_en[1]) | (!RRIOT & interrupt[6] & irq_en[0]));

// These wires have a weak pull up, so any undriven wires will be high
assign PA_out      = out_a | ~dir_a;
assign PB_out[6:0] = out_b[6:0] | ~dir_b[6:0];
assign PB_out[7]   = (out_b[7] | ~dir_b[7]) & (!RRIOT | IRQ_n | dir_b[7]);

assign oe = (CS1 & ~CS2_n) && RW_n;
always_ff @(posedge clk) begin
	if ((CS1 & ~CS2_n) && RW_n) begin
		if (~RS_n) begin // RAM selected
			d_out <= riot_ram[addr];
		end else if (!(RRIOT && IOS_n))
			if (~addr[2]) begin // Address registers
				case(addr[1:0])
					2'b01: d_out <= dir_a; // DDRA
					2'b11: d_out <= dir_b; // DDRB
					2'b00: d_out <= (PA_in & PA_out); // Input A
					2'b10: d_out <= (PB_in & PB_out); // Input B
				endcase
			end else begin // Timer & Interrupts
				if (~addr[0])
					d_out <= timer[7:0];
				else
					d_out <= {interrupt[7:6], 6'd0};
			end
		end

	if (~res_n)
		d_out <= 8'hFF;
end

wire pa7 = dir_a[7] ? PA_out[7] : PA_in[7];
wire p1 = incr == 2'd0 || rollover;
wire p8 = ~|prescaler[2:0] && incr == 2'd1;
wire p64 = ~|prescaler[5:0] && incr == 2'd2;
wire p1024 = ~|prescaler[9:0] && incr == 2'd3;
wire tick_inc = p1 || p8 || p64 || p1024;

always_ff @(posedge clk) if (~res_n) begin
	riot_ram <= '{RAMSIZE{8'h00}};
	out_a <= 8'h00;
	out_b <= 8'h00;
	dir_a <= 8'h00;
	dir_b <= 8'h00;
	{interrupt, irq_en, edge_detect} <= '0;
	incr <= 2'b10; // Increment resets to 64
	timer <= 8'hFF;   // Timer resets to FF
	prescaler <= 0;
	rollover <= 0;
end else begin

	if (ce) begin : riot_stuff
		reg old_pa7;

		prescaler <= prescaler + 1'd1;

		if (tick_inc)
			timer <= timer - 8'd1;

		if (CS1 & ~CS2_n) begin
			if (~RS_n) begin // RAM selected
				if (~RW_n)
					riot_ram[addr] <= d_in;
			end
			else if (!(RRIOT && IOS_n))
				if (~addr[2]) begin // Address registers
					if (~RW_n) begin
						case(addr[1:0])
							2'b01: dir_a <= d_in; // DDRA
							2'b11: dir_b <= d_in; // DDRB
							2'b00: out_a <= d_in; // Output A
							2'b10: out_b <= d_in; // Output B
						endcase
					end
				end else begin // Timer & Interrupts
					if (~RW_n) begin
						if (addr[4] || RRIOT) begin
							prescaler <= 10'd0;
							rollover <= 0;
							interrupt[7] <= 0;
							incr <= addr[1:0];
							timer <= d_in;
							irq_en[1] <= addr[3];
						end else begin
							irq_en[0] <= addr[1];
							edge_detect <= addr[0];
						end
					end else begin
						if (~addr[0]) begin
							irq_en[1] <= addr[3];
							rollover <= 0;
							interrupt[7] <= 0;
						end else if (!RRIOT)
							interrupt[6] <= 0;
					end
				end
		end

		if (tick_inc && timer == 0) begin
			interrupt[7] <= 1;
			rollover <= 1;
		end

		// Edge detection
		if (!RRIOT) begin
			old_pa7 <= pa7;
			if ((edge_detect && ~old_pa7 && pa7) || (~edge_detect && old_pa7 && ~pa7))
				interrupt[6] <= 1;
		end
	end
end

endmodule