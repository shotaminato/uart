module uart2seg (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_rx,
    output logic o_tx,
    output logic [6:0] o_seg
);

    logic rst_n_meta;
    logic rst_n_sync;
    logic rx_meta;
    logic rx_sync;
    logic tx_meta;
    logic tx_sync;
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

    always_ff @(posedge i_clk or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            tx_sync <= 1'b1;
            o_tx    <= 1'b1;
        end else begin
            tx_sync <= tx_meta;
            o_tx    <= tx_sync;
        end
    end

    uart_rx u_uart_rx (
        .i_clk(i_clk),
        .i_rst_n(rst_n_sync),
        .i_rx(rx_sync),
        .o_rdata(o_rdata),
        .o_rvalid(o_rvalid),
        .i_rready(i_rready)
    );

    uart_tx u_uart_tx (
        .i_clk(i_clk),
        .i_rst_n(rst_n_sync),
        .o_tx(tx_meta),
        .i_wdata(o_rdata),
        .i_wvalid(o_rvalid),
        .o_wready()
    );

    char_7seg u_char_7seg (
        .i_clk(i_clk),
        .i_rst_n(rst_n_sync),
        .i_valid(o_rvalid),
        .i_char(o_rdata),
        .o_seg(o_seg),
        .o_ready(i_rready)
    );

endmodule