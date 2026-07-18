module uart_tx #(
    parameter BAUD_RATE = 115200,
    parameter DATA_WIDTH = 8,
    parameter STOP_BITS = 1,
    parameter PARITY = "NONE",
    parameter CLK_FREQ_MHZ = 50
) (
    input  logic i_clk,
    input  logic i_rst_n,

    output logic o_tx,

    input  logic [DATA_WIDTH-1:0] i_wdata,
    input  logic                  i_wvalid,
    output logic                  o_wready
);

    localparam int unsigned NUM_CYCLES_PER_BIT = CLK_FREQ_MHZ * 1_000_000 / BAUD_RATE; // about 434

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // FIFO
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic rx_fifo_wvalid;
    logic rx_fifo_wready;
    logic [DATA_WIDTH-1:0] rx_fifo_wdata;
    logic rx_fifo_rvalid;
    logic rx_fifo_rready;
    logic [DATA_WIDTH-1:0] rx_fifo_rdata;

    assign rx_fifo_wvalid = i_wvalid;
    assign rx_fifo_wdata  = i_wdata;
    assign o_wready       = rx_fifo_wready;

    fifo #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(16)
    ) u_fifo (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_wvalid(rx_fifo_wvalid),
        .o_wready(rx_fifo_wready),
        .i_wdata(rx_fifo_wdata),
        .o_rvalid(rx_fifo_rvalid),
        .i_rready(rx_fifo_rready),
        .o_rdata(rx_fifo_rdata)
    );

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // UART TX
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA  = 2'b10,
        STOP  = 2'b11
    } uart_tx_state_t;
    
    uart_tx_state_t tx_state;
    uart_tx_state_t tx_state_next;

    logic [11:0] cycle_cnt;
    logic [11:0] cycle_cnt_next;
    logic bit_valid;
    logic tx_state_hold;
    logic [DATA_WIDTH-1:0] tx_data;
    logic [DATA_WIDTH-1:0] tx_bit_valid;
    logic [DATA_WIDTH-1:0] tx_bit_valid_next;

    assign cycle_cnt_next = (tx_state == IDLE) || bit_valid ? '0 : 12'(cycle_cnt + 1);
    `DFFR(cycle_cnt, cycle_cnt_next, 1'b1, i_clk, i_rst_n)

    assign bit_valid = cycle_cnt == NUM_CYCLES_PER_BIT - 1;

    assign tx_state_next = uart_tx_state_t'(
            ((tx_state == IDLE ) ? START : '0) |
            ((tx_state == START) ? DATA  : '0) |
            ((tx_state == DATA ) ? STOP  : '0) |
            ((tx_state == STOP ) ? IDLE  : '0)
        );

    assign tx_state_hold = 
        ((tx_state == IDLE ) & ~rx_fifo_rvalid) |
        ((tx_state == START) & ~bit_valid     ) |
        ((tx_state == DATA ) & ~(bit_valid & tx_bit_valid[DATA_WIDTH-1])) |
        ((tx_state == STOP ) & ~bit_valid     );

    `DFFR(tx_state, tx_state_next, ~tx_state_hold, i_clk, i_rst_n)

    assign rx_fifo_rready = (tx_state == IDLE);

    `DFFR(tx_data, rx_fifo_rdata, (tx_state == IDLE), i_clk, i_rst_n)

    assign tx_bit_valid_next = 
        (tx_state == DATA) ? (tx_bit_valid << 1) : DATA_WIDTH'(1);
    `DFFR(tx_bit_valid, tx_bit_valid_next, bit_valid, i_clk, i_rst_n)

    assign o_tx = 
        ((tx_state == IDLE ) & 1'b1                       ) |
        ((tx_state == START) & 1'b0                       ) |
        ((tx_state == DATA ) & (|(tx_bit_valid & tx_data))) |
        ((tx_state == STOP ) & 1'b1                       );



endmodule