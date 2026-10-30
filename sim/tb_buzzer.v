// 验证蜂鸣器：按键短鸣 + 报警间歇鸣叫
`timescale 1ns/1ps
module tb_buzzer;
    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    reg  rst_n = 1'b0;
    reg  alarm = 1'b0;
    reg  beep  = 1'b0;
    wire buz;

    reg ms_tick = 1'b0;
    integer cnt = 0;
    always @(posedge clk) begin
        cnt = cnt + 1;
        if (cnt >= 27000) begin
            cnt = 0;
            ms_tick = 1'b1;
        end else begin
            ms_tick = 1'b0;
        end
    end

    buzzer #(.BUZZ_ACTIVE_HIGH(1'b1)) dut (
        .clk(clk), .rst_n(rst_n), .tick_ms(ms_tick),
        .alarm(alarm), .beep_req(beep), .buz(buz)
    );

    initial begin
        #1000;
        rst_n = 1'b1;
        #10_000_000;
        $display("idle          buz=%b (expect 0)", buz);

        beep = 1'b1; #37; beep = 1'b0;
        #20_000_000;
        $display("beep +20ms    buz=%b (expect 1)", buz);
        #100_000_000;
        $display("beep +120ms   buz=%b (expect 0)", buz);

        alarm = 1'b1;
        #150_000_000;
        $display("alarm +150ms  buz=%b (expect 1)", buz);
        #300_000_000;
        $display("alarm +450ms  buz=%b (expect toggled)", buz);
        #300_000_000;
        $display("alarm +750ms  buz=%b (expect toggled)", buz);
        $finish;
    end
endmodule
