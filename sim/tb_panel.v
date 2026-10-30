// 渲染一帧 hdmi_panel，输出 frame.ppm（用于检查界面布局）
`timescale 1ns/1ps
module tb_panel;
    reg clk = 1'b0;
    always #13.468 clk = ~clk;        // 37.125 MHz 像素时钟

    reg rst_n = 1'b0;

    wire [7:0] r, g, b;
    wire       de, hs, vs;

    hdmi_panel dut (
        .pix_clk(clk), .rst_n(rst_n),
        .target_rpm(16'd180), .actual_rpm(16'd172), .duty(10'd620),
        .run(1'b1), .rev(1'b0), .alarm(1'b0),
        .post_done(1'b1), .post_ok(1'b1),
        .post_result_valid(1'b1), .post_status(8'h03),
        .r(r), .g(g), .b(b), .de(de), .hs(hs), .vs(vs)
    );

    integer f;
    integer i;
    integer px;
    integer line = 0;

    initial begin
        // 预置历史：先 0，再爬升到 180，末尾小扰动
        for (i = 0; i < 512; i = i + 1) begin
            if (i < 80)
                dut.hist[i] = {12'd0, 12'd0};
            else if (i < 220)
                dut.hist[i] = {12'd180, (i - 80) * 12'd1};
            else
                dut.hist[i] = {12'd180, 12'd172};
        end
        px = 0;
        f = $fopen("frame.ppm", "wb");
        $fwrite(f, "P6\n1280 720\n255\n");
    end

    always @(posedge clk) begin
        if (px == 0) rst_n <= 1'b1;      // 第一拍后释放复位

        if (rst_n && de) begin
            $fwrite(f, "%c%c%c", r, g, b);
            px = px + 1;
            if (px == 1280 * 720) begin
                $fclose(f);
                $display("frame done, pixels=%0d", px);
                $finish;
            end
        end
    end
endmodule
