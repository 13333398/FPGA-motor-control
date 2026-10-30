// 单元测试：POST 正常、编码器失败、PWM 失败
`timescale 1ns/1ps

module tb_post_ctrl;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg ms_tick = 1'b0;
    integer ms_div = 0;
    always @(posedge clk) begin
        if (ms_div == 269) begin
            ms_div  <= 0;
            ms_tick <= 1'b1;
        end else begin
            ms_div  <= ms_div + 1;
            ms_tick <= 1'b0;
        end
    end

    reg pass_enc_edge = 1'b0;
    reg fail_enc_edge = 1'b0;
    reg pwm_fail_enc_edge = 1'b0;

    wire [9:0] pass_duty, enc_fail_duty, pwm_fail_duty;
    wire pass_dir, enc_fail_dir, pwm_fail_dir;
    wire pass_test, enc_fail_test, pwm_fail_test;
    wire pass_done, enc_fail_done, pwm_fail_done;
    wire pass_ok, enc_fail_ok, pwm_fail_ok;
    wire pass_valid, enc_fail_valid, pwm_fail_valid;
    wire [7:0] pass_status, enc_fail_status, pwm_fail_status;

    reg pass_pwm = 1'b0;
    reg enc_fail_pwm = 1'b0;
    reg pwm_fail_pwm = 1'b0;

    always @(posedge clk) begin
        if (pass_test)
            pass_pwm <= ~pass_pwm;
        if (enc_fail_test)
            enc_fail_pwm <= ~enc_fail_pwm;
        // pwm_fail_pwm 保持常低，模拟 PWM 输出不翻转。
    end

    post_ctrl #(
        .POWER_ON_MS(2), .ENC_PULSE_MS(3), .ENC_SETTLE_MS(4),
        .PWM_TEST_MS(3), .RESULT_HOLD_MS(2), .PWM_EDGE_MIN(16)
    ) pass_dut (
        .clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
        .enc_edge(pass_enc_edge), .pwm_wave(pass_pwm),
        .post_duty(pass_duty), .post_dir(pass_dir),
        .post_test_mode(pass_test), .post_done(pass_done),
        .post_ok(pass_ok), .post_result_valid(pass_valid),
        .post_status(pass_status)
    );

    post_ctrl #(
        .POWER_ON_MS(2), .ENC_PULSE_MS(3), .ENC_SETTLE_MS(4),
        .PWM_TEST_MS(3), .RESULT_HOLD_MS(2), .PWM_EDGE_MIN(16)
    ) enc_fail_dut (
        .clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
        .enc_edge(fail_enc_edge), .pwm_wave(enc_fail_pwm),
        .post_duty(enc_fail_duty), .post_dir(enc_fail_dir),
        .post_test_mode(enc_fail_test), .post_done(enc_fail_done),
        .post_ok(enc_fail_ok), .post_result_valid(enc_fail_valid),
        .post_status(enc_fail_status)
    );

    post_ctrl #(
        .POWER_ON_MS(2), .ENC_PULSE_MS(3), .ENC_SETTLE_MS(4),
        .PWM_TEST_MS(3), .RESULT_HOLD_MS(2), .PWM_EDGE_MIN(16)
    ) pwm_fail_dut (
        .clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
        .enc_edge(pwm_fail_enc_edge), .pwm_wave(pwm_fail_pwm),
        .post_duty(pwm_fail_duty), .post_dir(pwm_fail_dir),
        .post_test_mode(pwm_fail_test), .post_done(pwm_fail_done),
        .post_ok(pwm_fail_ok), .post_result_valid(pwm_fail_valid),
        .post_status(pwm_fail_status)
    );

    integer cycles = 0;
    reg pass_pulse_sent = 1'b0;
    reg pwm_fail_pulse_sent = 1'b0;

    always @(posedge clk) begin
        cycles = cycles + 1;
        pass_enc_edge <= 1'b0;
        fail_enc_edge <= 1'b0;
        pwm_fail_enc_edge <= 1'b0;

        if ((pass_dut.state == 1) && !pass_pulse_sent) begin
            pass_enc_edge <= 1'b1;
            pass_pulse_sent <= 1'b1;
        end

        // enc_fail_dut 不接边沿；pwm_fail_dut 给边沿，只让 PWM 失败。
        if ((pwm_fail_dut.state == 1) && !pwm_fail_pulse_sent) begin
            pwm_fail_enc_edge <= 1'b1;
            pwm_fail_pulse_sent <= 1'b1;
        end

        if (cycles > 20000) begin
            $display("POST timeout");
            $finish;
        end
    end

    initial begin
        #20 rst_n = 1'b1;

        wait (pass_done && enc_fail_done && pwm_fail_done);
        #20;

        if ((pass_status != 8'h03) || !pass_ok) begin
            $display("FAIL: POST pass status=%h ok=%b", pass_status, pass_ok);
            $finish;
        end
        if ((enc_fail_status != 8'h02) || enc_fail_ok) begin
            $display("FAIL: encoder error status=%h ok=%b",
                     enc_fail_status, enc_fail_ok);
            $finish;
        end
        if ((pwm_fail_status != 8'h01) || pwm_fail_ok) begin
            $display("FAIL: PWM error status=%h ok=%b",
                     pwm_fail_status, pwm_fail_ok);
            $finish;
        end

        $display("PASS: post_ctrl pass/fail cases");
        $finish;
    end
endmodule
