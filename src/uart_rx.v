// =============================================================
//  uart_rx.v  --  8N1 串口接收（默认 115200）
//  rx 先过两级同步，检测起始位后在中点采样
// =============================================================
module uart_rx #(
    parameter integer CLK_FREQ = 27_000_000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid      // 收到一个字节，单周期脉冲
);

    localparam integer DIV = (CLK_FREQ + BAUD/2) / BAUD;
    localparam integer HALF = DIV / 2;

    reg [2:0]  sync;
    wire       rx_s = sync[1];

    reg [15:0] cnt;
    reg [3:0]  bitn;
    reg [7:0]  sh;
    reg        busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sync <= 3'b111;
        else        sync <= {sync[1:0], rx};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt   <= 16'd0;
            bitn  <= 4'd0;
            sh    <= 8'd0;
            busy  <= 1'b0;
            data  <= 8'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (!busy) begin
                if (!rx_s) begin              // 起始位下降沿
                    busy <= 1'b1;
                    cnt  <= HALF - 1;         // 等到起始位中点
                    bitn <= 4'd0;
                end
            end else begin
                if (cnt >= DIV - 1) begin
                    cnt <= 16'd0;
                    if (bitn == 4'd0) begin
                        // 采样点应在起始位中点；为低才继续
                        if (rx_s) busy <= 1'b0;
                        else      bitn <= 4'd1;
                    end else if (bitn <= 4'd8) begin
                        sh   <= {rx_s, sh[7:1]};  // LSB 先到
                        bitn <= bitn + 1'b1;
                    end else begin
                        busy  <= 1'b0;            // 停止位
                        data  <= sh;
                        valid <= 1'b1;
                    end
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule
