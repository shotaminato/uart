module uart #(
    parameter BAUD_RATE = 115200,
    parameter DATA_WIDTH = 8,
    parameter STOP_BITS = 1,
    parameter PARITY = "NONE",
    parameter CLK_FREQ_MHZ = 50
) (
    input  logic i_clk,
    input  logic i_rst_n,

    input  logic i_rx,
    output logic o_tx,

    input  logic [DATA_WIDTH-1:0] i_wdata,
    input  logic                  i_wvalid,
    output logic                  o_wready,

    output logic [DATA_WIDTH-1:0] o_rdata,
    output logic                  o_rvalid,
    input  logic                  i_rready
);

    localparam int unsigned NUM_CYCLES_PER_BIT    = CLK_FREQ_MHZ * 1_000_000 / BAUD_RATE; // about 434
    localparam int unsigned OVERSAMPLING_FACTOR   = 16;
    localparam int unsigned NUM_CYCLES_PER_SAMPLE = NUM_CYCLES_PER_BIT / OVERSAMPLING_FACTOR;

    logic [11:0] cycle_cnt;
    logic [11:0] cycle_cnt_next;

    assign cycle_cnt_next = cycle_cnt >= NUM_CYCLES_PER_SAMPLE - 1 ? 0 : cycle_cnt + 1;
    `DFF(cycle_cnt, cycle_cnt_next, 1'b1)

    logic sample_valid;
    assign sample_valid = cycle_cnt == 0;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX Sampling
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    logic rx;
    `DFF(rx, i_rx, 1'b1)

    logic rx_sampled;
    `DFF(rx_sampled, rx, sample_valid)

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX Accumulation
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    typedef enum {
        IDLE,
        START,
        RECEIVE_BIT,
        STOP
    } rx_state_t;

    rx_state_t rx_state;
    rx_state_t rx_state_next;

    logic rx_start_bit_detected;
    assign rx_start_bit_detected = rx_sampled == 0;


    logic [$clog2(OVERSAMPLING_FACTOR * (DATA_WIDTH + 2))-1:0] rx_sample_count;
    logic [$clog2(OVERSAMPLING_FACTOR * (DATA_WIDTH + 2))-1:0] rx_sample_count_next;
    assign rx_sample_count_next = (rx_state == RECEIVE_BIT) ? rx_sample_count + 1 : 2;
    `DFF(rx_sample_count, rx_sample_count_next, sample_valid)

    logic last_sample_received;
    assign last_sample_received = rx_sample_count == (OVERSAMPLING_FACTOR * (DATA_WIDTH + 2) - 1);

    assign rx_state_next = 
        (rx_state == IDLE       ) ? ((sample_valid & rx_start_bit_detected) ? START       : IDLE       ) :
        (rx_state == START      ) ? ((sampke_valid & rx_start_bit_detected) ? RECEIVE_BIT : IDLE       ) :
        (rx_state == RECEIVE_BIT) ? ((sample_valid & last_sample_received ) ? STOP        : RECEIVE_BIT) :
        (rx_state == STOP       ) ? ((sample_valid                        ) ? IDLE        : STOP       ) :
        IDLE;
    `DFF(rx_state, rx_state_next, sample_valid)

    logic                 [2:0] start_bit;
    logic                 [2:0] end_bit;
    logic [DATA_WIDTH-1:0][2:0] data_bit;

    `DFF(start_bit[0], rx, (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2 - 1)) & sample_valid);
    `DFF(start_bit[1], rx, (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2    )) & sample_valid);
    `DFF(start_bit[2], rx, (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2 + 1)) & sample_valid);

    genvar g_bit;
    for (g_bit = 0; g_bit < DATA_WIDTH + 2; g_bit++) begin : gen_rx_bit_received
        
        
        
    end





    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // FIFO
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic rx_fifo_wvalid;
    logic rx_fifo_wready;
    logic [DATA_WIDTH-1:0] rx_fifo_wdata;
    logic rx_fifo_rvalid;
    logic rx_fifo_rready;
    logic [DATA_WIDTH-1:0] rx_fifo_rdata;

    assign rx_fifo_wvalid = (rx_state == STOP & rx_bit_valid);
    assign rx_fifo_wdata  = rx_bit_received;
    assign o_rdata  = rx_fifo_rdata;
    assign o_rvalid = rx_fifo_rvalid;
    assign rx_fifo_rready = i_rready;

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






endmodule