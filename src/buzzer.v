// =============================================================
//  buzzer.v  --  蜂鸣器驱动
//
//  alarm=1    : 报警，300 ms 响 / 300 ms 停，反复
//  beep_req=1 : 单次短鸣 80 ms（按键反馈）
//
//  适配"有源蜂鸣器模块"（自带三极管，GPIO 只给控制电平）。
//  BUZZ_ACTIVE_HIGH = 1 表示高电平响；低电平触发的模块改成 0。
// =============================================================
module buzzer #(
    parameter BUZZ_ACTIVE_HIGH = 1'b1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tick_ms,      // 1 ms 脉冲
    input  wire alarm,
    input  wire beep_req,     // 单周期脉冲
    output wire buz
);

    // -------- 报警节拍：300 ms 翻转 --------
    reg [9:0] alarm_ms;
    reg       alarm_phase;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm_ms    <= 10'd0;
            alarm_phase <= 1'b1;      // 报警一出现就立即响
        end else if (tick_ms) begin
            if (alarm) begin
                if (alarm_ms >= 10'd299) begin
                    alarm_ms    <= 10'd0;
                    alarm_phase <= ~alarm_phase;
                end else begin
                    alarm_ms <= alarm_ms + 1'b1;
                end
            end else begin
                alarm_ms    <= 10'd0;
                alarm_phase <= 1'b1;  // 待机时保持"响"相位，报警立刻发声
            end
        end
    end

    // -------- 按键短鸣：80 ms --------
    reg [7:0] beep_ms;
    reg       beep_on;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beep_ms <= 8'd0;
            beep_on <= 1'b0;
        end else if (beep_req) begin
            beep_ms <= 8'd80;
            beep_on <= 1'b1;
        end else if (tick_ms && beep_on) begin
            if (beep_ms <= 8'd1) begin
                beep_on <= 1'b0;
                beep_ms <= 8'd0;
            end else begin
                beep_ms <= beep_ms - 1'b1;
            end
        end
    end

    wire drive = (alarm & alarm_phase) | beep_on;

    assign buz = BUZZ_ACTIVE_HIGH ? drive : ~drive;

endmodule
