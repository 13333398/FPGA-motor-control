// =============================================================
//  uart_tx.v  --  8N1 串口发送（默认 115200）
//  27 MHz / 115200 = 234.4 -> 取 234，实际 115384，误差 0.16%
// =============================================================
module uart_tx #(
    parameter integer CLK_FREQ = 27_000_000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,
    output reg        busy,
    output reg        tx
);

    localparam integer DIV = (CLK_FREQ + BAUD/2) / BAUD;

    reg [15:0] cnt;
    reg [3:0]  bitn;
    reg [9:0]  shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            tx      <= 1'b1;
            cnt     <= 16'd0;
            bitn    <= 4'd0;
            shifter <= 10'h3FF;
        end else if (!busy) begin
            tx <= 1'b1;
            if (send) begin
                shifter <= {1'b1, data, 1'b0};  // bit0=起始位，bit9=停止位
                busy    <= 1'b1;
                bitn    <= 4'd0;
                cnt     <= 16'd0;
                tx      <= 1'b0;                // 立即发起始位
            end
        end else begin
            if (cnt >= DIV - 1) begin
                cnt <= 16'd0;
                if (bitn == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bitn <= bitn + 1'b1;
                    tx   <= shifter[bitn + 1'b1];
                end
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule
