// =============================================================
//  speed_m.v  --  M 法测速（固定闸门时间内数编码器增量）
//
//  转速换算：
//    每圈计数 TPR = 编码器线数 x 4 x 减速比
//    RPM = delta * 60 / (TPR * T_gate)
//        = delta * 60 * F_CLK / (TPR * GATE_CYCLES)
//  用定点乘代替除法：RPM = (delta * RPM_K) >> 16
//
//  默认参数按 GA12-N20（11 线、1:30）：
//    TPR = 11*4*30 = 1320，闸门 20 ms
// =============================================================
module speed_m #(
    parameter integer F_CLK   = 27_000_000,
    parameter integer GATE_MS = 20,
    parameter integer TPR     = 1320
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire signed [23:0] pos,
    output reg  [15:0]       rpm,     // 绝对转速
    output reg               dir,     // 0 正转 / 1 反转
    output reg               tick     // 每次闸门结束产生一个时钟脉冲
);

    localparam integer GATE_CYCLES = F_CLK / 1000 * GATE_MS;

    // 64 位中间计算，避免常量乘法溢出
    localparam [63:0] RPM_K_64 =
        (64'd60 * F_CLK * 64'd65536) / (TPR * GATE_CYCLES);
    localparam [31:0] RPM_K = RPM_K_64[31:0];

    reg  [31:0]       gate_cnt;
    reg  signed [23:0] pos_prev;

    wire signed [23:0] delta = pos - pos_prev;
    wire [23:0]        mag   = delta[23] ? (~delta + 1'b1) : delta;
    wire [47:0]        prod  = mag * RPM_K;
    wire [31:0]        rpm_calc = prod >> 16;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gate_cnt <= 32'd0;
            pos_prev <= 24'sd0;
            rpm      <= 16'd0;
            dir      <= 1'b0;
            tick     <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (gate_cnt >= GATE_CYCLES - 1) begin
                gate_cnt <= 32'd0;
                pos_prev <= pos;
                dir      <= delta[23];
                rpm      <= (rpm_calc > 32'd65535) ? 16'd65535 : rpm_calc[15:0];
                tick     <= 1'b1;
            end else begin
                gate_cnt <= gate_cnt + 1'b1;
            end
        end
    end

endmodule
