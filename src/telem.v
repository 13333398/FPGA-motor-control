// =============================================================
//  telem.v  --  串口遥测
//  每 200 ms 发一帧 ASCII（115200 8N1）：
//      Sxxxx Txxxx Dxxx Nxxxx CR LF
//      |     |      +-- PWM 占空比 0..3FF（16 进制）
//      |     +--------- 目标转速 RPM（16 进制）
//      +--------------- 实测转速 RPM（16 进制）
//      N = 帧序号，每帧 +1（用来判断丢帧/终端是否重复打印）
//  用任意串口助手就能看，方便整定 PI 参数。
// =============================================================
module telem #(
    parameter integer CLK_FREQ  = 27_000_000,
    parameter integer PERIOD_MS = 500
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] target_rpm,
    input  wire [15:0] actual_rpm,
    input  wire [9:0]  duty,
    output wire        uart_tx
);

    localparam integer TICK_CYC = CLK_FREQ / 1000 * PERIOD_MS;
    localparam integer FRAME_LEN = 24;

    // ---------- 定时触发 ----------
    reg [31:0] tick_cnt;
    reg        tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 32'd0;
            tick     <= 1'b0;
        end else if (tick_cnt >= TICK_CYC - 1) begin
            tick_cnt <= 32'd0;
            tick     <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick     <= 1'b0;
        end
    end

    // ---------- 字节拼装 ----------
    function [7:0] hexc;
        input [3:0] n;
        begin
            hexc = (n < 4'd10) ? (8'h30 + n) : (8'h37 + n);
        end
    endfunction

    reg  [4:0] fidx;
    reg  [7:0] byte_o;
    reg  [15:0] fcnt;
    reg  sending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fcnt <= 16'd0;
        else if (tick && !sending)
            fcnt <= fcnt + 1'b1;
    end

    always @(*) begin
        case (fidx)
            5'd0:  byte_o = 8'h53;                     // 'S'
            5'd1:  byte_o = hexc(actual_rpm[15:12]);
            5'd2:  byte_o = hexc(actual_rpm[11:8]);
            5'd3:  byte_o = hexc(actual_rpm[7:4]);
            5'd4:  byte_o = hexc(actual_rpm[3:0]);
            5'd5:  byte_o = 8'h20;                     // ' '
            5'd6:  byte_o = 8'h54;                     // 'T'
            5'd7:  byte_o = hexc(target_rpm[15:12]);
            5'd8:  byte_o = hexc(target_rpm[11:8]);
            5'd9:  byte_o = hexc(target_rpm[7:4]);
            5'd10: byte_o = hexc(target_rpm[3:0]);
            5'd11: byte_o = 8'h20;                     // ' '
            5'd12: byte_o = 8'h44;                     // 'D'
            5'd13: byte_o = hexc({2'b00, duty[9:8]});
            5'd14: byte_o = hexc(duty[7:4]);
            5'd15: byte_o = hexc(duty[3:0]);
            5'd16: byte_o = 8'h20;                     // ' '
            5'd17: byte_o = 8'h4E;                     // 'N'
            5'd18: byte_o = hexc(fcnt[15:12]);
            5'd19: byte_o = hexc(fcnt[11:8]);
            5'd20: byte_o = hexc(fcnt[7:4]);
            5'd21: byte_o = hexc(fcnt[3:0]);
            5'd22: byte_o = 8'h0D;                     // CR
            default: byte_o = 8'h0A;                   // LF
        endcase
    end

    reg  tx_send;
    wire tx_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sending <= 1'b0;
            fidx    <= 5'd0;
            tx_send <= 1'b0;
        end else begin
            tx_send <= 1'b0;
            if (!sending) begin
                if (tick) begin
                    sending <= 1'b1;
                    fidx    <= 5'd0;
                end
            end else if (!tx_busy && !tx_send) begin
                tx_send <= 1'b1;
                if (fidx == FRAME_LEN - 1) begin
                    sending <= 1'b0;
                    fidx    <= 5'd0;
                end else begin
                    fidx <= fidx + 1'b1;
                end
            end
        end
    end

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (115200)
    ) u_uart (
        .clk  (clk),
        .rst_n(rst_n),
        .data (byte_o),
        .send (tx_send),
        .busy (tx_busy),
        .tx   (uart_tx)
    );

endmodule
