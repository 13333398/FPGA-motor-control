// =============================================================
//  pi_ctrl.v  --  定点 PI 速度控制器
//
//  输入：目标转速 / 实际转速（RPM），控制周期由 tick 决定（默认 50 Hz）
//  输出：PWM 占空比 0..1023
//
//  增益用 Q8.8 表示：KP_Q8 = 256 表示 1.0
//    P = err * KP_Q8 >> 8
//    I = 累加 err * KI_Q8 >> 8（每个控制周期一次）
//
//  包含：积分限幅、抗积分饱和(anti-windup)、输出限幅、死区补偿
// =============================================================
module pi_ctrl #(
    parameter signed [15:0] KP_Q8    = 16'sd1280, // 5.0
    parameter signed [15:0] KI_Q8    = 16'sd77,   // 0.3
    parameter        [9:0]  DUTY_MAX = 10'd1023,
    parameter        [9:0]  MIN_DUTY = 10'd120    // 死区补偿：低于此值补到启动占空比
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick,
    input  wire        run,
    input  wire [15:0] target_rpm,
    input  wire [15:0] actual_rpm,
    output reg  [9:0]  duty
);

    localparam signed [26:0] DMAX = 27'sd1023;
    localparam signed [26:0] MIND = 27'sd120;

    // 显式声明为 signed，避免依赖 $signed()，兼容各家综合器
    wire signed [16:0] tgt_s = {1'b0, target_rpm};
    wire signed [16:0] act_s = {1'b0, actual_rpm};
    wire signed [16:0] err   = tgt_s - act_s;

    wire signed [32:0] p_full = err * KP_Q8;
    wire signed [32:0] i_full = err * KI_Q8;
    wire signed [26:0] p_term = p_full >>> 8;
    wire signed [26:0] i_inc  = i_full >>> 8;

    reg  signed [26:0] integ;
    reg  signed [26:0] sum_v;
    reg  signed [26:0] int_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || !run) begin
            integ <= 27'sd0;
            duty  <= 10'd0;
        end else if (tick) begin
            sum_v = p_term + integ;
            int_v = integ + i_inc;

            // 抗积分饱和：输出已经顶到上/下限且误差还在往同方向推，就停止累加
            if ((sum_v > DMAX) && (err > 0)) int_v = integ;
            if ((sum_v < 0)    && (err < 0)) int_v = integ;

            if (int_v > DMAX) int_v = DMAX;
            if (int_v < 0)    int_v = 27'sd0;
            integ <= int_v;

            // 输出限幅 + 死区补偿
            if (sum_v <= 0)
                duty <= 10'd0;
            else if (sum_v >= DMAX)
                duty <= DUTY_MAX;
            else if ((sum_v < MIND) && (target_rpm != 16'd0))
                duty <= MIN_DUTY;
            else
                duty <= sum_v[9:0];
        end
    end

endmodule
