// =============================================================
//  stall_prot.v  --  堵转保护
//
//  判据（持续 TRIP_MS）：
//    目标 >= TGT_MIN
//    且 占空比 > DUTY_TH（接近满幅）
//    且 实际转速 < SPEED_TH（几乎不转）
//  -> fault 置 1 并保持，直到复位（S1）
//
//  500 ms 的确认时间可以过滤启动瞬间的误判；
//  软启动让占空比缓慢上升，也进一步降低误报概率。
// =============================================================
module stall_prot #(
    parameter integer  TRIP_MS  = 500,
    parameter integer  TICK_MS  = 20,
    parameter [9:0]    DUTY_TH  = 10'd900,
    parameter [15:0]   SPEED_TH = 16'd10,
    parameter [15:0]   TGT_MIN  = 16'd40
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick,
    input  wire        enable,
    input  wire        clear,     // 1 = 清除报警（上位机 C 命令）
    input  wire [15:0] target_ramp,
    input  wire [15:0] actual_rpm,
    input  wire [9:0]  duty,
    output reg         fault
);

    localparam integer TRIP_TICKS = (TRIP_MS + TICK_MS - 1) / TICK_MS;

    reg [15:0] cnt;

    wire cond = enable &&
                (target_ramp >= TGT_MIN) &&
                (duty > DUTY_TH) &&
                (actual_rpm < SPEED_TH);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt   <= 16'd0;
            fault <= 1'b0;
        end else if (clear) begin
            cnt   <= 16'd0;
            fault <= 1'b0;
        end else if (tick && !fault) begin
            if (cond) begin
                if (cnt >= TRIP_TICKS - 1)
                    fault <= 1'b1;       // 锁定报警，只能按 S1 复位
                else
                    cnt <= cnt + 1'b1;
            end else begin
                cnt <= 16'd0;
            end
        end
    end

endmodule
