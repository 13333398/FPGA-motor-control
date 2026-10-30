// =============================================================
//  quad_dec.v  --  正交编码器四倍频 + 鉴向
//  输入 A/B 两级同步后，按 Gray 码状态迁移累加位置。
//  正转一个完整周期：00 -> 01 -> 11 -> 10 -> 00  (pos +1)
//  反转反向走，pos -1。
//  位置是"计数"，不是角度；转速由 speed_m 定时取差值算。
// =============================================================
module quad_dec (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              enc_a,
    input  wire              enc_b,
    output reg signed [23:0] pos,
    output reg               edge_pulse
);

    reg [1:0] a_sync;
    reg [1:0] b_sync;
    reg [1:0] ab_stable;
    reg [1:0] ab_candidate;
    reg [1:0] ab_sample_cnt;
    reg [1:0] ab_q;

    // 两级同步，防亚稳态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_sync <= 2'b00;
            b_sync <= 2'b00;
        end else begin
            a_sync <= {a_sync[0], enc_a};
            b_sync <= {b_sync[0], enc_b};
        end
    end

    wire [1:0] ab = {a_sync[1], b_sync[1]};

    // 连续两个同步采样一致后才更新。只延迟两个时钟，
    // 对当前转速没有实际影响，并降低单周期毛刺造成的误计数。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_stable     <= 2'b00;
            ab_candidate  <= 2'b00;
            ab_sample_cnt <= 2'd0;
        end else if (ab == ab_stable) begin
            ab_candidate  <= ab;
            ab_sample_cnt <= 2'd0;
        end else if ((ab == ab_candidate) &&
                     (ab_sample_cnt >= 2'd1)) begin
            ab_stable     <= ab;
            ab_sample_cnt <= 2'd0;
        end else begin
            ab_candidate  <= ab;
            ab_sample_cnt <= 2'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ab_q       <= 2'b00;
            pos        <= 24'sd0;
            edge_pulse <= 1'b0;
        end else begin
            ab_q       <= ab_stable;
            edge_pulse <= 1'b0;
            if (ab_stable != ab_q) begin
                edge_pulse <= 1'b1;
                case ({ab_q, ab_stable})
                    4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00:
                        pos <= pos + 24'sd1;
                    4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00:
                        pos <= pos - 24'sd1;
                    default: ;   // 两路同时跳变：噪声或丢边沿，不计数
                endcase
            end
        end
    end

endmodule
