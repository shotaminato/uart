module uart_rx #(
    parameter BAUD_RATE = 115200,
    parameter DATA_WIDTH = 8,
    parameter STOP_BITS = 1,
    parameter PARITY = "NONE",
    parameter CLK_FREQ_MHZ = 50
) (
    input  logic i_clk,
    input  logic i_rst_n,

    input  logic i_rx,

    output logic [DATA_WIDTH-1:0] o_rdata,
    output logic                  o_rvalid,
    input  logic                  i_rready
);

    localparam int unsigned NUM_CYCLES_PER_BIT    = CLK_FREQ_MHZ * 1_000_000 / BAUD_RATE; // about 434
    localparam int unsigned OVERSAMPLING_FACTOR   = 16;
    localparam int unsigned NUM_CYCLES_PER_SAMPLE = NUM_CYCLES_PER_BIT / OVERSAMPLING_FACTOR;

    logic [11:0] cycle_cnt;
    logic [11:0] cycle_cnt_next;

    assign cycle_cnt_next = cycle_cnt >= NUM_CYCLES_PER_SAMPLE - 1 ? '0 : 12'(cycle_cnt + 1);
    `DFFR(cycle_cnt, cycle_cnt_next, 1'b1, i_clk, i_rst_n)

    logic sample_valid;
    assign sample_valid = cycle_cnt == 0;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX Sampling
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    logic rx;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx <= 1'b1;
        end else begin
            rx <= i_rx;
        end
    end

    logic rx_sampled;
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_sampled <= 1'b1;
        end else if (sample_valid) begin
            rx_sampled <= rx;
        end
    end

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX State Machine
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
    assign rx_sample_count_next = $clog2(OVERSAMPLING_FACTOR * (DATA_WIDTH + 2))'((rx_state == RECEIVE_BIT) ? rx_sample_count + 1 : 2);
    `DFFR(rx_sample_count, rx_sample_count_next, sample_valid, i_clk, i_rst_n)

    logic last_sample_received;
    assign last_sample_received = rx_sample_count == (OVERSAMPLING_FACTOR * (DATA_WIDTH + 2) - 1);

    assign rx_state_next = 
        (rx_state == IDLE       ) ? ((sample_valid & rx_start_bit_detected) ? START       : IDLE       ) :
        (rx_state == START      ) ? ((sample_valid & rx_start_bit_detected) ? RECEIVE_BIT : IDLE       ) :
        (rx_state == RECEIVE_BIT) ? ((sample_valid & last_sample_received ) ? STOP        : RECEIVE_BIT) :
        (rx_state == STOP       ) ? IDLE                                                                 : 
        IDLE;
    `DFFR(rx_state, rx_state_next, sample_valid, i_clk, i_rst_n)

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX Bit Received
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    logic                 [2:0] start_bit;
    logic                 [2:0] end_bit  ;
    logic [DATA_WIDTH-1:0][2:0] data_bit ;

    logic                 [2:0] start_bit_enable;
    logic                 [2:0] end_bit_enable  ;
    logic [DATA_WIDTH-1:0][2:0] data_bit_enable ;

    assign start_bit_enable[0] = (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2 - 1)) & sample_valid;
    assign start_bit_enable[1] = (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2    )) & sample_valid;
    assign start_bit_enable[2] = (rx_sample_count == (0 + OVERSAMPLING_FACTOR / 2 + 1)) & sample_valid;

    `DFFR(start_bit[0], rx, start_bit_enable[0], i_clk, i_rst_n)
    `DFFR(start_bit[1], rx, start_bit_enable[1], i_clk, i_rst_n)
    `DFFR(start_bit[2], rx, start_bit_enable[2], i_clk, i_rst_n)

    genvar g_bit;
    generate
        for (g_bit = 0; g_bit < DATA_WIDTH; g_bit++) begin : gen_rx_bit_received
            assign data_bit_enable[g_bit][0] = (rx_sample_count == (((g_bit + 1) * OVERSAMPLING_FACTOR) + OVERSAMPLING_FACTOR / 2 - 1)) & sample_valid;
            assign data_bit_enable[g_bit][1] = (rx_sample_count == (((g_bit + 1) * OVERSAMPLING_FACTOR) + OVERSAMPLING_FACTOR / 2    )) & sample_valid;
            assign data_bit_enable[g_bit][2] = (rx_sample_count == (((g_bit + 1) * OVERSAMPLING_FACTOR) + OVERSAMPLING_FACTOR / 2 + 1)) & sample_valid;

            `DFFR(data_bit[g_bit][0], rx, data_bit_enable[g_bit][0], i_clk, i_rst_n)
            `DFFR(data_bit[g_bit][1], rx, data_bit_enable[g_bit][1], i_clk, i_rst_n)
            `DFFR(data_bit[g_bit][2], rx, data_bit_enable[g_bit][2], i_clk, i_rst_n)
        end
    endgenerate

    assign end_bit_enable[0] = (rx_sample_count == ((DATA_WIDTH + 2) * OVERSAMPLING_FACTOR - 1)) & sample_valid;
    assign end_bit_enable[1] = (rx_sample_count == ((DATA_WIDTH + 2) * OVERSAMPLING_FACTOR    )) & sample_valid;
    assign end_bit_enable[2] = (rx_sample_count == ((DATA_WIDTH + 2) * OVERSAMPLING_FACTOR + 1)) & sample_valid;

    `DFFR(end_bit[0], rx, end_bit_enable[0], i_clk, i_rst_n)
    `DFFR(end_bit[1], rx, end_bit_enable[1], i_clk, i_rst_n)
    `DFFR(end_bit[2], rx, end_bit_enable[2], i_clk, i_rst_n)

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // RX Bit Median
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    logic start_bit_med;
    logic [DATA_WIDTH-1:0] data_bit_med ;
    logic [DATA_WIDTH-1:0] data_bit_med_next ;

    assign start_bit_med = 
        (start_bit[0] & start_bit[1]) | 
        (start_bit[1] & start_bit[2]) | 
        (start_bit[2] & start_bit[0]);

    genvar g_bit_med;
    generate
        for (g_bit_med = 0; g_bit_med < DATA_WIDTH; g_bit_med++) begin : gen_rx_bit_med
            assign data_bit_med_next[g_bit_med] = 
                (data_bit[g_bit_med][0] & data_bit[g_bit_med][1]) | 
                (data_bit[g_bit_med][1] & data_bit[g_bit_med][2]) | 
                (data_bit[g_bit_med][2] & data_bit[g_bit_med][0]);
        end
    endgenerate

    `DFFR(data_bit_med, data_bit_med_next, sample_valid, i_clk, i_rst_n)

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // FIFO
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic rx_fifo_wvalid;
    logic rx_fifo_wready;
    logic [DATA_WIDTH-1:0] rx_fifo_wdata;
    logic rx_fifo_rvalid;
    logic rx_fifo_rready;
    logic [DATA_WIDTH-1:0] rx_fifo_rdata;

    assign rx_fifo_wvalid = (rx_state == STOP) & sample_valid & ~start_bit_med;
    assign rx_fifo_wdata  = data_bit_med;
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