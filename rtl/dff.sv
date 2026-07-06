module uart_dff #(
    parameter WIDTH = 1
) (
    input  logic i_clk,
    input  logic i_rst_n,
    input  logic [WIDTH-1:0] i_d,
    input  logic              i_en,
    output logic [WIDTH-1:0] o_q
);

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_q <= 0;
        end else begin
            if (i_en) begin
                o_q <= i_d;
            end
        end
    end
endmodule


`define DFF(__q, __d, __en) \
    always_ff @(posedge i_clk or negedge i_rst_n) begin \
        if (!i_rst_n) begin \
            {__q} <= 0; \
        end else begin \
            if ({__en}) begin \
                {__q} <= {__d}; \
            end \
        end \
    end