module uart2seg (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_rx,
    // output logic o_tx,
    output logic [6:0] o_seg
);

    logic rst_n_meta;
    logic rst_n_sync;
    logic rx_meta;
    logic rx_sync;
    logic       o_rvalid;
    logic [7:0] o_rdata;
    logic       i_rready;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rst_n_meta <= 1'b0;
            rst_n_sync <= 1'b0;
        end else begin
            rst_n_meta <= 1'b1;
            rst_n_sync <= rst_n_meta;
        end
    end

    always_ff @(posedge i_clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= i_rx;
            rx_sync <= rx_meta;
        end
    end

    uart u_uart (
        .i_clk(i_clk),
        .i_rst_n(rst_n_sync),
        .i_rx(rx_sync),
        .o_tx(o_tx),
        .o_rdata(o_rdata),
        .o_rvalid(o_rvalid),
        .i_rready(i_rready)
    );

    char_7seg u_char_7seg (
        .i_clk(i_clk),
        .i_rst_n(rst_n_sync),
        .i_valid(o_rvalid),
        .i_char(o_rdata),
        .o_seg(o_seg),
        .o_ready(i_rready)
    );

    // logic [31:0] cycle_cnt;
    // logic [31:0] cycle_cnt_next;
    // assign cycle_cnt_next = cycle_cnt < 100_000_000_000 ? cycle_cnt + 1 : 0;
    // `DFF(cycle_cnt, cycle_cnt_next, 1'b1)


    // logic [7:0] o_rdata_next;

    // assign o_rdata_next = (o_rdata < 8'h30 + 9) & (o_rdata >= 8'h30) ? o_rdata + 1 : 8'h30;
    // assign o_rvalid = cycle_cnt % 50_000_000 == 0;
    // `DFF(o_rdata, o_rdata_next, o_rvalid)


    // logic [6:0] o_seg_next;

    // assign o_seg_next = o_seg == 7'b0 ? 7'b0000001 : {o_seg[5:0], o_seg[6]};
    // `DFF(o_seg, o_seg_next, cycle_cnt % 50_000_000 == 0)

endmodule