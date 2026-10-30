// 验证 telem 的发送周期，以及帧内容
`timescale 1ns/1ps
module tb_telem;
    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    reg  rst_n = 1'b0;
    wire tx;

    telem #(.CLK_FREQ(27_000_000)) dut (
        .clk(clk), .rst_n(rst_n),
        .target_rpm(16'd120),
        .actual_rpm(16'd118),
        .duty(10'd300),
        .uart_tx(tx)
    );

    integer ticks = 0;
    integer bits  = 0;
    reg     txq   = 1'b1;

    always @(posedge clk) begin
        if (dut.tick) ticks = ticks + 1;
        if (txq !== tx) begin
            bits = bits + 1;
            txq  = tx;
        end
    end

    initial begin
        #1000;
        rst_n = 1'b1;
        #400_000_000;     // 400 ms
        $display("0.4 s : ticks=%0d (expect 0)", ticks);
        #100_000_000;     // 500 ms
        $display("0.5 s : ticks=%0d (expect 1)", ticks);
        #500_000_000;     // 1 s
        $display("1.0 s : ticks=%0d (expect 2)  tx edges=%0d", ticks, bits);
        #1_000_000_000;   // 2 s
        $display("2.0 s : ticks=%0d (expect 4)", ticks);
        $finish;
    end
endmodule
