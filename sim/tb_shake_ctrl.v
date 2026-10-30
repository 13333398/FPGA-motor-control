// 单元测试：颤振脱困成功、次数耗尽失败、手动清除
`timescale 1ns/1ps

module tb_shake_ctrl;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg ms_tick = 1'b0;
    integer ms_div = 0;
    always @(posedge clk) begin
        if (ms_div == 9) begin
            ms_div  <= 0;
            ms_tick <= 1'b1;
        end else begin
            ms_div  <= ms_div + 1;
            ms_tick <= 1'b0;
        end
    end

    reg stall_detected = 1'b1;
    reg manual_clear = 1'b0;
    reg [15:0] success_rpm = 16'd0;
    reg [15:0] fail_rpm = 16'd0;
    reg success_tick = 1'b0;
    reg fail_tick = 1'b0;

    wire success_active, success_pwm_dir, success_latched;
    wire success_ok, success_clear;
    wire [9:0] success_pwm_duty;

    wire fail_active, fail_pwm_dir, fail_latched;
    wire fail_ok, fail_clear;
    wire [9:0] fail_pwm_duty;

    shake_ctrl #(
        .MAX_CYCLES(2), .PULSE_MS(3), .GAP_MS(2),
        .TOTAL_TIMEOUT_MS(100), .CONFIRM_TICKS(2)
    ) success_dut (
        .clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
        .speed_tick(success_tick), .stall_detected(stall_detected),
        .manual_clear(manual_clear), .target_rpm(16'd120),
        .target_dir(1'b1), .actual_rpm(success_rpm),
        .active(success_active), .pwm_duty(success_pwm_duty),
        .pwm_dir(success_pwm_dir), .stall_latched(success_latched),
        .recovery_success(success_ok),
        .clear_stall_detected(success_clear)
    );

    shake_ctrl #(
        .MAX_CYCLES(2), .PULSE_MS(3), .GAP_MS(2),
        .TOTAL_TIMEOUT_MS(100), .CONFIRM_TICKS(2)
    ) fail_dut (
        .clk(clk), .rst_n(rst_n), .ms_tick(ms_tick),
        .speed_tick(fail_tick), .stall_detected(stall_detected),
        .manual_clear(manual_clear), .target_rpm(16'd120),
        .target_dir(1'b0), .actual_rpm(fail_rpm),
        .active(fail_active), .pwm_duty(fail_pwm_duty),
        .pwm_dir(fail_pwm_dir), .stall_latched(fail_latched),
        .recovery_success(fail_ok),
        .clear_stall_detected(fail_clear)
    );

    integer cycles = 0;
    integer main_pulses = 0;
    integer opp_pulses = 0;

    always @(posedge clk) begin
        cycles = cycles + 1;
        success_tick <= 1'b0;
        fail_tick <= 1'b0;

        if ((success_dut.state == 1) && (success_pwm_duty != 0))
            main_pulses = main_pulses + 1;
        if ((success_dut.state == 3) && (success_pwm_duty != 0))
            opp_pulses = opp_pulses + 1;

        if ((cycles > 100) && (cycles < 140) && ((cycles % 20) == 0))
            success_rpm <= 16'd20;
        if ((cycles == 105) || (cycles == 125) || (cycles == 145))
            success_tick <= 1'b1;

        if (cycles > 2000) begin
            $display("FAIL: shake timeout");
            $finish;
        end
    end

    initial begin
        #20 rst_n = 1'b1;

        wait (success_ok);
        if (success_latched) begin
            $display("FAIL: successful recovery latched a fault");
            $finish;
        end
        if ((main_pulses == 0) || (opp_pulses == 0)) begin
            $display("FAIL: both shake directions were not exercised");
            $finish;
        end

        wait (fail_latched);
        #20;
        $display("INFO: fail latch after %0d cycles", cycles);

        stall_detected = 1'b0;
        manual_clear = 1'b1;
        #20 manual_clear = 1'b0;
        if (fail_latched) begin
            $display("FAIL: manual clear did not release latch");
            $finish;
        end

        $display("PASS: shake_ctrl recovery and failure cases");
        $finish;
    end
endmodule
