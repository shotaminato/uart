// AXI4-Lite slave (one outstanding read, one outstanding write).
// AW/W may arrive in either order or in the same cycle. B/R are registered
// (valid the cycle after the request is accepted).
//
// Register-file interface:
//   o_wr_valid  1-cycle pulse when both AW and W have been accepted
//   o_rd_valid  1-cycle pulse on the AR handshake
//   i_wr_resp / i_rd_data / i_rd_resp are sampled in that same cycle
//
// Responses: the register file supplies AXI resp[1:0]
//   2'b00 OKAY, 2'b10 SLVERR, 2'b11 DECERR

module axil_slave #(
    parameter int unsigned ADDR_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  logic                     i_clk,
    input  logic                     i_rst_n,

    input  logic [ADDR_WIDTH-1:0]    i_awaddr,
    input  logic [2:0]               i_awprot,
    input  logic                     i_awvalid,
    output logic                     o_awready,

    input  logic [DATA_WIDTH-1:0]    i_wdata,
    input  logic [DATA_WIDTH/8-1:0]  i_wstrb,
    input  logic                     i_wvalid,
    output logic                     o_wready,

    output logic [1:0]               o_bresp,
    output logic                     o_bvalid,
    input  logic                     i_bready,

    input  logic [ADDR_WIDTH-1:0]    i_araddr,
    input  logic [2:0]               i_arprot,
    input  logic                     i_arvalid,
    output logic                     o_arready,

    output logic [DATA_WIDTH-1:0]    o_rdata,
    output logic [1:0]               o_rresp,
    output logic                     o_rvalid,
    input  logic                     i_rready,

    output logic                     o_wr_valid,
    output logic [ADDR_WIDTH-1:0]    o_wr_addr,
    output logic [DATA_WIDTH-1:0]    o_wr_data,
    output logic [DATA_WIDTH/8-1:0]  o_wr_strb,
    input  logic [1:0]               i_wr_resp,

    output logic                     o_rd_valid,
    output logic [ADDR_WIDTH-1:0]    o_rd_addr,
    input  logic [DATA_WIDTH-1:0]    i_rd_data,
    input  logic [1:0]               i_rd_resp
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic unused_prot;
    assign unused_prot = |{i_awprot, i_arprot};

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Write channel
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic                    aw_pend;
    logic                    w_pend;
    logic                    b_pend;
    logic [ADDR_WIDTH-1:0]   awaddr_q;
    logic [DATA_WIDTH-1:0]   wdata_q;
    logic [STRB_WIDTH-1:0]   wstrb_q;
    logic [1:0]              bresp_q;

    logic aw_hs;
    logic w_hs;
    logic b_hs;
    logic wr_issue;

    logic                    aw_pend_next;
    logic                    w_pend_next;
    logic                    b_pend_next;

    assign o_awready = ~aw_pend & ~b_pend;
    assign o_wready  = ~w_pend  & ~b_pend;

    assign aw_hs = i_awvalid & o_awready;
    assign w_hs  = i_wvalid  & o_wready;
    assign b_hs  = o_bvalid  & i_bready;

    assign wr_issue = (aw_pend | aw_hs) & (w_pend | w_hs);

    assign aw_pend_next = (aw_pend | aw_hs) & ~wr_issue;
    assign w_pend_next  = (w_pend  | w_hs ) & ~wr_issue;
    assign b_pend_next  = wr_issue | (b_pend & ~b_hs);

    `DFFR(aw_pend, aw_pend_next, 1'b1, i_clk, i_rst_n)
    `DFFR(w_pend,  w_pend_next,  1'b1, i_clk, i_rst_n)
    `DFFR(b_pend,  b_pend_next,  1'b1, i_clk, i_rst_n)

    `DFFR(awaddr_q, i_awaddr, aw_hs, i_clk, i_rst_n)
    `DFFR(wdata_q,  i_wdata,  w_hs,  i_clk, i_rst_n)
    `DFFR(wstrb_q,  i_wstrb,  w_hs,  i_clk, i_rst_n)
    `DFFR(bresp_q,  i_wr_resp, wr_issue, i_clk, i_rst_n)

    assign o_wr_valid = wr_issue;
    assign o_wr_addr  = aw_pend ? awaddr_q : i_awaddr;
    assign o_wr_data  = w_pend  ? wdata_q  : i_wdata;
    assign o_wr_strb  = w_pend  ? wstrb_q  : i_wstrb;

    assign o_bvalid = b_pend;
    assign o_bresp  = bresp_q;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Read channel
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic                    r_pend;
    logic                    r_pend_next;
    logic                    ar_hs;
    logic                    r_hs;
    logic [DATA_WIDTH-1:0]   rdata_q;
    logic [1:0]              rresp_q;

    assign o_arready = ~r_pend;
    assign ar_hs     = i_arvalid & o_arready;
    assign r_hs      = o_rvalid  & i_rready;

    assign r_pend_next = ar_hs | (r_pend & ~r_hs);

    `DFFR(r_pend,  r_pend_next, 1'b1, i_clk, i_rst_n)
    `DFFR(rdata_q, i_rd_data,   ar_hs, i_clk, i_rst_n)
    `DFFR(rresp_q, i_rd_resp,   ar_hs, i_clk, i_rst_n)

    assign o_rd_valid = ar_hs;
    assign o_rd_addr  = i_araddr;

    assign o_rvalid = r_pend;
    assign o_rdata  = rdata_q;
    assign o_rresp  = rresp_q;

endmodule
