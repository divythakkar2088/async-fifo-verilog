// distributed under the mit license
// https://opensource.org/licenses/mit-license.php

`timescale 1 ns / 1 ps
`default_nettype none

module wptr_full

	#(
		parameter ADDRSIZE = 4
	)(
		input  wire                wclk,
		input  wire                wrst_n,
		input  wire                winc,
		input  wire [ADDRSIZE  :0] wq2_rptr, // Gray-coded read pointer, synchronized into the write clock domain
		output reg                 wfull,
		output reg                 awfull,
		output wire [ADDRSIZE-1:0] waddr,
		output reg  [ADDRSIZE  :0] wptr  // Gray-coded write pointer (in the write clock domain
	);

    reg  [ADDRSIZE:0] wbin;  // Current Binary Write Pointer
    wire [ADDRSIZE:0] wgraynext, wbinnext, wgraynextp1;
    wire              awfull_val, wfull_val;

	// GRAYSTYLE2 pointer
	always @(posedge wclk or negedge wrst_n) begin

		if (!wrst_n)
			{wbin, wptr} <= 0;
		else
			{wbin, wptr} <= {wbinnext, wgraynext};

	end

    // Memory write-address pointer (okay to use binary to address memory)
    assign waddr = wbin[ADDRSIZE-1:0];
    assign wbinnext  = wbin + ((winc & ~wfull) ? 1 : 0);
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;
    assign wgraynextp1 = ((wbinnext + 1'b1) >> 1) ^ (wbinnext + 1'b1);  // Next+1 Gray write pointer for almost-full detection

    //------------------------------------------------------------------
    // Simplified version of the three necessary full-tests:
    // assign wfull_val=((wgnext[ADDRSIZE] !=wq2_rptr[ADDRSIZE] ) &&
    //                   (wgnext[ADDRSIZE-1]  !=wq2_rptr[ADDRSIZE-1]) &&
    // (wgnext[ADDRSIZE-2:0]==wq2_rptr[ADDRSIZE-2:0]));
    //------------------------------------------------------------------


    //Example :rptr = binary 3 (011) → gray = 010
    //Full at wptr = 3+4 = 7 (111) → gray = 100
    //g(rptr) = 0 1 0
    //g(wptr) = 1 0 0
    //          ^ ^
    //        flip flip, bit0 same

     assign wfull_val = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1],wq2_rptr[ADDRSIZE-2:0]});
     assign awfull_val = (wgraynextp1 == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1],wq2_rptr[ADDRSIZE-2:0]});

     always @(posedge wclk or negedge wrst_n) begin
     

        if (!wrst_n) begin
            awfull <= 1'b0;
            wfull  <= 1'b0;
        end else begin
            awfull <= awfull_val;
            wfull  <= wfull_val;
        end
    end

endmodule

`resetall
