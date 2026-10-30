// =============================================================
//  cmd_parser.v  --  上位机命令解析
//
//  支持的 ASCII 命令（以 \n 或 \r 结尾）：
//    T<数字>   设置目标转速 RPM，例如 "T120\n"（0 = 停机）
//    R         切换正反转（同长按 S2）
//    C         清除堵转报警
//
//  速度上限 600 RPM。
// =============================================================
module cmd_parser (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [15:0] speed,          // 新目标值
    output reg         speed_valid,    // 单周期脉冲
    output reg         reverse_pulse,
    output reg         clear_pulse
);

    localparam [7:0] CH_T = 8'h54;   // 'T'
    localparam [7:0] CH_R = 8'h52;   // 'R'
    localparam [7:0] CH_C = 8'h43;   // 'C'
    localparam [7:0] CH_LF = 8'h0A;
    localparam [7:0] CH_CR = 8'h0D;

    reg        in_num;
    reg [15:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_num        <= 1'b0;
            acc           <= 16'd0;
            speed         <= 16'd0;
            speed_valid   <= 1'b0;
            reverse_pulse <= 1'b0;
            clear_pulse   <= 1'b0;
        end else begin
            speed_valid   <= 1'b0;
            reverse_pulse <= 1'b0;
            clear_pulse   <= 1'b0;

            if (rx_valid) begin
                if (rx_data == CH_T) begin
                    in_num <= 1'b1;
                    acc    <= 16'd0;
                end else if (in_num && (rx_data >= 8'h30) && (rx_data <= 8'h39)) begin
                    if (acc < 16'd600)
                        acc <= acc * 16'd10 + {12'd0, rx_data[3:0]};
                end else if ((rx_data == CH_LF) || (rx_data == CH_CR)) begin
                    if (in_num) begin
                        speed       <= (acc > 16'd600) ? 16'd600 : acc;
                        speed_valid <= 1'b1;
                        in_num      <= 1'b0;
                    end
                end else if (rx_data == CH_R) begin
                    reverse_pulse <= 1'b1;
                    in_num        <= 1'b0;
                end else if (rx_data == CH_C) begin
                    clear_pulse   <= 1'b1;
                    in_num        <= 1'b0;
                end else begin
                    in_num <= 1'b0;
                end
            end
        end
    end

endmodule
