// =============================================================
//  tb_motor_top.v  --  闭环仿真（带电机模型 + 编码器模型）
//
//  模型：
//    占空比 0..1 -> 稳态转速 (duty-0.10)*800 RPM（含 10% 死区）
//    一阶惯性 tau = 250 ms
//    编码器按当前转速实时产生正交 A/B 波形
//
//  仿真脚本：
//    vlib work
//    vlog ../src/*.v tb_motor_top.v
//    vsim -c -do "run -all; quit" tb_motor_top
//
//  输出：
//    控制台打印 + tb_motor.csv（时间/目标/实测/占空比）
// =============================================================
`timescale 1ns/1ps

module tb_motor_top;

    localparam real F_CLK = 27.0e6;
    localparam real TPR   = 1320.0;

    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    // 按键高有效：0=松开，1=按下
    reg btn_sel = 1'b0;
    reg btn_rst = 1'b0;
    reg enc_a   = 1'b0;
    reg enc_b   = 1'b0;

    wire pwm, ain1, ain2, uart_tx;
    wire [5:0] led;

    motor_top #(
        .SELF_TEST(1'b0),     // 用测试台的外部电机模型
        .HDMI_EN(1'b0),
        .POST_EN(1'b0)        // 本测试只验证原有闭环和堵转
    ) dut (
        .clk     (clk),
        .btn_sel (btn_sel),
        .btn_rst (btn_rst),
        .enc_a   (enc_a),
        .enc_b   (enc_b),
        .uart_rx (1'b1),
        .pwm     (pwm),
        .ain1    (ain1),
        .ain2    (ain2),
        .uart_tx (uart_tx),
        .led     (led)
    );

    // ---------------- 电机模型 ----------------
    real    duty      = 0.0;
    real    speed     = 0.0;
    real    load      = 0.0;
    real    ss        = 0.0;
    integer hi_cnt    = 0;
    integer tot_cnt   = 0;
    integer ms_cnt    = 0;
    integer ms_ticks  = 0;

    always @(posedge clk) begin
        tot_cnt = tot_cnt + 1;
        if (pwm) hi_cnt = hi_cnt + 1;

        if (tot_cnt >= 27000) begin
            duty    = hi_cnt / 27000.0;
            hi_cnt  = 0;
            tot_cnt = 0;
        end

        ms_cnt = ms_cnt + 1;
        if (ms_cnt >= 27000) begin
            ms_cnt = 0;
            ms_ticks = ms_ticks + 1;
            if (duty > 0.10)
                ss = (duty - 0.10) * 800.0 - load;
            else
                ss = 0.0 - load;
            if (ss < 0.0) ss = 0.0;
            speed = speed + (ss - speed) * 0.004;   // dt/tau = 1ms/250ms
        end
    end

    // ---------------- 编码器模型 ----------------
    real    enc_phase = 0.0;
    integer quad      = 0;
    integer enc_div   = 0;

    always @(posedge clk) begin
        enc_div = enc_div + 1;
        if (enc_div >= 10) begin
            enc_div   = 0;
            enc_phase = enc_phase + (speed * TPR / 60.0) * 10.0 / F_CLK;
            if (enc_phase >= 1.0) begin
                enc_phase = enc_phase - 1.0;
                quad      = (quad + 1) & 3;
                case (quad)
                    0: {enc_a, enc_b} = 2'b00;
                    1: {enc_a, enc_b} = 2'b01;
                    2: {enc_a, enc_b} = 2'b11;
                    default: {enc_a, enc_b} = 2'b10;
                endcase
            end
        end
    end

    // ---------------- 记录 ----------------
    integer fd;

    initial begin
        fd = $fopen("tb_motor.csv", "w");
        $fdisplay(fd, "time_ms,target,actual,duty");
    end

    always @(posedge clk) begin
        if (dut.speed_tick) begin
            $fdisplay(fd, "%0d,%0d,%0d,%0d",
                      ms_ticks, dut.target_rpm, dut.actual_rpm, dut.duty);
            $display("t=%0d ms  target=%0d  actual=%0d  duty=%0d",
                     ms_ticks, dut.target_rpm, dut.actual_rpm, dut.duty);
        end
    end

    // ---------------- 激励 ----------------
    initial begin
        #2_000_000;                              // 2 ms 上电
        btn_sel = 1'b1; #20_000_000; btn_sel = 1'b0;   // 按 1 次 -> 60 RPM
        #50_000_000;
        btn_sel = 1'b1; #20_000_000; btn_sel = 1'b0;   // 再按 -> 120 RPM
        #500_000_000;                            // 等它稳住

        load = 60.0;                             // 加负载 200 ms
        #200_000_000;
        load = 0.0;                              // 撤掉负载
        #200_000_000;

        // ---- 堵转测试：负载远大于电机能力 ----
        load = 800.0;                            // 超过电机最大出力 -> 真堵转
        #1_500_000_000;                          // 堵转保持 1.5 s（含 500ms 确认时间）
        $display("---- stall check: fault=%b  speed=%0.1f  duty=%0d  (expect fault=1) ----",
                 dut.stall_fault, speed, dut.duty);

        $fclose(fd);
        $display("---- simulation finished ----");
        $finish;
    end

endmodule
