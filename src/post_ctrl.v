// =============================================================
//  post_ctrl.v  --  上电自检（POST）状态机
//
//  流程：
//    PWR_ON     -> 等待电源和编码器稳定，电机输出关闭
//    ENC_PULSE  -> 低占空比短脉冲，检查编码器是否出现边沿
//    ENC_SETTLE -> 关闭 H 桥，继续收集编码器边沿
//    PWM_TEST   -> AIN1/AIN2=0，仅让 PWMA 输出测试波形
//    HOLD       -> 显示自检结果约 1 秒
//    DONE       -> 锁存结果，允许主控制环路接管
//
//  post_status 中 1 表示对应检查通过：
//    bit0 = 编码器边沿
//    bit1 = PWM 输出翻转
//
//  注意：PWM 检查统计的是 FPGA 内部 PWM 波形。当前硬件没有
//  PWMA 回读脚，因此不能证明 27 脚到 TB6612 的外部连线正常。
// =============================================================
module post_ctrl #(
    parameter integer POWER_ON_MS    = 100,
    parameter integer ENC_PULSE_MS   = 120,
    parameter integer ENC_SETTLE_MS  = 250,
    parameter integer PWM_TEST_MS    = 10,
    parameter integer RESULT_HOLD_MS = 1000,
    parameter [9:0]   ENC_TEST_DUTY  = 10'd256,   // 25%
    parameter [9:0]   PWM_TEST_DUTY  = 10'd512,   // 50%
    parameter integer PWM_EDGE_MIN   = 64
)(
    input  wire       clk,
    input  wire       rst_n,          // 仅跟随上电复位，S1 不重新触发 POST
    input  wire       ms_tick,
    input  wire       enc_edge,       // quad_dec 的已滤波边沿脉冲
    input  wire       pwm_wave,       // FPGA 内部生成的 PWMA 波形
    output reg  [9:0] post_duty,
    output reg        post_dir,
    output reg        post_test_mode,
    output reg        post_done,
    output reg        post_ok,
    output reg        post_result_valid,
    output reg  [7:0] post_status
);

    localparam [2:0] S_PWR_ON     = 3'd0;
    localparam [2:0] S_ENC_PULSE  = 3'd1;
    localparam [2:0] S_ENC_SETTLE = 3'd2;
    localparam [2:0] S_PWM_TEST   = 3'd3;
    localparam [2:0] S_HOLD       = 3'd4;
    localparam [2:0] S_DONE       = 3'd5;

    reg [2:0]  state;
    reg [31:0] timer_ms;
    reg        enc_ok;
    reg        pwm_ok;
    reg        enc_edge_seen;
    reg [15:0] pwm_edges;
    reg        pwm_prev;

    // 状态对应的 PWM 输出。POST 从不直接驱动输出管脚，
    // 而是把命令交给原来的 pwm_gen，保留其复位和换向保护。
    always @(*) begin
        post_duty         = 10'd0;
        post_dir          = 1'b0;
        post_test_mode    = 1'b0;
        post_result_valid = (state == S_HOLD) || (state == S_DONE);

        case (state)
            S_ENC_PULSE: begin
                post_duty = ENC_TEST_DUTY;
            end
            S_PWM_TEST: begin
                post_duty      = PWM_TEST_DUTY;
                post_test_mode = 1'b1;
            end
            default: begin
                post_duty      = 10'd0;
                post_test_mode = 1'b0;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_PWR_ON;
            timer_ms      <= 32'd0;
            enc_ok        <= 1'b0;
            pwm_ok        <= 1'b0;
            enc_edge_seen <= 1'b0;
            pwm_edges     <= 16'd0;
            pwm_prev      <= 1'b0;
            post_done     <= 1'b0;
            post_ok       <= 1'b0;
            post_status   <= 8'd0;
        end else begin
            // 边沿不依赖 1 ms 时基，避免短脉冲边沿被漏掉。
            if ((state == S_ENC_PULSE) || (state == S_ENC_SETTLE)) begin
                if (enc_edge)
                    enc_edge_seen <= 1'b1;
            end

            // 26.37 kHz PWM 在一个 10 ms 窗口内约有 500 个边沿。
            if ((state == S_PWM_TEST) && (pwm_wave != pwm_prev)) begin
                if (pwm_edges != 16'hFFFF)
                    pwm_edges <= pwm_edges + 1'b1;
            end
            pwm_prev <= pwm_wave;

            if (ms_tick) begin
                case (state)
                    S_PWR_ON: begin
                        if ((timer_ms + 1'b1) >= POWER_ON_MS) begin
                            timer_ms      <= 32'd0;
                            state         <= S_ENC_PULSE;
                            enc_edge_seen <= 1'b0;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_ENC_PULSE: begin
                        if ((timer_ms + 1'b1) >= ENC_PULSE_MS) begin
                            timer_ms <= 32'd0;
                            state    <= S_ENC_SETTLE;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_ENC_SETTLE: begin
                        if ((timer_ms + 1'b1) >= ENC_SETTLE_MS) begin
                            timer_ms       <= 32'd0;
                            enc_ok         <= enc_edge_seen;
                            post_status[0] <= enc_edge_seen;
                            pwm_edges      <= 16'd0;
                            state          <= S_PWM_TEST;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_PWM_TEST: begin
                        if ((timer_ms + 1'b1) >= PWM_TEST_MS) begin
                            timer_ms       <= 32'd0;
                            pwm_ok         <= (pwm_edges >= PWM_EDGE_MIN);
                            post_status[1] <= (pwm_edges >= PWM_EDGE_MIN);
                            post_ok        <= enc_ok &&
                                              (pwm_edges >= PWM_EDGE_MIN);
                            state          <= S_HOLD;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_HOLD: begin
                        if ((timer_ms + 1'b1) >= RESULT_HOLD_MS) begin
                            timer_ms  <= 32'd0;
                            post_done <= 1'b1;
                            state     <= S_DONE;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_DONE: begin
                        timer_ms <= 32'd0;
                    end

                    default: begin
                        state    <= S_PWR_ON;
                        timer_ms <= 32'd0;
                    end
                endcase
            end
        end
    end

endmodule
