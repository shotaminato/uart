module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 16
) (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic             i_wvalid,
    output logic             o_wready, // not full
    input  logic [WIDTH-1:0] i_wdata,

    output logic             o_rvalid, // not empty
    input  logic             i_rready,
    output logic [WIDTH-1:0] o_rdata
);

    logic [WIDTH-1:0] mem [DEPTH];
    genvar gi;
    logic [$clog2(DEPTH)-1:0] wr_ptr;
    logic [$clog2(DEPTH)-1:0] rd_ptr;
    logic [$clog2(DEPTH)-1:0] wr_ptr_next;
    logic [$clog2(DEPTH)-1:0] rd_ptr_next;

    logic [$clog2(DEPTH):0] count;
    logic [$clog2(DEPTH):0] count_next;

    assign count_next = count + i_wvalid - (i_rready & o_rvalid);
    `DFFR(count, count_next, 1'b1, i_clk, i_rst_n)

    assign wr_ptr_next = $clog2(DEPTH)'((wr_ptr == DEPTH - 1) ? '0 : wr_ptr + 1);
    `DFFR(wr_ptr, wr_ptr_next, (i_wvalid & o_wready), i_clk, i_rst_n)
	 
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : gen_mem
            `DFFR(mem[gi], (wr_ptr == gi) ? i_wdata : mem[gi], (wr_ptr == gi) & i_wvalid, i_clk, i_rst_n)
        end
    endgenerate

    assign o_rdata = mem[rd_ptr];
    assign o_rvalid = count > 0;
    assign o_wready = (count < DEPTH);

    assign rd_ptr_next = $clog2(DEPTH)'((rd_ptr == DEPTH - 1) ? '0 : rd_ptr + 1);
    `DFFR(rd_ptr, rd_ptr_next, i_rready & o_rvalid, i_clk, i_rst_n)

endmodule
