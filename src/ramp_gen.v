// =============================================================
//  ramp_gen.v  --  软启动斜坡发生器
//
//  每个 tick（默认 20 ms）让 ramp_out 向 target_in 靠近 STEP
//  STEP=4、tick=20ms -> 200 RPM/s
//  0 -> 240 RPM 约 1.2 s，起步平缓，抑制电流冲击
// =============================================================
module ramp_gen #(
    parameter [15:0] STEP = 16'd4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick,
    input  wire [15:0] target_in,
    output reg  [15:0] ramp_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ramp_out <= 16'd0;
        else if (tick) begin
            if (ramp_out < target_in)
                ramp_out <= ((target_in - ramp_out) > STEP)
                            ? ramp_out + STEP : target_in;
            else if (ramp_out > target_in)
                ramp_out <= ((ramp_out - target_in) > STEP)
                            ? ramp_out - STEP : target_in;
        end
    end

endmodule
