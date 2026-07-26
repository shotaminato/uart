module uart2seg (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic i_rx,
    output logic o_tx,
    output logic [6:0] o_seg
);

    localparam int MEM_SIZE = 1024;

    logic rst_n_meta;
    logic rst_n_sync;
    logic rx_meta;
    logic rx_sync;
    logic tx_meta;
    logic tx_sync;
    logic       rx_o_rvalid;
    logic [7:0] rx_o_rdata;
    logic       rx_i_rready;

    logic       tx_i_wvalid;
    logic [7:0] tx_i_wdata;
    logic       tx_o_wready;

    logic [7:0] mem [MEM_SIZE];

    logic [$clog2(MEM_SIZE):0] mem_ptr;
    logic [$clog2(MEM_SIZE):0] mem_ptr_next;
    logic mem_valid;

    initial begin
        $readmemb("../dv/bin/input.bin", mem);
    end

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
        .i_clk   (i_clk),
        .i_rst_n (rst_n_sync),
        .i_rx    (rx_sync),
        .o_rdata (rx_o_rdata),
        .o_rvalid(rx_o_rvalid),
        .i_rready(rx_i_rready)
    );

    assign mem_valid = mem_ptr < MEM_SIZE;

    assign tx_i_wvalid = mem_valid | rx_o_rvalid;
    assign tx_i_wdata  = mem_valid ? mem[mem_ptr] : rx_o_rdata;

    assign mem_ptr_next = mem_valid & tx_o_wready ? mem_ptr + 1 : mem_ptr;

    `DFFR(mem_ptr, mem_ptr_next, 1'b1, i_clk, rst_n_sync)

    uart_tx u_uart_tx (
        .i_clk   (i_clk),
        .i_rst_n (rst_n_sync),
        .o_tx    (tx_meta),
        .i_wdata (tx_i_wdata),
        .i_wvalid(tx_i_wvalid),
        .o_wready(tx_o_wready)
    );

    char_7seg u_char_7seg (
        .i_clk  (i_clk),
        .i_rst_n(rst_n_sync ),
        .i_valid(rx_o_rvalid),
        .i_char (rx_o_rdata ),
        .o_seg  (o_seg      ),
        .o_ready(rx_i_rready)
    );

endmodule