// 渲染 POST 两项均失败页面，输出 post_error_frame.ppm
`timescale 1ns/1ps

module tb_post_error_panel;
    reg clk = 1'b0;
    always #13.468 clk = ~clk;

    reg rst_n = 1'b0;
    wire [7:0] r, g, b;
    wire de, hs, vs;

    hdmi_panel dut (
        .pix_clk(clk), .rst_n(rst_n),
        .target_rpm(16'd0), .actual_rpm(16'd0), .duty(10'd0),
        .run(1'b0), .rev(1'b0), .alarm(1'b0),
        .post_done(1'b0), .post_ok(1'b0),
        .post_result_valid(1'b1), .post_status(8'h00),
        .r(r), .g(g), .b(b), .de(de), .hs(hs), .vs(vs)
    );

    integer f;
    integer px = 0;

    initial begin
        f = $fopen("post_error_frame.ppm", "wb");
        $fwrite(f, "P6\n1280 720\n255\n");
    end

    always @(posedge clk) begin
        if (px == 0)
            rst_n <= 1'b1;
        if (rst_n && de) begin
            $fwrite(f, "%c%c%c", r, g, b);
            px = px + 1;
            if (px == 1280 * 720) begin
                $fclose(f);
                $display("POST error frame done");
                $finish;
            end
        end
    end
endmodule
