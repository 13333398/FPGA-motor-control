// =============================================================
//  motor_top.v  --  Tang Nano 20K 直流电机 PI 闭环调速（顶层）
//
//  按键：
//    S1 (88) 复位 / 清除堵转报警
//    S2 (87) 短按：切目标 0 -> 60 -> 120 -> 180 -> 240 -> 0
//            长按 >=1 秒：切换正转 / 反转（先减速到 0 再换向）
//
//  增强功能：
//    软启动：目标经 200 RPM/s 斜坡，0 -> 240 约 1.2 s
//    堵转保护：占空比 > 88% 且转速 < 10 RPM 持续 500 ms
//              -> 先进行 3 个正反颤振周期，成功则回 PI
//              -> 失败才切断输出、锁存报警，按 S1 解除
//    上电自检：检查编码器边沿和 PWM 内部翻转，HDMI 显示结果
//
//  LED（板载低电平点亮，代码已取反：亮 = 状态成立）：
//    led0 心跳
//    led1 运行中
//    led2 转速 > 90 RPM
//    led3 转速 > 150 RPM
//    led4 转速 > 210 RPM
//    led5 反转指示（亮 = 反转）
//
//  接线（TB6612）：
//    PWMA <- pwm(27)   AIN1 <- ain1(28)   AIN2 <- ain2(29)
//    STBY 接 3.3V      VM 接电机电源      GND 与板子共地
//  编码器：A -> 25   B -> 26   VCC 3.3V
//  串口：115200 8N1，每 500 ms 一帧 Sxxxx Txxxx Dxxx Nxxxx
// =============================================================
module motor_top #(
    parameter SELF_TEST         = 1'b0, // 0 = 用真实编码器
    parameter HDMI_EN           = 1'b1, // 1 = 打开 HDMI 面板
    parameter POST_EN           = 1'b1, // 1 = 上电执行 POST
    parameter POST_BLOCK_ON_FAIL = 1'b1, // 1 = POST 失败禁止主控制
    parameter integer POST_POWER_ON_MS    = 100,
    parameter integer POST_ENC_PULSE_MS   = 120,
    parameter integer POST_ENC_SETTLE_MS  = 250,
    parameter integer POST_PWM_TEST_MS    = 10,
    parameter integer POST_RESULT_HOLD_MS = 3000,
    parameter integer SHAKE_MAX_CYCLES     = 3,
    parameter integer SHAKE_PULSE_MS       = 120,
    parameter integer SHAKE_GAP_MS         = 200,
    parameter integer SHAKE_TIMEOUT_MS     = 3000,
    parameter [9:0]   SHAKE_DUTY           = 10'd350
)(
    input  wire       clk,        // 27 MHz, pin 4
    input  wire       btn_sel,    // pin 87  S2
    input  wire       btn_rst,    // pin 88  S1
    input  wire       enc_a,      // pin 25
    input  wire       enc_b,      // pin 26
    input  wire       uart_rx,    // pin 70  上位机命令
    output wire       pwm,        // pin 27
    output wire       ain1,       // pin 28
    output wire       ain2,       // pin 29
    output wire       uart_tx,    // pin 69
    output wire       buz,        // pin 48  蜂鸣器
    output wire       tmds_clk_p, // pin 33
    output wire       tmds_clk_n, // pin 34
    output wire [2:0] tmds_data_p,// pins 35/37/39
    output wire [2:0] tmds_data_n,// pins 36/38/40
    output wire [5:0] led         // pins 15..20
);

    localparam integer F_CLK   = 27_000_000;
    localparam integer GATE_MS = 20;
    // GA12-N20：7 线编码器 x 4 倍频 x 50 减速比 = 1400
    localparam integer TPR     = 1400;

    // 板载按键高电平有效（实测）
    localparam BTN_ACTIVE_LOW   = 1'b0;

    // 调试开关：非 0 时强制开环占空比（验证 PWM / 驱动板用）
    localparam [9:0]  FORCE_DUTY = 10'd0;    // 0 = 正常闭环（开环调试时改成 300）

    // 软启动：每 20 ms 变化 4 RPM -> 200 RPM/s
    localparam [15:0] RAMP_STEP  = 16'd4;

    // 堵转判据：占空比阈值
    localparam [9:0]  DUTY_STALL = 10'd900;
    // 蜂鸣器模块：1 = 高电平响；低电平触发的模块改成 0
    localparam        BUZZ_ACTIVE_HIGH = 1'b1;

    // -------------------- 信号声明 --------------------
    reg  [15:0] por_cnt = 16'd0;
    reg         por_n   = 1'b0;

    wire        sel_raw;
    wire        rst_raw;
    wire        sel_pressed;
    wire        rst_pressed;
    wire        rst_n;

    reg  [15:0] ms_div;
    reg         ms_tick;

    reg  [10:0] hold_ms;
    reg         sel_q;
    reg         sel_long_done;
    reg         preset_pulse;
    reg         dir_toggle;

    reg  [2:0]  preset_idx;
    reg  [15:0] target_rpm;
    reg  [15:0] target_set;
    reg  [15:0] preset_next_value;

    wire [7:0]  uart_data;
    wire        uart_valid;
    wire [15:0] cmd_speed;
    wire        cmd_speed_valid;
    wire        cmd_rev;
    wire        cmd_clr;
    wire        dir_toggle_any;
    wire        fault_clear;

    reg         dir_req;
    reg         dir_cur;
    reg         dir_pending;

    wire [15:0] ramp_in;
    wire [15:0] ramp_rpm;
    wire        stall_fault;
    wire        run_cmd;
    wire        run;

    wire signed [23:0] pos;
    wire        enc_edge;
    wire        vm_a, vm_b;
    wire        enc_a_use, enc_b_use;
    wire [15:0] actual_rpm;
    wire        speed_dir;
    wire        speed_tick;

    wire [9:0]  duty_pi;
    wire [9:0]  normal_duty;
    wire [9:0]  duty;
    wire        pwm_wave;
    wire        pwm_dir;

    // POST 旁路接口
    wire [9:0]  post_duty;
    wire        post_dir;
    wire        post_test_mode;
    wire        post_done;
    wire        post_ok;
    wire        post_result_valid;
    wire [7:0]  post_status;
    wire        post_control_enable;

    // 颤振脱困旁路接口
    wire        shake_active;
    wire [9:0]  shake_pwm_duty;
    wire        shake_pwm_dir;
    wire        shake_stall_latched;
    wire        shake_recovery_success;
    wire        shake_clear_stall_detected;

    reg  [23:0] hb;
    wire [5:0]  led_normal;

    // -------------------- 上电复位 --------------------
    always @(posedge clk) begin
        if (por_cnt != 16'hFFFF) begin
            por_cnt <= por_cnt + 1'b1;
            por_n   <= 1'b0;
        end else begin
            por_n   <= 1'b1;
        end
    end

    // -------------------- 按键同步 + 消抖 --------------------
    assign sel_raw = BTN_ACTIVE_LOW ? ~btn_sel : btn_sel;
    assign rst_raw = BTN_ACTIVE_LOW ? ~btn_rst : btn_rst;

    debounce u_db_sel (.clk(clk), .rst_n(por_n), .din(sel_raw), .dout(sel_pressed));
    debounce u_db_rst (.clk(clk), .rst_n(por_n), .din(rst_raw), .dout(rst_pressed));

    assign rst_n = por_n & ~rst_pressed;

    // -------------------- 上位机串口命令（70 脚 RX） --------------------
    uart_rx #(
        .CLK_FREQ(F_CLK), .BAUD(115200)
    ) u_urx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx),
        .data(uart_data), .valid(uart_valid)
    );

    cmd_parser u_cmd (
        .clk(clk), .rst_n(rst_n),
        .rx_data(uart_data), .rx_valid(uart_valid),
        .speed(cmd_speed), .speed_valid(cmd_speed_valid),
        .reverse_pulse(cmd_rev), .clear_pulse(cmd_clr)
    );

    assign dir_toggle_any = dir_toggle | cmd_rev;
    assign fault_clear    = cmd_clr;

    // -------------------- 1 ms 时基 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div  <= 16'd0;
            ms_tick <= 1'b0;
        end else if (ms_div >= 16'd26999) begin
            ms_div  <= 16'd0;
            ms_tick <= 1'b1;
        end else begin
            ms_div  <= ms_div + 1'b1;
            ms_tick <= 1'b0;
        end
    end

    // POST 在真正上电复位后只执行一次。S1 可暂停主控制，
    // 但不会再次给电机试探脉冲。
    generate
    if (POST_EN) begin : g_post
        post_ctrl #(
            .POWER_ON_MS   (POST_POWER_ON_MS),
            .ENC_PULSE_MS  (POST_ENC_PULSE_MS),
            .ENC_SETTLE_MS (POST_ENC_SETTLE_MS),
            .PWM_TEST_MS   (POST_PWM_TEST_MS),
            .RESULT_HOLD_MS(POST_RESULT_HOLD_MS)
        ) u_post (
            .clk              (clk),
            .rst_n            (por_n),
            .ms_tick          (ms_tick),
            .enc_edge         (enc_edge),
            .pwm_wave         (pwm_wave),
            .post_duty        (post_duty),
            .post_dir         (post_dir),
            .post_test_mode   (post_test_mode),
            .post_done        (post_done),
            .post_ok          (post_ok),
            .post_result_valid(post_result_valid),
            .post_status      (post_status)
        );
    end else begin : g_no_post
        assign post_duty         = 10'd0;
        assign post_dir          = 1'b0;
        assign post_test_mode    = 1'b0;
        assign post_done         = 1'b1;
        assign post_ok           = 1'b1;
        assign post_result_valid = 1'b1;
        assign post_status       = 8'h03;
    end
    endgenerate

    assign post_control_enable =
        post_done && (post_ok || !POST_BLOCK_ON_FAIL);

    // -------------------- S2：短按切档 / 长按切方向 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_ms       <= 11'd0;
            sel_q         <= 1'b0;
            sel_long_done <= 1'b0;
            preset_pulse  <= 1'b0;
            dir_toggle    <= 1'b0;
        end else begin
            preset_pulse <= 1'b0;
            dir_toggle   <= 1'b0;
            sel_q        <= sel_pressed;

            if (sel_pressed && !sel_q) begin          // 刚按下
                hold_ms       <= 11'd0;
                sel_long_done <= 1'b0;
            end else if (sel_pressed) begin            // 按住中
                if (ms_tick && hold_ms < 11'd1000)
                    hold_ms <= hold_ms + 1'b1;
                if (ms_tick && (hold_ms == 11'd999) && !sel_long_done) begin
                    sel_long_done <= 1'b1;
                    dir_toggle    <= 1'b1;             // 长按 -> 切方向
                end
            end else if (sel_q) begin                  // 刚松开
                if (!sel_long_done)
                    preset_pulse <= 1'b1;              // 短按 -> 切档
            end
        end
    end

    // -------------------- 目标转速档位 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            preset_idx <= 3'd0;
        else if (preset_pulse)
            preset_idx <= (preset_idx == 3'd4) ? 3'd0 : preset_idx + 1'b1;
    end

    always @(*) begin
        case (preset_idx)
            3'd0:    target_rpm = 16'd0;
            3'd1:    target_rpm = 16'd60;
            3'd2:    target_rpm = 16'd120;
            3'd3:    target_rpm = 16'd180;
            default: target_rpm = 16'd240;
        endcase
    end

    // 下一次按键切换后应该得到的值
    always @(*) begin
        case ((preset_idx == 3'd4) ? 3'd0 : (preset_idx + 1'b1))
            3'd0:    preset_next_value = 16'd0;
            3'd1:    preset_next_value = 16'd60;
            3'd2:    preset_next_value = 16'd120;
            3'd3:    preset_next_value = 16'd180;
            default: preset_next_value = 16'd240;
        endcase
    end

    // 目标值：按键和上位机都能改，谁后到听谁的
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            target_set <= 16'd0;
        else if (cmd_speed_valid)
            target_set <= cmd_speed;
        else if (preset_pulse)
            target_set <= preset_next_value;
    end

    // -------------------- 方向控制：先停稳再换向 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_req     <= 1'b0;
            dir_cur     <= 1'b0;
            dir_pending <= 1'b0;
        end else if (FORCE_DUTY != 10'd0) begin
            // 开环调试模式（FORCE_DUTY≠0）不支持换向：
            // 否则 dir_pending 永远等不到 duty=0，会卡死
            dir_pending <= 1'b0;
        end else begin
            if (dir_toggle_any && post_control_enable && !shake_active) begin
                dir_req     <= ~dir_req;
                dir_pending <= 1'b1;
            end
            if (dir_pending && post_control_enable && !shake_active &&
                (ramp_rpm == 16'd0) && (duty == 10'd0)) begin
                dir_cur     <= dir_req;
                dir_pending <= 1'b0;
            end
        end
    end

    // -------------------- 软启动斜坡 --------------------
    assign ramp_in =
        (dir_pending || stall_fault || shake_stall_latched ||
         !post_control_enable) ?
        16'd0 : target_set;

    ramp_gen #(.STEP(RAMP_STEP)) u_ramp (
        .clk(clk), .rst_n(rst_n), .tick(speed_tick),
        .target_in(ramp_in), .ramp_out(ramp_rpm)
    );

    assign run_cmd = (ramp_rpm != 16'd0) ||
                     (FORCE_DUTY != 10'd0);
    assign run = run_cmd && post_control_enable && !shake_stall_latched;

    // -------------------- 编码器（可切片内虚拟电机） --------------------
    selftest_motor #(.F_CLK(F_CLK), .TPR(TPR)) u_vm (
        .clk(clk), .rst_n(rst_n),
        .duty(post_test_mode ? 10'd0 : duty),
        .dir(pwm_dir),
        .enc_a(vm_a), .enc_b(vm_b)
    );

    assign enc_a_use = SELF_TEST ? vm_a : enc_a;
    assign enc_b_use = SELF_TEST ? vm_b : enc_b;

    quad_dec u_quad (
        .clk(clk), .rst_n(rst_n),
        .enc_a(enc_a_use), .enc_b(enc_b_use),
        .pos(pos), .edge_pulse(enc_edge)
    );

    // -------------------- 测速 --------------------
    speed_m #(.F_CLK(F_CLK), .GATE_MS(GATE_MS), .TPR(TPR)) u_speed (
        .clk(clk), .rst_n(rst_n), .pos(pos),
        .rpm(actual_rpm), .dir(speed_dir), .tick(speed_tick)
    );

    // -------------------- PI 控制器 --------------------
    pi_ctrl u_pi (
        .clk(clk), .rst_n(rst_n),
        .tick(speed_tick),
        .run(run && !stall_fault && !shake_active &&
             !shake_stall_latched),
        .target_rpm(ramp_rpm),
        .actual_rpm(actual_rpm),
        .duty(duty_pi)
    );

    assign normal_duty =
        (FORCE_DUTY != 10'd0) ? FORCE_DUTY : duty_pi;

    // -------------------- 堵转保护 --------------------
    stall_prot #(
        .TRIP_MS (500),
        .TICK_MS (GATE_MS),
        .DUTY_TH (DUTY_STALL),
        .SPEED_TH(16'd10),
        .TGT_MIN (16'd40)
    ) u_stall (
        .clk(clk), .rst_n(rst_n), .tick(speed_tick),
        .enable(run && !shake_active && (FORCE_DUTY == 10'd0)),
        .clear(fault_clear | shake_clear_stall_detected),
        .target_ramp(ramp_rpm),
        .actual_rpm(actual_rpm),
        .duty(duty),
        .fault(stall_fault)
    );

    // -------------------- 颤振脱困 --------------------
    shake_ctrl #(
        .MAX_CYCLES      (SHAKE_MAX_CYCLES),
        .PULSE_MS        (SHAKE_PULSE_MS),
        .GAP_MS          (SHAKE_GAP_MS),
        .TOTAL_TIMEOUT_MS(SHAKE_TIMEOUT_MS),
        .CONFIRM_TICKS   (2),
        .SHAKE_DUTY      (SHAKE_DUTY)
    ) u_shake (
        .clk(clk), .rst_n(rst_n),
        .ms_tick(ms_tick), .speed_tick(speed_tick),
        .stall_detected(stall_fault),
        .manual_clear(fault_clear),
        .target_rpm(target_set),
        .target_dir(dir_cur),
        .actual_rpm(actual_rpm),
        .active(shake_active),
        .pwm_duty(shake_pwm_duty),
        .pwm_dir(shake_pwm_dir),
        .stall_latched(shake_stall_latched),
        .recovery_success(shake_recovery_success),
        .clear_stall_detected(shake_clear_stall_detected)
    );

    // 输出仲裁：POST -> 颤振 -> 正常 PI -> 故障关闭。
    // PI 内部计算和时序没有被修改。
    assign duty =
        post_test_mode          ? post_duty :
        !post_done              ? post_duty :
        !post_control_enable    ? 10'd0 :
        shake_stall_latched     ? 10'd0 :
        shake_active            ? shake_pwm_duty :
                                  normal_duty;

    assign pwm_dir =
        !post_done              ? post_dir :
        shake_active            ? shake_pwm_dir :
                                  dir_cur;

    // -------------------- PWM + TB6612 --------------------
    pwm_gen #(.F_CLK(F_CLK)) u_pwm (
        .clk(clk), .rst_n(rst_n),
        .dir(pwm_dir),
        .duty(duty),
        .test_mode(post_test_mode),
        .pwm(pwm_wave), .ain1(ain1), .ain2(ain2)
    );
    assign pwm = pwm_wave;

    // -------------------- 串口遥测（T 用斜坡值，能看到软启动） --------------------
    telem #(.CLK_FREQ(F_CLK)) u_telem (
        .clk(clk), .rst_n(rst_n),
        .target_rpm(ramp_rpm),
        .actual_rpm(actual_rpm),
        .duty(duty),
        .uart_tx(uart_tx)
    );

    // -------------------- 蜂鸣器 --------------------
    buzzer #(
        .BUZZ_ACTIVE_HIGH(BUZZ_ACTIVE_HIGH)
    ) u_buz (
        .clk(clk), .rst_n(rst_n), .tick_ms(ms_tick),
        .alarm(shake_stall_latched),
        .beep_req(preset_pulse),      // 切档时"嘀"一声
        .buz(buz)
    );

    // -------------------- LED：心跳 / 运行 / 转速条 / 方向 --------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb <= 24'd0;
        else        hb <= hb + 1'b1;
    end

    assign led_normal[0] = ~hb[23];                  // 心跳
    assign led_normal[1] = ~run;                     // 运行中
    assign led_normal[2] = ~(actual_rpm > 16'd90);   // 转速条 1
    assign led_normal[3] = ~(actual_rpm > 16'd150);  // 转速条 2
    assign led_normal[4] = ~(actual_rpm > 16'd210);  // 转速条 3
    assign led_normal[5] = ~pwm_dir;                 // 亮 = 反转

    // 堵转报警：6 个灯一起约 3 Hz 闪烁（0 = 亮，LED 低电平点亮）
    assign led = shake_stall_latched ? {6{hb[22]}} : led_normal;

    // -------------------- HDMI 实时面板 --------------------
    generate
    if (HDMI_EN) begin : g_hdmi
        wire serial_clk;
        wire pix_clk;
        wire pll_lock;
        wire hdmi_rst_n = rst_n & pll_lock;

        TMDS_rPLL u_tmds_rpll (
            .clkin (clk),
            .clkout(serial_clk),
            .lock  (pll_lock)
        );

        CLKDIV u_clkdiv (
            .RESETN(hdmi_rst_n),
            .HCLKIN(serial_clk),
            .CLKOUT(pix_clk),
            .CALIB (1'b1)
        );
        defparam u_clkdiv.DIV_MODE = "5";
        defparam u_clkdiv.GSREN    = "false";

        wire [7:0] v_r, v_g, v_b;
        wire       v_de, v_hs, v_vs;

        hdmi_panel u_panel (
            .pix_clk(pix_clk), .rst_n(hdmi_rst_n),
            .target_rpm(ramp_rpm), .actual_rpm(actual_rpm), .duty(duty),
            .run(run), .rev(pwm_dir), .alarm(shake_stall_latched),
            .post_done(post_done), .post_ok(post_ok),
            .post_result_valid(post_result_valid),
            .post_status(post_status),
            .r(v_r), .g(v_g), .b(v_b),
            .de(v_de), .hs(v_hs), .vs(v_vs)
        );

        DVI_TX_Top u_dvi (
            .I_rst_n      (hdmi_rst_n),
            .I_serial_clk (serial_clk),
            .I_rgb_clk    (pix_clk),
            .I_rgb_vs     (v_vs),
            .I_rgb_hs     (v_hs),
            .I_rgb_de     (v_de),
            .I_rgb_r      (v_r),
            .I_rgb_g      (v_g),
            .I_rgb_b      (v_b),
            .O_tmds_clk_p (tmds_clk_p),
            .O_tmds_clk_n (tmds_clk_n),
            .O_tmds_data_p(tmds_data_p),
            .O_tmds_data_n(tmds_data_n)
        );
    end else begin : g_no_hdmi
        assign tmds_clk_p  = 1'b0;
        assign tmds_clk_n  = 1'b0;
        assign tmds_data_p = 3'b000;
        assign tmds_data_n = 3'b000;
    end
    endgenerate

endmodule
