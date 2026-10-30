// 验证 串口接收 + 命令解析
`timescale 1ns/1ps
module tb_cmd;
    localparam integer DIV = 234;      // 27MHz / 115200

    reg clk = 1'b0;
    always #18.518 clk = ~clk;

    reg  rst_n = 1'b0;
    reg  rx    = 1'b1;

    wire [7:0]  data;
    wire        valid;
    wire [15:0] speed;
    wire        speed_valid, rev, clr;

    uart_rx #(.CLK_FREQ(27_000_000), .BAUD(115200)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(rx),
        .data(data), .valid(valid)
    );

    cmd_parser u_cmd (
        .clk(clk), .rst_n(rst_n),
        .rx_data(data), .rx_valid(valid),
        .speed(speed), .speed_valid(speed_valid),
        .reverse_pulse(rev), .clear_pulse(clr)
    );

    reg seen_speed = 1'b0, seen_rev = 1'b0, seen_clr = 1'b0;
    always @(posedge clk) begin
        if (speed_valid) seen_speed <= 1'b1;
        if (rev)         seen_rev   <= 1'b1;
        if (clr)         seen_clr   <= 1'b1;
    end

    task send_byte(input [7:0] b);
        integer i;
        begin
            rx = 1'b0; repeat (DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; repeat (DIV) @(posedge clk);
            end
            rx = 1'b1; repeat (DIV) @(posedge clk);
        end
    endtask

    initial begin
        #1000;
        rst_n = 1'b1;
        #1000;

        // "T120\n"
        send_byte(8'h54); send_byte(8'h31); send_byte(8'h32);
        send_byte(8'h30); send_byte(8'h0A);
        #5000;
        $display("T120 -> speed=%0d  valid=%b  (expect 120, 1)", speed, seen_speed);

        seen_speed = 1'b0;
        // "T999\n" 应被限幅到 600
        send_byte(8'h54); send_byte(8'h39); send_byte(8'h39);
        send_byte(8'h39); send_byte(8'h0A);
        #5000;
        $display("T999 -> speed=%0d  valid=%b  (expect 600, 1)", speed, seen_speed);

        // "R\n"
        send_byte(8'h52); send_byte(8'h0A);
        #5000;
        $display("R    -> reverse=%b (expect 1)", seen_rev);

        // "C\n"
        send_byte(8'h43); send_byte(8'h0A);
        #5000;
        $display("C    -> clear=%b (expect 1)", seen_clr);

        // "T0\n"
        seen_speed = 1'b0;
        send_byte(8'h54); send_byte(8'h30); send_byte(8'h0A);
        #5000;
        $display("T0   -> speed=%0d  valid=%b  (expect 0, 1)", speed, seen_speed);

        $finish;
    end
endmodule
