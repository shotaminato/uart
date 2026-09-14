// Self-checking testbench for uart_axil (AXI4-Lite + UART MMIO).
// Exercises register map, DECERR, TX push, RX pop-on-read, and AW/W ordering.

`timescale 1ns/1ps

module tb_uart_axil;

    localparam int unsigned ADDR_WIDTH   = 8;
    localparam int unsigned DATA_WIDTH   = 32;
    localparam int unsigned CLK_FREQ_MHZ = 50;
    localparam int unsigned BAUD_RATE    = 115200;
    localparam int unsigned CYCLES_PER_BIT = CLK_FREQ_MHZ * 1_000_000 / BAUD_RATE;

    localparam logic [7:0] ADDR_STATUS  = 8'h00;
    localparam logic [7:0] ADDR_RXDATA  = 8'h04;
    localparam logic [7:0] ADDR_TXDATA  = 8'h08;
    localparam logic [7:0] ADDR_CONTROL = 8'h0C;
    localparam logic [7:0] ADDR_BAD     = 8'h10;

    localparam logic [1:0] AXI_OKAY   = 2'b00;
    localparam logic [1:0] AXI_DECERR = 2'b11;

    logic                     i_clk;
    logic                     i_rst_n;
    logic [ADDR_WIDTH-1:0]    i_awaddr;
    logic [2:0]               i_awprot;
    logic                     i_awvalid;
    logic                     o_awready;
    logic [DATA_WIDTH-1:0]    i_wdata;
    logic [3:0]               i_wstrb;
    logic                     i_wvalid;
    logic                     o_wready;
    logic [1:0]               o_bresp;
    logic                     o_bvalid;
    logic                     i_bready;
    logic [ADDR_WIDTH-1:0]    i_araddr;
    logic [2:0]               i_arprot;
    logic                     i_arvalid;
    logic                     o_arready;
    logic [DATA_WIDTH-1:0]    o_rdata;
    logic [1:0]               o_rresp;
    logic                     o_rvalid;
    logic                     i_rready;
    logic                     o_tx;
    logic                     i_rx;

    int unsigned fail_count;

    uart_axil #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .BAUD_RATE   (BAUD_RATE),
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) dut (
        .i_clk    (i_clk),
        .i_rst_n  (i_rst_n),
        .i_awaddr (i_awaddr),
        .i_awprot (i_awprot),
        .i_awvalid(i_awvalid),
        .o_awready(o_awready),
        .i_wdata  (i_wdata),
        .i_wstrb  (i_wstrb),
        .i_wvalid (i_wvalid),
        .o_wready (o_wready),
        .o_bresp  (o_bresp),
        .o_bvalid (o_bvalid),
        .i_bready (i_bready),
        .i_araddr (i_araddr),
        .i_arprot (i_arprot),
        .i_arvalid(i_arvalid),
        .o_arready(o_arready),
        .o_rdata  (o_rdata),
        .o_rresp  (o_rresp),
        .o_rvalid (o_rvalid),
        .i_rready (i_rready),
        .o_tx     (o_tx),
        .i_rx     (i_rx)
    );

    initial begin
        i_clk = 1'b0;
        forever #10 i_clk = ~i_clk;
    end

    task automatic axil_idle();
        i_awaddr  = '0;
        i_awprot  = 3'b000;
        i_awvalid = 1'b0;
        i_wdata   = '0;
        i_wstrb   = 4'h0;
        i_wvalid  = 1'b0;
        i_bready  = 1'b1;
        i_araddr  = '0;
        i_arprot  = 3'b000;
        i_arvalid = 1'b0;
        i_rready  = 1'b1;
    endtask

    task automatic axil_write(
        input  logic [7:0]  addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb,
        output logic [1:0]  resp,
        input  int          aw_first
    );
        resp = 2'b00;

        if (aw_first) begin
            @(negedge i_clk);
            i_awaddr  = addr;
            i_awvalid = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_awvalid = 1'b0;
            i_wdata   = data;
            i_wstrb   = strb;
            i_wvalid  = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_wvalid = 1'b0;
        end else begin
            @(negedge i_clk);
            i_wdata  = data;
            i_wstrb  = strb;
            i_wvalid = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_wvalid  = 1'b0;
            i_awaddr  = addr;
            i_awvalid = 1'b1;
            @(posedge i_clk);
            @(negedge i_clk);
            i_awvalid = 1'b0;
        end

        if (!o_bvalid) begin
            $display("FAIL BVALID missing after write");
            fail_count += 1;
        end
        resp = o_bresp;
        @(posedge i_clk);
    endtask

    task automatic axil_write_same(
        input  logic [7:0]  addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb,
        output logic [1:0]  resp
    );
        @(negedge i_clk);
        i_awaddr  = addr;
        i_awvalid = 1'b1;
        i_wdata   = data;
        i_wstrb   = strb;
        i_wvalid  = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_awvalid = 1'b0;
        i_wvalid  = 1'b0;
        if (!o_bvalid) begin
            $display("FAIL BVALID missing after same-cycle write");
            fail_count += 1;
        end
        resp = o_bresp;
        @(posedge i_clk);
    endtask

    task automatic axil_read(
        input  logic [7:0]  addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        @(negedge i_clk);
        i_araddr  = addr;
        i_arvalid = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_arvalid = 1'b0;
        if (!o_rvalid) begin
            $display("FAIL RVALID missing after AR addr=0x%02x", addr);
            fail_count += 1;
        end
        data = o_rdata;
        resp = o_rresp;
        @(posedge i_clk);
    endtask

    // Delayed RREADY: AR first, then stall R to prove RX pop happened on AR
    // and RDATA stayed snapshotted.
    task automatic axil_read_stall_r(
        input  logic [7:0]  addr,
        input  int unsigned stall_cycles,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        @(negedge i_clk);
        i_rready  = 1'b0;
        i_araddr  = addr;
        i_arvalid = 1'b1;
        @(posedge i_clk);
        @(negedge i_clk);
        i_arvalid = 1'b0;
        if (!o_rvalid) begin
            $display("FAIL RVALID missing during stalled R");
            fail_count += 1;
        end
        repeat (stall_cycles) @(posedge i_clk);
        @(negedge i_clk);
        data = o_rdata;
        resp = o_rresp;
        i_rready = 1'b1;
        @(posedge i_clk);
    endtask

    task automatic uart_send_byte(input logic [7:0] b);
        int unsigned i;
        @(negedge i_clk);
        i_rx = 1'b0;
        repeat (CYCLES_PER_BIT) @(posedge i_clk);
        for (i = 0; i < 8; i++) begin
            @(negedge i_clk);
            i_rx = b[i];
            repeat (CYCLES_PER_BIT) @(posedge i_clk);
        end
        @(negedge i_clk);
        i_rx = 1'b1;
        repeat (CYCLES_PER_BIT) @(posedge i_clk);
        repeat (CYCLES_PER_BIT) @(posedge i_clk);
    endtask

    task automatic expect_eq(
        input string        name,
        input logic [31:0]  got,
        input logic [31:0]  exp
    );
        if (got !== exp) begin
            $display("FAIL %s: got 0x%08x expected 0x%08x", name, got, exp);
            fail_count += 1;
        end else begin
            $display("PASS %s = 0x%08x", name, got);
        end
    endtask

    initial begin
        logic [31:0] rdata;
        logic [1:0]  resp;
        logic [31:0] status0;
        int unsigned n;
        fail_count = 0;

        $display("tb_uart_axil: start");
        axil_idle();
        i_rst_n = 1'b0;
        i_rx    = 1'b1;
        repeat (8) @(posedge i_clk);
        i_rst_n = 1'b1;
        repeat (8) @(posedge i_clk);

        // CONTROL defaults to ENABLE=1
        axil_read(ADDR_CONTROL, rdata, resp);
        expect_eq("CONTROL after reset", rdata, 32'h1);
        expect_eq("CONTROL RRESP", {30'b0, resp}, {30'b0, AXI_OKAY});

        // STATUS: RX empty, TX ready
        axil_read(ADDR_STATUS, rdata, resp);
        expect_eq("STATUS after reset", rdata, 32'h2);
        expect_eq("STATUS RRESP", {30'b0, resp}, {30'b0, AXI_OKAY});

        // RXDATA empty
        axil_read(ADDR_RXDATA, rdata, resp);
        expect_eq("RXDATA empty", rdata, 32'h0);

        // TXDATA read is 0 / OKAY
        axil_read(ADDR_TXDATA, rdata, resp);
        expect_eq("TXDATA read", rdata, 32'h0);
        expect_eq("TXDATA read RRESP", {30'b0, resp}, {30'b0, AXI_OKAY});

        // Bad address
        axil_read(ADDR_BAD, rdata, resp);
        expect_eq("bad read RRESP", {30'b0, resp}, {30'b0, AXI_DECERR});
        axil_write_same(ADDR_BAD, 32'hA5, 4'hF, resp);
        expect_eq("bad write BRESP", {30'b0, resp}, {30'b0, AXI_DECERR});

        // CONTROL write 0 then 1 (soft reset), W-then-AW order
        axil_write(ADDR_CONTROL, 32'h0, 4'hF, resp, 0);
        expect_eq("CONTROL=0 BRESP", {30'b0, resp}, {30'b0, AXI_OKAY});
        axil_read(ADDR_CONTROL, rdata, resp);
        expect_eq("CONTROL read 0", rdata, 32'h0);
        axil_write(ADDR_CONTROL, 32'h1, 4'hF, resp, 1);
        axil_read(ADDR_CONTROL, rdata, resp);
        expect_eq("CONTROL read 1", rdata, 32'h1);
        axil_read(ADDR_STATUS, rdata, resp);
        expect_eq("STATUS after re-enable", rdata, 32'h2);

        // TX write (same-cycle AW+W)
        axil_write_same(ADDR_TXDATA, 32'h000000A5, 4'hF, resp);
        expect_eq("TXDATA BRESP", {30'b0, resp}, {30'b0, AXI_OKAY});

        // Fill TX FIFO (depth 16). uart_tx pops one byte into the shifter,
        // so 1 + 16 writes are needed before TX_READY clears.
        for (n = 0; n < 16; n++) begin
            axil_write_same(ADDR_TXDATA, 32'h00000010 + n, 4'hF, resp);
        end
        axil_read(ADDR_STATUS, status0, resp);
        expect_eq("STATUS TX full (TX_READY=0)", status0 & 32'h2, 32'h0);

        axil_write_same(ADDR_TXDATA, 32'h000000FF, 4'hF, resp);
        expect_eq("TX overflow BRESP still OKAY", {30'b0, resp}, {30'b0, AXI_OKAY});
        axil_read(ADDR_STATUS, rdata, resp);
        expect_eq("STATUS still TX not ready", rdata & 32'h2, 32'h0);

        // Drain via soft reset
        axil_write_same(ADDR_CONTROL, 32'h0, 4'hF, resp);
        axil_write_same(ADDR_CONTROL, 32'h1, 4'hF, resp);
        axil_read(ADDR_STATUS, rdata, resp);
        expect_eq("STATUS after TX flush", rdata, 32'h2);

        // Two RX bytes; first read pops, second remains
        uart_send_byte(8'h3C);
        uart_send_byte(8'h5A);

        // Wait until RX_VALID
        n = 0;
        rdata = 32'h0;
        while ((rdata[0] !== 1'b1) && (n < 20000)) begin
            axil_read(ADDR_STATUS, rdata, resp);
            n += 1;
        end
        if (rdata[0] !== 1'b1) begin
            $display("FAIL RX_VALID never set");
            fail_count += 1;
        end else begin
            $display("PASS RX_VALID after two bytes (STATUS=0x%08x)", rdata);
        end

        // Stall RREADY after AR to confirm snapshot + single pop
        axil_read_stall_r(ADDR_RXDATA, 20, rdata, resp);
        expect_eq("RXDATA first byte (stalled R)", rdata, 32'h3C);
        expect_eq("RXDATA first RRESP", {30'b0, resp}, {30'b0, AXI_OKAY});

        axil_read(ADDR_RXDATA, rdata, resp);
        expect_eq("RXDATA second byte", rdata, 32'h5A);

        axil_read(ADDR_STATUS, rdata, resp);
        expect_eq("STATUS RX empty after two pops", rdata & 32'h1, 32'h0);
        axil_read(ADDR_RXDATA, rdata, resp);
        expect_eq("RXDATA empty after consume", rdata, 32'h0);

        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $display("%0d TEST(S) FAILED", fail_count);
            $fatal(1);
        end
    end

    initial begin
        #20_000_000;
        $fatal(1, "timeout");
    end

endmodule
