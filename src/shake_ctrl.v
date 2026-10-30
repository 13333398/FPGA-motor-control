// =============================================================
//  shake_ctrl.v  --  堵转后的有限次颤振脱困
//
//  一个脱困周期：
//    目标方向脉冲 -> 全桥关断 -> 反方向脉冲 -> 全桥关断
//
//  成功：连续 CONFIRM_TICKS 个测速周期检测到转速达到阈值。
//  失败：完成 MAX_CYCLES 个周期，或整个流程超过 TOTAL_TIMEOUT_MS。
//
//  本模块只生成旁路 PWM 命令，不修改 PI 内部状态。
// =============================================================
module shake_ctrl #(
    parameter integer MAX_CYCLES       = 3,
    parameter integer PULSE_MS         = 120,
    parameter integer GAP_MS           = 200,
    parameter integer TOTAL_TIMEOUT_MS = 3000,
    parameter integer CONFIRM_TICKS    = 2,
    parameter [9:0]   SHAKE_DUTY       = 10'd350
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ms_tick,
    input  wire        speed_tick,
    input  wire        stall_detected,
    input  wire        manual_clear,
    input  wire [15:0] target_rpm,
    input  wire        target_dir,
    input  wire [15:0] actual_rpm,
    output reg         active,
    output reg  [9:0]  pwm_duty,
    output reg         pwm_dir,
    output reg         stall_latched,
    output reg         recovery_success,
    output reg         clear_stall_detected
);

    localparam [2:0] S_IDLE       = 3'd0;
    localparam [2:0] S_MAIN_PULSE = 3'd1;
    localparam [2:0] S_GAP1       = 3'd2;
    localparam [2:0] S_OPP_PULSE  = 3'd3;
    localparam [2:0] S_GAP2       = 3'd4;
    localparam [2:0] S_SUCCESS    = 3'd5;
    localparam [2:0] S_FAIL       = 3'd6;

    reg [2:0]  state;
    reg        base_dir;
    reg [1:0]  retry_cnt;
    reg [31:0] timer_ms;
    reg [31:0] elapsed_ms;
    reg [2:0]  motion_ticks;

    // 至少 8 RPM；目标较大时提高到约目标的 6.25%。
    wire [15:0] recover_th =
        ((target_rpm >> 4) > 16'd8) ? (target_rpm >> 4) : 16'd8;
    wire        speed_ok = (actual_rpm >= recover_th);
    wire        in_attempt = (state >= S_MAIN_PULSE) &&
                             (state <= S_GAP2);

    always @(*) begin
        active               = 1'b0;
        pwm_duty             = 10'd0;
        pwm_dir              = base_dir;
        recovery_success     = 1'b0;
        clear_stall_detected = 1'b0;

        case (state)
            S_MAIN_PULSE: begin
                active   = 1'b1;
                pwm_duty = SHAKE_DUTY;
                pwm_dir  = base_dir;
            end
            S_GAP1: begin
                active   = 1'b1;
                pwm_duty = 10'd0;
                pwm_dir  = ~base_dir;   // 提前建立下一次换向死区
            end
            S_OPP_PULSE: begin
                active   = 1'b1;
                pwm_duty = SHAKE_DUTY;
                pwm_dir  = ~base_dir;
            end
            S_GAP2: begin
                active   = 1'b1;
                pwm_duty = 10'd0;
                pwm_dir  = base_dir;
            end
            S_SUCCESS: begin
                recovery_success     = 1'b1;
                clear_stall_detected = 1'b1;
                pwm_dir              = base_dir;
            end
            default: begin
                pwm_dir = base_dir;
            end
        endcase

        // 目标被用户改为 0 时直接取消，不启动电机。
        if ((state == S_IDLE) &&
            stall_detected && (target_rpm == 16'd0)) begin
            clear_stall_detected = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            base_dir      <= 1'b0;
            retry_cnt     <= 2'd0;
            timer_ms      <= 32'd0;
            elapsed_ms    <= 32'd0;
            motion_ticks  <= 3'd0;
            stall_latched <= 1'b0;
        end else if (manual_clear) begin
            state         <= S_IDLE;
            retry_cnt     <= 2'd0;
            timer_ms      <= 32'd0;
            elapsed_ms    <= 32'd0;
            motion_ticks  <= 3'd0;
            stall_latched <= 1'b0;
        end else begin
            if (in_attempt && ms_tick)
                elapsed_ms <= elapsed_ms + 1'b1;

            // 目标归零：取消脱困并清除原堵转检出。
            if (in_attempt && (target_rpm == 16'd0)) begin
                state        <= S_SUCCESS;
                timer_ms     <= 32'd0;
                motion_ticks <= 3'd0;
            end
            // 连续确认两次测速结果才认为成功。
            else if (in_attempt && speed_tick) begin
                if (speed_ok) begin
                    if ((motion_ticks + 1'b1) >= CONFIRM_TICKS) begin
                        state        <= S_SUCCESS;
                        timer_ms     <= 32'd0;
                        motion_ticks <= 3'd0;
                    end else begin
                        motion_ticks <= motion_ticks + 1'b1;
                    end
                end else begin
                    motion_ticks <= 3'd0;
                end
            end
            // 总超时优先于当前脉冲/间隔计数。
            else if (in_attempt && ms_tick &&
                     ((elapsed_ms + 1'b1) >= TOTAL_TIMEOUT_MS)) begin
                state         <= S_FAIL;
                timer_ms      <= 32'd0;
                stall_latched <= 1'b1;
            end
            else if (ms_tick) begin
                case (state)
                    S_IDLE: begin
                        timer_ms <= 32'd0;
                        if (stall_detected && (target_rpm != 16'd0) &&
                            !stall_latched) begin
                            state        <= S_MAIN_PULSE;
                            base_dir     <= target_dir;
                            retry_cnt    <= 2'd0;
                            elapsed_ms   <= 32'd0;
                            motion_ticks <= 3'd0;
                        end
                    end

                    S_MAIN_PULSE: begin
                        if ((timer_ms + 1'b1) >= PULSE_MS) begin
                            timer_ms <= 32'd0;
                            state    <= S_GAP1;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_GAP1: begin
                        if ((timer_ms + 1'b1) >= GAP_MS) begin
                            timer_ms <= 32'd0;
                            state    <= S_OPP_PULSE;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_OPP_PULSE: begin
                        if ((timer_ms + 1'b1) >= PULSE_MS) begin
                            timer_ms <= 32'd0;
                            if (retry_cnt >= MAX_CYCLES - 1) begin
                                retry_cnt <= MAX_CYCLES;
                            end else begin
                                retry_cnt <= retry_cnt + 1'b1;
                            end
                            state <= S_GAP2;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_GAP2: begin
                        if ((timer_ms + 1'b1) >= GAP_MS) begin
                            timer_ms <= 32'd0;
                            if (retry_cnt >= MAX_CYCLES)
                                state <= S_FAIL;
                            else
                                state <= S_MAIN_PULSE;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    S_SUCCESS: begin
                        state      <= S_IDLE;
                        retry_cnt  <= 2'd0;
                        elapsed_ms <= 32'd0;
                    end

                    S_FAIL: begin
                        stall_latched <= 1'b1;
                        timer_ms      <= 32'd0;
                    end

                    default: begin
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end

endmodule
