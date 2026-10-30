// =============================================================
//  pwm_gen.v  --  PWM 发生器 + TB6612 方向控制
//
//  PWM 周期 1024 个时钟 @27MHz = 26.37 kHz（TB6612 支持到 100 kHz）
//  duty = 0..1023 对应 0..100%
//
//  TB6612 接法：
//    PWMA <- pwm      AIN1 <- ain1      AIN2 <- ain2
//    STBY 接 3.3V，VM 接电机电源，电机电源地与板子共地
//  换向时先"滑行"约 20 ms（ain1/ain2/pwm 全 0），避免 H 桥硬反接
// =============================================================
module pwm_gen #(
    parameter integer F_CLK     = 27_000_000,
    parameter [9:0]   DUTY_MAX  = 10'd1023
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       dir,      // 0 正转 / 1 反转
    input  wire [9:0] duty,
    input  wire       test_mode, // POST: 方向全关，仅输出 PWM 波形
    output reg        pwm,
    output reg        ain1,
    output reg        ain2
);

    localparam [19:0] GUARD_TICKS = F_CLK / 1000 * 20;  // 20 ms

    reg [9:0]  cnt;
    reg        dir_q;
    reg        guard_busy;
    reg [19:0] guard_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= 10'd0;
            dir_q      <= 1'b0;
            guard_busy <= 1'b0;
            guard_cnt  <= 20'd0;
            pwm        <= 1'b0;
            ain1       <= 1'b0;
            ain2       <= 1'b0;
        end else begin
            cnt <= (cnt >= DUTY_MAX) ? 10'd0 : cnt + 10'd1;

            if (dir != dir_q) begin
                dir_q      <= dir;
                guard_busy <= 1'b1;
                guard_cnt  <= 20'd0;
            end else if (guard_busy) begin
                if (guard_cnt >= GUARD_TICKS)
                    guard_busy <= 1'b0;
                else
                    guard_cnt <= guard_cnt + 1'b1;
            end

            if (test_mode) begin
                // 两个方向输入都拉低，测试 PWM 时电机不会受力。
                pwm  <= (cnt < duty);
                ain1 <= 1'b0;
                ain2 <= 1'b0;
            end else if (guard_busy || (duty == 10'd0)) begin
                pwm  <= 1'b0;
                ain1 <= 1'b0;
                ain2 <= 1'b0;
            end else begin
                pwm  <= (cnt < duty);
                ain1 <= ~dir_q;
                ain2 <=  dir_q;
            end
        end
    end

endmodule
