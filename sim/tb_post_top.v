// 顶层集成测试：POST 通过后释放 PI；编码器无信号时阻断启动
`timescale 1ns/1ps

module tb_post_top;
    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    reg btn_sel_pass = 1'b0;
    reg btn_rst = 1'b0;
    reg btn_sel_noenc = 1'b0;

    wire pwm_pass, ain1_pass, ain2_pass, uart_tx_pass;
    wire [5:0] led_pass;
    wire pwm_noenc, ain1_noenc, ain2_noenc, uart_tx_noenc;
    wire [5:0] led_noenc;

    motor_top #(
        .SELF_TEST(1'b1), .HDMI_EN(1'b0), .POST_EN(1'b1),
        .POST_POWER_ON_MS(2), .POST_ENC_PULSE_MS(100),
        .POST_ENC_SETTLE_MS(20), .POST_PWM_TEST_MS(3),
        .POST_RESULT_HOLD_MS(2)
    ) pass_dut (
        .clk(clk), .btn_sel(btn_sel_pass), .btn_rst(btn_rst),
        .enc_a(1'b0), .enc_b(1'b0), .uart_rx(1'b1),
        .pwm(pwm_pass), .ain1(ain1_pass), .ain2(ain2_pass),
        .uart_tx(uart_tx_pass), .buz(), .led(led_pass),
        .tmds_clk_p(), .tmds_clk_n(),
        .tmds_data_p(), .tmds_data_n()
    );

    motor_top #(
        .SELF_TEST(1'b0), .HDMI_EN(1'b0), .POST_EN(1'b1),
        .POST_POWER_ON_MS(2), .POST_ENC_PULSE_MS(20),
        .POST_ENC_SETTLE_MS(10), .POST_PWM_TEST_MS(3),
        .POST_RESULT_HOLD_MS(2)
    ) noenc_dut (
        .clk(clk), .btn_sel(btn_sel_noenc), .btn_rst(btn_rst),
        .enc_a(1'b0), .enc_b(1'b0), .uart_rx(1'b1),
        .pwm(pwm_noenc), .ain1(ain1_noenc), .ain2(ain2_noenc),
        .uart_tx(uart_tx_noenc), .buz(), .led(led_noenc),
        .tmds_clk_p(), .tmds_clk_n(),
        .tmds_data_p(), .tmds_data_n()
    );

    initial begin
        wait (pass_dut.post_done && noenc_dut.post_done);
        #1000;

        if (!pass_dut.post_ok || (pass_dut.post_status != 8'h03)) begin
            $display("FAIL: self-test POST status=%h ok=%b",
                     pass_dut.post_status, pass_dut.post_ok);
            $finish;
        end
        if (noenc_dut.post_ok || (noenc_dut.post_status != 8'h02)) begin
            $display("FAIL: no-encoder POST status=%h ok=%b",
                     noenc_dut.post_status, noenc_dut.post_ok);
            $finish;
        end
        if (noenc_dut.post_control_enable || noenc_dut.run) begin
            $display("FAIL: failed POST did not block main control");
            $finish;
        end

        // POST 通过后短按一次，主控制应切到 60 RPM 并进入 PI。
        btn_sel_pass = 1'b1;
        #20_000_000;
        btn_sel_pass = 1'b0;

        wait (pass_dut.actual_rpm >= 16'd40);
        $display("INFO: closed loop released after POST, rpm=%0d",
                 pass_dut.actual_rpm);

        $display("PASS: POST top-level release and block cases");
        $finish;
    end
endmodule
