// 调试用：单独验证 selftest_motor
`timescale 1ns/1ps
module tb_vm;
    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    reg  rst_n = 1'b0;
    wire a, b;

    selftest_motor #(.F_CLK(27_000_000), .TPR(1320)) dut (
        .clk(clk), .rst_n(rst_n), .duty(10'd300),
        .enc_a(a), .enc_b(b)
    );

    integer cyc   = 0;
    integer edges = 0;
    reg     aq    = 1'b0;

    initial begin
        #1000 rst_n = 1'b1;
    end

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (a !== aq) begin
            edges = edges + 1;
            aq = a;
        end
        if ((cyc % 270_000) == 0)
            $display("t=%0d ms  rst=%b tick=%b ss=%0d vq=%0d inc=%0d acc=%0d edges=%0d",
                     cyc/27000, rst_n, dut.ms_tick, dut.ss, dut.vq, dut.inc,
                     dut.acc, edges);
        if (cyc > 27_000_000) $finish;
    end
endmodule
