// =============================================================
//  tb_selftest.v  --  片内虚拟电机自检
//  不接任何外设，验证 按键 -> PI -> PWM -> 虚拟电机 -> 编码器 -> 测速
//  这条完整闭环在芯片内部跑通。
// =============================================================
`timescale 1ns/1ps

module tb_selftest;

    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    // 按键高有效：0=松开，1=按下
    reg btn_sel = 1'b0;
    reg btn_rst = 1'b0;

    wire pwm, ain1, ain2, uart_tx;
    wire [5:0] led;

    motor_top #(
        .SELF_TEST(1'b1),
        .HDMI_EN(1'b0),
        .POST_EN(1'b0)
    ) dut (
        .clk     (clk),
        .btn_sel (btn_sel),
        .btn_rst (btn_rst),
        .enc_a   (1'b0),      // 外部编码器不用
        .enc_b   (1'b0),
        .uart_rx (1'b1),
        .pwm     (pwm),
        .ain1    (ain1),
        .ain2    (ain2),
        .uart_tx (uart_tx),
        .led     (led)
    );

    integer ms_cnt  = 0;
    integer ms_ticks = 0;
    integer fd;

    initial begin
        fd = $fopen("tb_selftest.csv", "w");
        $fdisplay(fd, "time_ms,target,actual,duty");
    end

    always @(posedge clk) begin
        ms_cnt = ms_cnt + 1;
        if (ms_cnt >= 27000) begin
            ms_cnt = 0;
            ms_ticks = ms_ticks + 1;
        end

        if (dut.speed_tick) begin
            $fdisplay(fd, "%0d,%0d,%0d,%0d",
                      ms_ticks, dut.target_rpm, dut.actual_rpm, dut.duty);
            $display("t=%0d ms  target=%0d  actual=%0d  duty=%0d",
                     ms_ticks, dut.target_rpm, dut.actual_rpm, dut.duty);
        end
    end

    initial begin
        #2_000_000;
        btn_sel = 1'b1; #20_000_000; btn_sel = 1'b0;   // 60 RPM
        #300_000_000;
        btn_sel = 1'b1; #20_000_000; btn_sel = 1'b0;   // 120 RPM
        #400_000_000;

        // 长按 1.2 s -> 切方向（先减速到 0 再反向）
        btn_sel = 1'b1; #1_200_000_000; btn_sel = 1'b0;
        #600_000_000;
        $display("---- dir check: dir_cur=%b actual=%0d (expect dir_cur=1) ----",
                 dut.dir_cur, dut.actual_rpm);

        $fclose(fd);
        $display("---- selftest finished ----");
        $finish;
    end

endmodule
