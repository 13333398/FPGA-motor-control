// =============================================================
//  selftest_motor.v  --  片内虚拟电机（只需一块开发板就能自检）
//
//  输入：PWM 占空比 0..1023
//  输出：模拟编码器 A/B 正交波形
//
//  模型：一阶惯性 + 10% 启动死区
//    稳态转速 = (duty/1024 - 0.10) * 800 RPM
//    时间常数 tau ≈ 256 ms
//
//  用途：不接电机、不接编码器时，把 SELF_TEST 置 1，
//  整条闭环链路（PI→PWM→"电机"→编码器→测速→PI）都在芯片内跑，
//  串口能看到转速收敛，LED 的反应也是真实的。
// =============================================================
module selftest_motor #(
    parameter integer F_CLK = 27_000_000,
    parameter integer TPR   = 1320
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [9:0] duty,
    input  wire       dir,        // 0 正转 / 1 反转（只影响编码器相位方向）
    output reg        enc_a,
    output reg        enc_b
);

    // ---------------- 1 ms 时基 ----------------
    reg [14:0] ms_cnt;
    reg        ms_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_cnt  <= 15'd0;
            ms_tick <= 1'b0;
        end else if (ms_cnt >= F_CLK/1000 - 1) begin
            ms_cnt  <= 15'd0;
            ms_tick <= 1'b1;
        end else begin
            ms_cnt  <= ms_cnt + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    // ---------------- 一阶速度模型 ----------------
    wire signed [16:0] duty_s  = {7'b0, duty};
    reg  signed [24:0] vq      = 25'sd0;   // 速度 Q8.8（RPM x 256）
    reg  signed [24:0] vq_next;
    reg  signed [16:0] ss      = 17'sd0;
    reg  signed [31:0] tmp;
    reg  signed [24:0] ssq_r;              // ss 的 Q8.8 版本

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vq <= 25'sd0;
        end else if (ms_tick) begin
            if (duty > 10'd102) begin
                tmp = (duty_s - 17'sd102) * 32'sd800;
                ss  = tmp >>> 10;
            end else begin
                ss = 17'sd0;
            end

            ssq_r = ss <<< 8;
            // Q8.8 一阶惯性：小误差也不会被截断成 0
            vq_next = vq + ((ssq_r - vq) >>> 8);
            if (vq_next < 0)
                vq <= 25'sd0;
            else
                vq <= vq_next;
        end
    end

    // ---------------- 编码器边沿生成 ----------------
    // 每 100 个时钟更新一次相位累加器（Q16.16，单位=边沿）
    // 边沿速率 = vspeed * TPR / 60  edges/s
    // 每次增量 = vspeed * TPR/60 * 65536 / (F_CLK/100)
    //          ≈ vspeed * 683 / 128   (TPR=1320, F_CLK=27MHz)
    // vq 是 RPMx256，所以这里 >>15 等价于 (rpm * 683) >> 7
    wire [31:0] inc = (vq[23:0] * 32'd683) >> 15;

    reg [6:0]  div100;
    reg [31:0] acc;
    reg [1:0]  quad;
    reg [1:0]  quad_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div100 <= 7'd0;
            acc    <= 32'd0;
            quad   <= 2'd0;
            enc_a  <= 1'b0;
            enc_b  <= 1'b0;
        end else if (div100 >= 7'd99) begin
            div100 <= 7'd0;
            if ((acc + inc) >= 32'h0001_0000) begin
                acc  <= acc + inc - 32'h0001_0000;
                quad <= dir ? (quad - 1'b1) : (quad + 1'b1);
                quad_n = dir ? (quad - 1'b1) : (quad + 1'b1);
                case (quad_n)
                    2'd0: {enc_a, enc_b} <= 2'b00;
                    2'd1: {enc_a, enc_b} <= 2'b01;
                    2'd2: {enc_a, enc_b} <= 2'b11;
                    default: {enc_a, enc_b} <= 2'b10;
                endcase
            end else begin
                acc <= acc + inc;
            end
        end else begin
            div100 <= div100 + 1'b1;
        end
    end

endmodule
