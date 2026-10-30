// =============================================================
//  debounce.v  --  按键消抖
//  27 MHz / 27000 = 1 kHz 采样，连续 8 次一致才更新输出
// =============================================================
module debounce #(
    parameter integer SAMPLE_DIV = 27000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire din,      // 1 = 按下
    output reg  dout      // 消抖后的按下标志
);

    reg [15:0] div_cnt;
    reg [7:0]  shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 16'd0;
            shift   <= 8'd0;
            dout    <= 1'b0;
        end else if (div_cnt >= SAMPLE_DIV - 1) begin
            div_cnt <= 16'd0;
            shift   <= {shift[6:0], din};
            if (&shift)
                dout <= 1'b1;
            else if (~|shift)
                dout <= 1'b0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

endmodule
