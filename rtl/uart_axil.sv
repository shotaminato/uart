// uart_axil — AXI4-Lite MMIO wrapper around uart_rx / uart_tx
//
// Clock / reset
//   i_clk, i_rst_n   Single clock domain shared by AXI and UART (active-low async reset)
//
// Physical UART
//   o_tx, i_rx       Serial pins. Idle-high. Same baud/data parameters as uart_rx/uart_tx.
//
// AXI4-Lite slave (32-bit data, ADDR_WIDTH-bit address offset, default 8)
//   Address is a byte offset into this block. Word-align bits [1:0] are ignored.
//   Unmapped offsets return DECERR (2'b11) on BRESP/RRESP. Mapped accesses return OKAY.
//
// Register map (byte offset)
//   0x00 STATUS  (RO)
//        [0] RX_VALID   uart_rx has a byte to read
//        [1] TX_READY   uart_tx can accept a byte (TX FIFO not full)
//        [31:2] reserved 0
//   0x04 RXDATA  (RO)
//        [7:0] received byte when RX_VALID=1, else 0
//        Read (AR handshake) pops/consumes one RX FIFO entry if RX_VALID was 1.
//        RDATA is snapshotted on the AR handshake so a delayed RREADY cannot lose
//        the byte or pop a later one.
//        Read when RX_VALID=0 returns 0 and does not pop.
//   0x08 TXDATA  (WO)
//        [7:0] byte to transmit. Pushed on write if TX_READY=1 and wstrb[0]=1.
//        Write when TX_READY=0 (or wstrb[0]=0) is ignored. BRESP is still OKAY.
//        Read returns 0 with OKAY.
//   0x0C CONTROL (RW)
//        [0] ENABLE  (reset 1). 0 holds uart_rx and uart_tx in reset (soft reset).
//        [31:1] reserved; writes ignored, reads 0
//        Only wstrb[0] updates ENABLE.
//
// Writes to STATUS/RXDATA are ignored (OKAY). Unaligned offsets 0x00-0x0F decode
// as the containing word. Offsets outside {0x00,0x04,0x08,0x0C} are DECERR.

module uart_axil #(
    parameter int unsigned ADDR_WIDTH   = 8,
    parameter int unsigned DATA_WIDTH   = 32,
    parameter              BAUD_RATE    = 115200,
    parameter              DATA_BITS    = 8,
    parameter              STOP_BITS    = 1,
    parameter              PARITY       = "NONE",
    parameter              CLK_FREQ_MHZ = 50
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

    output logic                     o_tx,
    input  logic                     i_rx
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_DECERR = 2'b11;

    localparam logic [ADDR_WIDTH-1:0] ADDR_STATUS  = ADDR_WIDTH'(32'h00);
    localparam logic [ADDR_WIDTH-1:0] ADDR_RXDATA  = ADDR_WIDTH'(32'h04);
    localparam logic [ADDR_WIDTH-1:0] ADDR_TXDATA  = ADDR_WIDTH'(32'h08);
    localparam logic [ADDR_WIDTH-1:0] ADDR_CONTROL = ADDR_WIDTH'(32'h0C);

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // AXI-Lite <-> register-file pulses
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic                    csr_wr_valid;
    logic [ADDR_WIDTH-1:0]   csr_wr_addr;
    logic [DATA_WIDTH-1:0]   csr_wr_data;
    logic [STRB_WIDTH-1:0]   csr_wr_strb;
    logic [1:0]              csr_wr_resp;

    logic                    csr_rd_valid;
    logic [ADDR_WIDTH-1:0]   csr_rd_addr;
    logic [DATA_WIDTH-1:0]   csr_rd_data;
    logic [1:0]              csr_rd_resp;

    axil_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_axil (
        .i_clk     (i_clk),
        .i_rst_n   (i_rst_n),
        .i_awaddr  (i_awaddr),
        .i_awprot  (i_awprot),
        .i_awvalid (i_awvalid),
        .o_awready (o_awready),
        .i_wdata   (i_wdata),
        .i_wstrb   (i_wstrb),
        .i_wvalid  (i_wvalid),
        .o_wready  (o_wready),
        .o_bresp   (o_bresp),
        .o_bvalid  (o_bvalid),
        .i_bready  (i_bready),
        .i_araddr  (i_araddr),
        .i_arprot  (i_arprot),
        .i_arvalid (i_arvalid),
        .o_arready (o_arready),
        .o_rdata   (o_rdata),
        .o_rresp   (o_rresp),
        .o_rvalid  (o_rvalid),
        .i_rready  (i_rready),
        .o_wr_valid(csr_wr_valid),
        .o_wr_addr (csr_wr_addr),
        .o_wr_data (csr_wr_data),
        .o_wr_strb (csr_wr_strb),
        .i_wr_resp (csr_wr_resp),
        .o_rd_valid(csr_rd_valid),
        .o_rd_addr (csr_rd_addr),
        .i_rd_data (csr_rd_data),
        .i_rd_resp (csr_rd_resp)
    );

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Address decode (word-aligned; [1:0] ignored)
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0] wr_word;
    logic [ADDR_WIDTH-1:0] rd_word;

    assign wr_word = {csr_wr_addr[ADDR_WIDTH-1:2], 2'b00};
    assign rd_word = {csr_rd_addr[ADDR_WIDTH-1:2], 2'b00};

    logic wr_sel_status;
    logic wr_sel_rxdata;
    logic wr_sel_txdata;
    logic wr_sel_control;
    logic wr_mapped;

    logic rd_sel_status;
    logic rd_sel_rxdata;
    logic rd_sel_txdata;
    logic rd_sel_control;
    logic rd_mapped;

    assign wr_sel_status  = (wr_word == ADDR_STATUS);
    assign wr_sel_rxdata  = (wr_word == ADDR_RXDATA);
    assign wr_sel_txdata  = (wr_word == ADDR_TXDATA);
    assign wr_sel_control = (wr_word == ADDR_CONTROL);
    assign wr_mapped      = wr_sel_status | wr_sel_rxdata | wr_sel_txdata | wr_sel_control;

    assign rd_sel_status  = (rd_word == ADDR_STATUS);
    assign rd_sel_rxdata  = (rd_word == ADDR_RXDATA);
    assign rd_sel_txdata  = (rd_word == ADDR_TXDATA);
    assign rd_sel_control = (rd_word == ADDR_CONTROL);
    assign rd_mapped      = rd_sel_status | rd_sel_rxdata | rd_sel_txdata | rd_sel_control;

    assign csr_wr_resp = wr_mapped ? AXI_OKAY : AXI_DECERR;
    assign csr_rd_resp = rd_mapped ? AXI_OKAY : AXI_DECERR;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // CONTROL[0] ENABLE (reset 1) — 0 holds the UART cores in reset
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic ctrl_enable;
    logic ctrl_enable_next;
    logic ctrl_enable_we;
    logic uart_rst_n;

    assign ctrl_enable_we   = csr_wr_valid & wr_sel_control & csr_wr_strb[0];
    assign ctrl_enable_next = csr_wr_data[0];
    `DFFR_VAL(ctrl_enable, ctrl_enable_next, ctrl_enable_we, i_clk, i_rst_n, 1'b1)

    assign uart_rst_n = i_rst_n & ctrl_enable;

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // UART RX / TX
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic [DATA_BITS-1:0] rx_rdata;
    logic                 rx_valid;
    logic                 rx_ready;
    logic [DATA_BITS-1:0] tx_wdata;
    logic                 tx_valid;
    logic                 tx_ready;

    // Pop exactly when RXDATA is accepted on AR and a byte is present. The byte
    // on rx_rdata is still the current FIFO head this cycle; axil_slave snapshots
    // csr_rd_data on the same AR handshake.
    assign rx_ready = csr_rd_valid & rd_sel_rxdata & rx_valid;

    assign tx_valid = csr_wr_valid & wr_sel_txdata & csr_wr_strb[0] & tx_ready;
    assign tx_wdata = csr_wr_data[DATA_BITS-1:0];

    uart_rx #(
        .BAUD_RATE   (BAUD_RATE),
        .DATA_WIDTH  (DATA_BITS),
        .STOP_BITS   (STOP_BITS),
        .PARITY      (PARITY),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) u_uart_rx (
        .i_clk   (i_clk),
        .i_rst_n (uart_rst_n),
        .i_rx    (i_rx),
        .o_rdata (rx_rdata),
        .o_rvalid(rx_valid),
        .i_rready(rx_ready)
    );

    uart_tx #(
        .BAUD_RATE   (BAUD_RATE),
        .DATA_WIDTH  (DATA_BITS),
        .STOP_BITS   (STOP_BITS),
        .PARITY      (PARITY),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) u_uart_tx (
        .i_clk   (i_clk),
        .i_rst_n (uart_rst_n),
        .o_tx    (o_tx),
        .i_wdata (tx_wdata),
        .i_wvalid(tx_valid),
        .o_wready(tx_ready)
    );

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Read data
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////

    logic [DATA_WIDTH-1:0] rd_status;
    logic [DATA_WIDTH-1:0] rd_rxdata;
    logic [DATA_WIDTH-1:0] rd_control;

    assign rd_status  = {{(DATA_WIDTH-2){1'b0}}, tx_ready, rx_valid};
    assign rd_rxdata  = {{(DATA_WIDTH-DATA_BITS){1'b0}}, rx_rdata};
    assign rd_control = {{(DATA_WIDTH-1){1'b0}}, ctrl_enable};

    assign csr_rd_data =
        (rd_sel_status  ? rd_status  : '0) |
        (rd_sel_rxdata  ? rd_rxdata  : '0) |
        (rd_sel_control ? rd_control : '0);

endmodule
