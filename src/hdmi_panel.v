// =============================================================
//  hdmi_panel.v  --  720p 实时监控面板（卡片式布局）
//
//  布局：
//    ┌──────────────────────────────────────────────────────┐
//    │  [ TGT ]            [ ACT ]            [ DUTY ]      │
//    │   180 RPM            172 RPM             60 %        │
//    │ ┌────────────────────────────────────┐  TGT ──      │
//    │ │      目标(橙虚线) + 实测(蓝实线)    │  ACT ──      │
//    │ └────────────────────────────────────┘               │
//    │  [RUN]  [REV]  [ALM]                                 │
//    └──────────────────────────────────────────────────────┘
//
//  纯流式渲染，无整帧缓存；历史只占 512x24bit BSRAM。
//  时序参数与 Sipeed 官方 hdmi 例程一致（1280x720）。
// =============================================================
module hdmi_panel #(
    parameter integer H_TOTAL = 1650,
    parameter integer H_SYNC  = 40,
    parameter integer H_BP    = 220,
    parameter integer H_RES   = 1280,
    parameter integer V_TOTAL = 750,
    parameter integer V_SYNC  = 5,
    parameter integer V_BP    = 20,
    parameter integer V_RES   = 720
)(
    input  wire        pix_clk,
    input  wire        rst_n,
    input  wire [15:0] target_rpm,
    input  wire [15:0] actual_rpm,
    input  wire [9:0]  duty,
    input  wire        run,
    input  wire        rev,
    input  wire        alarm,
    input  wire        post_done,
    input  wire        post_ok,
    input  wire        post_result_valid,
    input  wire [7:0]  post_status,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         de,
    output reg         hs,
    output reg         vs
);

    // ---------------- 像素坐标 ----------------
    reg [11:0] hcnt;
    reg [10:0] vcnt;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            hcnt <= 12'd0;
            vcnt <= 11'd0;
        end else if (hcnt >= H_TOTAL - 1) begin
            hcnt <= 12'd0;
            vcnt <= (vcnt >= V_TOTAL - 1) ? 11'd0 : vcnt + 1'b1;
        end else begin
            hcnt <= hcnt + 1'b1;
        end
    end

    wire [11:0] xa = hcnt - (H_SYNC + H_BP);
    wire [10:0] ya = vcnt - (V_SYNC + V_BP);
    wire        act = (hcnt >= H_SYNC + H_BP) && (hcnt < H_SYNC + H_BP + H_RES) &&
                      (vcnt >= V_SYNC + V_BP) && (vcnt < V_SYNC + V_BP + V_RES);

    // ---------------- 跨时钟域同步 ----------------
    reg [15:0] tgt_s1, tgt_s2, act1, act2;
    reg [9:0]  duty_s1, duty_s2;
    reg        run_s1, run_s2, rev_s1, rev_s2, alm_s1, alm_s2;
    reg        post_done_s1, post_done_s2;
    reg        post_ok_s1, post_ok_s2;
    reg        post_valid_s1, post_valid_s2;
    reg [7:0]  post_status_s1, post_status_s2;

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            tgt_s1 <= 0; tgt_s2 <= 0; act1 <= 0; act2 <= 0;
            duty_s1 <= 0; duty_s2 <= 0;
            run_s1 <= 0; run_s2 <= 0; rev_s1 <= 0; rev_s2 <= 0;
            alm_s1 <= 0; alm_s2 <= 0;
            post_done_s1 <= 0; post_done_s2 <= 0;
            post_ok_s1 <= 0; post_ok_s2 <= 0;
            post_valid_s1 <= 0; post_valid_s2 <= 0;
            post_status_s1 <= 0; post_status_s2 <= 0;
        end else begin
            tgt_s1 <= target_rpm; tgt_s2 <= tgt_s1;
            act1   <= actual_rpm; act2   <= act1;
            duty_s1 <= duty;      duty_s2 <= duty_s1;
            run_s1 <= run;        run_s2 <= run_s1;
            rev_s1 <= rev;        rev_s2 <= rev_s1;
            alm_s1 <= alarm;      alm_s2 <= alm_s1;
            post_done_s1 <= post_done;
            post_done_s2 <= post_done_s1;
            post_ok_s1 <= post_ok;
            post_ok_s2 <= post_ok_s1;
            post_valid_s1 <= post_result_valid;
            post_valid_s2 <= post_valid_s1;
            post_status_s1 <= post_status;
            post_status_s2 <= post_status_s1;
        end
    end

    wire show_post_screen = !post_done_s2 || !post_ok_s2;

    // ---------------- 历史缓存 ----------------
    reg [23:0] hist [0:511];
    reg [8:0]  wr_idx;
    reg [1:0]  fdiv;

    always @(posedge pix_clk) begin
        if (hcnt == 12'd0 && vcnt == 11'd0) begin
            fdiv <= fdiv + 1'b1;
            if (fdiv == 2'd3) begin
                hist[wr_idx] <= {tgt_s2[11:0], act2[11:0]};
                wr_idx <= wr_idx + 1'b1;
            end
        end
    end

    wire [8:0] sidx = ((xa >= 12'd70) && (xa < 12'd1094)) ? ((xa - 12'd70) >> 1) : 9'd0;

    reg [8:0]  raddr;
    reg [23:0] rdata;
    always @(posedge pix_clk) begin
        raddr <= sidx;
        rdata <= hist[raddr];
    end

    // ---------------- 小字体（5x7，列编码，LSB=顶行） ----------------
    function [6:0] fcol;
        input [7:0] ch;
        input [2:0] col;
        begin
            fcol = 7'd0;
            case (ch)
                8'h41: case (col) 0:fcol=7'h7C; 1:fcol=7'h12; 2:fcol=7'h11; 3:fcol=7'h12; default:fcol=7'h7C; endcase // A
                8'h43: case (col) 0:fcol=7'h3E; 1:fcol=7'h41; 2:fcol=7'h41; 3:fcol=7'h41; default:fcol=7'h22; endcase // C
                8'h44: case (col) 0:fcol=7'h7F; 1:fcol=7'h41; 2:fcol=7'h41; 3:fcol=7'h22; default:fcol=7'h1C; endcase // D
                8'h45: case (col) 0:fcol=7'h7F; 1:fcol=7'h49; 2:fcol=7'h49; 3:fcol=7'h49; default:fcol=7'h41; endcase // E
                8'h46: case (col) 0:fcol=7'h7F; 1:fcol=7'h09; 2:fcol=7'h09; 3:fcol=7'h09; default:fcol=7'h01; endcase // F
                8'h47: case (col) 0:fcol=7'h3E; 1:fcol=7'h41; 2:fcol=7'h49; 3:fcol=7'h49; default:fcol=7'h7A; endcase // G
                8'h4B: case (col) 0:fcol=7'h7F; 1:fcol=7'h08; 2:fcol=7'h14; 3:fcol=7'h22; default:fcol=7'h41; endcase // K
                8'h4C: case (col) 0:fcol=7'h7F; 1:fcol=7'h40; 2:fcol=7'h40; 3:fcol=7'h40; default:fcol=7'h40; endcase // L
                8'h4D: case (col) 0:fcol=7'h7F; 1:fcol=7'h02; 2:fcol=7'h0C; 3:fcol=7'h02; default:fcol=7'h7F; endcase // M
                8'h4E: case (col) 0:fcol=7'h7F; 1:fcol=7'h04; 2:fcol=7'h08; 3:fcol=7'h10; default:fcol=7'h7F; endcase // N
                8'h4F: case (col) 0:fcol=7'h3E; 1:fcol=7'h41; 2:fcol=7'h41; 3:fcol=7'h41; default:fcol=7'h3E; endcase // O
                8'h50: case (col) 0:fcol=7'h7F; 1:fcol=7'h09; 2:fcol=7'h09; 3:fcol=7'h09; default:fcol=7'h06; endcase // P
                8'h52: case (col) 0:fcol=7'h7F; 1:fcol=7'h09; 2:fcol=7'h19; 3:fcol=7'h29; default:fcol=7'h46; endcase // R
                8'h53: case (col) 0:fcol=7'h46; 1:fcol=7'h49; 2:fcol=7'h49; 3:fcol=7'h49; default:fcol=7'h31; endcase // S
                8'h54: case (col) 0:fcol=7'h01; 1:fcol=7'h01; 2:fcol=7'h7F; 3:fcol=7'h01; default:fcol=7'h01; endcase // T
                8'h55: case (col) 0:fcol=7'h3F; 1:fcol=7'h40; 2:fcol=7'h40; 3:fcol=7'h40; default:fcol=7'h3F; endcase // U
                8'h56: case (col) 0:fcol=7'h1F; 1:fcol=7'h20; 2:fcol=7'h40; 3:fcol=7'h20; default:fcol=7'h1F; endcase // V
                8'h57: case (col) 0:fcol=7'h1F; 1:fcol=7'h60; 2:fcol=7'h30; 3:fcol=7'h60; default:fcol=7'h1F; endcase // W
                8'h59: case (col) 0:fcol=7'h07; 1:fcol=7'h08; 2:fcol=7'h70; 3:fcol=7'h08; default:fcol=7'h07; endcase // Y
                default: fcol = 7'd0;
            endcase
        end
    endfunction

    function [7:0] ch_at;
        input [31:0] s;
        input [1:0]  i;
        begin
            case (i)
                2'd0: ch_at = s[31:24];
                2'd1: ch_at = s[23:16];
                2'd2: ch_at = s[15:8];
                default: ch_at = s[7:0];
            endcase
        end
    endfunction

    // 4 字符文字，字号 4x（每字 20x28）
    function text4_on;
        input [15:0] px, py, bx, by;
        input [31:0] s;
        input [2:0]  n;
        reg [2:0] i;
        reg [6:0] fc;
        begin
            text4_on = 1'b0;
            for (i = 3'd0; i < 3'd4; i = i + 1'b1) begin
                if (i < n) begin
                    if (px >= bx + i * 24 && px < bx + i * 24 + 20 &&
                        py >= by && py < by + 28) begin
                        fc = fcol(ch_at(s, i), (px - bx - i * 24) >> 2);
                        text4_on = fc[(py - by) >> 2];
                    end
                end
            end
        end
    endfunction

    // 8 倍字号：每字 40x56，字距 48，用于 POST 启动页。
    function text8_on;
        input [15:0] px, py, bx, by;
        input [31:0] s;
        input [2:0]  n;
        reg [2:0] i;
        reg [6:0] fc;
        begin
            text8_on = 1'b0;
            for (i = 3'd0; i < 3'd4; i = i + 1'b1) begin
                if (i < n) begin
                    if (px >= bx + i * 48 && px < bx + i * 48 + 40 &&
                        py >= by && py < by + 56) begin
                        fc = fcol(ch_at(s, i), (px - bx - i * 48) >> 3);
                        text8_on = fc[(py - by) >> 3];
                    end
                end
            end
        end
    endfunction

    // ---------------- 七段数字（64x104） ----------------
    function seg_on;
        input [15:0] dx, dy;
        input [3:0]  dg;
        reg a_, b_, c_, d_, e_, f_, g_;
        begin
            a_ = (dy < 12) && (dx >= 12) && (dx < 52);
            g_ = (dy >= 46) && (dy < 58) && (dx >= 12) && (dx < 52);
            d_ = (dy >= 92) && (dx >= 12) && (dx < 52);
            f_ = (dx < 12) && (dy >= 12) && (dy < 52);
            b_ = (dx >= 52) && (dy >= 12) && (dy < 52);
            e_ = (dx < 12) && (dy >= 52) && (dy < 92);
            c_ = (dx >= 52) && (dy >= 52) && (dy < 92);
            case (dg)
                4'd0: seg_on = a_|b_|c_|d_|e_|f_;
                4'd1: seg_on = b_|c_;
                4'd2: seg_on = a_|b_|g_|e_|d_;
                4'd3: seg_on = a_|b_|g_|c_|d_;
                4'd4: seg_on = f_|g_|b_|c_;
                4'd5: seg_on = a_|f_|g_|c_|d_;
                4'd6: seg_on = a_|f_|g_|e_|c_|d_;
                4'd7: seg_on = a_|b_|c_;
                4'd8: seg_on = a_|b_|c_|d_|e_|f_|g_;
                default: seg_on = a_|b_|c_|d_|f_|g_;
            endcase
        end
    endfunction

    function [3:0] div100;
        input [15:0] v;
        integer i; reg [15:0] t;
        begin
            t = v; div100 = 4'd0;
            for (i = 0; i < 10; i = i + 1)
                if (t >= 16'd100) begin t = t - 16'd100; div100 = div100 + 1'b1; end
        end
    endfunction

    function [3:0] div10;
        input [15:0] v;
        integer i; reg [15:0] t;
        begin
            t = v; div10 = 4'd0;
            for (i = 0; i < 10; i = i + 1)
                if (t >= 16'd10) begin t = t - 16'd10; div10 = div10 + 1'b1; end
        end
    endfunction

    function num3_on;
        input [15:0] px, py, bx, by;
        input [3:0]  h_, t_, o_;
        integer k;
        begin
            num3_on = 1'b0;
            if (py >= by && py < by + 104) begin
                for (k = 0; k < 3; k = k + 1) begin
                    if (px >= bx + k * 76 && px < bx + k * 76 + 64) begin
                        case (k)
                            0: num3_on = seg_on(px - bx,        py - by, h_);
                            1: num3_on = seg_on(px - bx - 76,   py - by, t_);
                            default: num3_on = seg_on(px - bx - 152, py - by, o_);
                        endcase
                    end
                end
            end
        end
    endfunction

    // ---------------- 数值 ----------------
    wire [15:0] vT = (tgt_s2 > 16'd999) ? 16'd999 : tgt_s2;
    wire [15:0] vS = (act2   > 16'd999) ? 16'd999 : act2;
    wire [15:0] vD = ((duty_s2 * 24'd100) >> 10);

    wire [3:0] hT = div100(vT);
    wire [3:0] tT = div10(vT - {12'd0, hT} * 16'd100);
    wire [3:0] oT = vT - {12'd0, hT} * 16'd100 - {12'd0, tT} * 16'd10;
    wire [3:0] hS = div100(vS);
    wire [3:0] tS = div10(vS - {12'd0, hS} * 16'd100);
    wire [3:0] oS = vS - {12'd0, hS} * 16'd100 - {12'd0, tS} * 16'd10;
    wire [3:0] hD = div100(vD);
    wire [3:0] tD = div10(vD - {12'd0, hD} * 16'd100);
    wire [3:0] oD = vD - {12'd0, hD} * 16'd100 - {12'd0, tD} * 16'd10;

    // ---------------- 曲线参数 ----------------
    wire [23:0] yoff_act = (rdata[11:0]  * 24'd1160) >> 10;
    wire [23:0] yoff_tgt = (rdata[23:12] * 24'd1160) >> 10;
    wire [15:0] act_y = 16'd640 - yoff_act[15:0];
    wire [15:0] tgt_y = 16'd640 - yoff_tgt[15:0];
    wire        accel = (tgt_s2 > act2 + 16'd6) || (act2 > tgt_s2 + 16'd6);

    // ---------------- 像素合成 ----------------
    reg [7:0] pr, pg, pb;
    reg       pde, phs, pvs;

    wire in_card1 = (xa >= 12'd60)  && (xa < 12'd420);
    wire in_card2 = (xa >= 12'd450) && (xa < 12'd810);
    wire in_card3 = (xa >= 12'd840) && (xa < 12'd1200);
    wire in_cards = (ya >= 11'd96) && (ya < 11'd330);
    wire in_chart = (xa >= 12'd60) && (xa < 12'd1094) && (ya >= 11'd360) && (ya < 11'd650);

    always @(*) begin
        // 背景
        pr = 8'd10; pg = 8'd15; pb = 8'd26;

        // 顶部装饰条
        if (ya < 11'd4) begin pr = 8'd56; pg = 8'd140; pb = 8'd230; end
        if (ya >= 11'd60 && ya < 11'd64) begin pr = 8'd26; pg = 8'd36; pb = 8'd58; end

        // 卡片底 + 边框
        if (in_cards) begin
            pr = 8'd18; pg = 8'd26; pb = 8'd44;
            if (in_card1 || in_card2 || in_card3) begin
                if (ya >= 11'd96 && ya < 11'd98) begin pr = 8'd44; pg = 8'd60; pb = 8'd96; end
                if (ya >= 11'd328) begin pr = 8'd44; pg = 8'd60; pb = 8'd96; end
            end
        end

        // 卡片顶部色条
        if (ya >= 11'd96 && ya < 11'd106) begin
            if (in_card1) begin pr = 8'd255; pg = 8'd170; pb = 8'd60;  end
            if (in_card2) begin pr = 8'd70;  pg = 8'd160; pb = 8'd255; end
            if (in_card3) begin pr = 8'd56;  pg = 8'd211; pb = 8'd159; end
        end

        // 图表区域
        if (in_chart) begin
            if (accel) begin pr = 8'd22; pg = 8'd20; pb = 8'd26; end
            else       begin pr = 8'd14; pg = 8'd21; pb = 8'd36; end

            // 网格（固定行，避免取模）
            case (ya)
                11'd364, 11'd365, 11'd419, 11'd420,
                11'd474, 11'd475, 11'd529, 11'd530,
                11'd584, 11'd585, 11'd639, 11'd640:
                    begin pr = 8'd30; pg = 8'd42; pb = 8'd66; end
                default: ;
            endcase

            // 实测线（3px）
            if ((ya + 3 >= act_y) && (ya <= act_y + 3))
                begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
            // 目标线（虚线，3px）
            if ((ya + 3 >= tgt_y) && (ya <= tgt_y + 3) && ((xa >> 3) & 1'b1) == 1'b0)
                begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
        end

        // 图表边框
        if ((xa >= 12'd60 && xa < 12'd1094) && (ya >= 11'd358 && ya < 11'd362)) begin pr = 8'd40; pg = 8'd54; pb = 8'd84; end
        if ((xa >= 12'd60 && xa < 12'd1094) && (ya >= 11'd648 && ya < 11'd652)) begin pr = 8'd40; pg = 8'd54; pb = 8'd84; end

        // 三个大数字
        // 每个像素最多只算一次七段
        if (ya >= 11'd180 && ya < 11'd284) begin
            if (xa >= 12'd84 && xa < 12'd148) begin
                if (seg_on(xa - 12'd84, ya - 11'd180, hT))
                    begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
            end else if (xa >= 12'd160 && xa < 12'd224) begin
                if (seg_on(xa - 12'd160, ya - 11'd180, tT))
                    begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
            end else if (xa >= 12'd236 && xa < 12'd300) begin
                if (seg_on(xa - 12'd236, ya - 11'd180, oT))
                    begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
            end else if (xa >= 12'd474 && xa < 12'd538) begin
                if (seg_on(xa - 12'd474, ya - 11'd180, hS))
                    begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
            end else if (xa >= 12'd550 && xa < 12'd614) begin
                if (seg_on(xa - 12'd550, ya - 11'd180, tS))
                    begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
            end else if (xa >= 12'd626 && xa < 12'd690) begin
                if (seg_on(xa - 12'd626, ya - 11'd180, oS))
                    begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
            end else if (xa >= 12'd864 && xa < 12'd928) begin
                if (seg_on(xa - 12'd864, ya - 11'd180, hD))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
            end else if (xa >= 12'd940 && xa < 12'd1004) begin
                if (seg_on(xa - 12'd940, ya - 11'd180, tD))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
            end else if (xa >= 12'd1016 && xa < 12'd1080) begin
                if (seg_on(xa - 12'd1016, ya - 11'd180, oD))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
            end
        end

        // 卡片标题
        if (xa >= 12'd84  && xa < 12'd156 && ya >= 11'd122 && ya < 11'd150)
            if (text4_on(xa, ya, 16'd84, 16'd122, 32'h54475420, 3'd3))
                begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end // TGT
        if (xa >= 12'd474 && xa < 12'd546 && ya >= 11'd122 && ya < 11'd150)
            if (text4_on(xa, ya, 16'd474, 16'd122, 32'h41435420, 3'd3))
                begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end // ACT
        if (xa >= 12'd864 && xa < 12'd960 && ya >= 11'd122 && ya < 11'd150)
            if (text4_on(xa, ya, 16'd864, 16'd122, 32'h44555459, 3'd4))
                begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end // DUTY

        // 图例
        if (ya >= 11'd382 && ya < 11'd386 && xa >= 12'd1116 && xa < 12'd1152)
            begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
        if (xa >= 12'd1160 && xa < 12'd1232 && ya >= 11'd372 && ya < 11'd400)
            if (text4_on(xa, ya, 16'd1160, 16'd372, 32'h54475420, 3'd3))
                begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
        if (ya >= 11'd432 && ya < 11'd436 && xa >= 12'd1116 && xa < 12'd1152)
            begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
        if (xa >= 12'd1160 && xa < 12'd1232 && ya >= 11'd422 && ya < 11'd450)
            if (text4_on(xa, ya, 16'd1160, 16'd422, 32'h41435420, 3'd3))
                begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end

        // 状态条
        if (ya >= 11'd672 && ya < 11'd706) begin
            if (xa >= 12'd60 && xa < 12'd160 && run_s2 && !alm_s2)
                begin pr = 8'd20; pg = 8'd64; pb = 8'd52; end
            if (xa >= 12'd180 && xa < 12'd280 && rev_s2)
                begin pr = 8'd72; pg = 8'd58; pb = 8'd18; end
            if (xa >= 12'd300 && xa < 12'd420 && alm_s2 && hcnt[10])
                begin pr = 8'd84; pg = 8'd22; pb = 8'd22; end
        end
        if (xa >= 12'd72  && xa < 12'd144 && ya >= 11'd678 && ya < 11'd706)
            if (text4_on(xa, ya, 16'd72, 16'd678, 32'h52554E20, 3'd3)) begin
                if (run_s2 && !alm_s2) begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
                else                   begin pr = 8'd58; pg = 8'd68;  pb = 8'd90;  end
            end
        if (xa >= 12'd192 && xa < 12'd264 && ya >= 11'd678 && ya < 11'd706)
            if (text4_on(xa, ya, 16'd192, 16'd678, 32'h52455620, 3'd3)) begin
                if (rev_s2) begin pr = 8'd255; pg = 8'd210; pb = 8'd64; end
                else        begin pr = 8'd58;  pg = 8'd68;  pb = 8'd90; end
            end
        if (xa >= 12'd312 && xa < 12'd384 && ya >= 11'd678 && ya < 11'd706)
            if (text4_on(xa, ya, 16'd312, 16'd678, 32'h414C4D20, 3'd3)) begin
                if (alm_s2) begin pr = 8'd255; pg = 8'd80; pb = 8'd80; end
                else        begin pr = 8'd58;  pg = 8'd68; pb = 8'd90; end
            end

        // ---------------- POST 启动页覆盖层 ----------------
        if (show_post_screen) begin
            pr = 8'd8; pg = 8'd13; pb = 8'd24;

            if (ya < 11'd6) begin
                pr = 8'd56; pg = 8'd140; pb = 8'd230;
            end

            if (xa >= 12'd300 && xa < 12'd980 &&
                ya >= 11'd220 && ya < 11'd520) begin
                pr = 8'd15; pg = 8'd23; pb = 8'd40;
            end
            if (((xa >= 12'd300 && xa < 12'd980) &&
                 (ya >= 11'd220 && ya < 11'd224)) ||
                ((xa >= 12'd300 && xa < 12'd980) &&
                 (ya >= 11'd516 && ya < 11'd520)) ||
                ((ya >= 11'd220 && ya < 11'd520) &&
                 (xa >= 12'd300 && xa < 12'd304)) ||
                ((ya >= 11'd220 && ya < 11'd520) &&
                 (xa >= 12'd976 && xa < 12'd980))) begin
                pr = 8'd48; pg = 8'd70; pb = 8'd112;
            end

            if (!post_valid_s2) begin
                if (text8_on(xa, ya, 16'd560, 16'd330,
                             32'h504F5354, 3'd4))
                    begin pr = 8'd70; pg = 8'd160; pb = 8'd255; end
            end else if (post_ok_s2) begin
                if (text8_on(xa, ya, 16'd368, 16'd330,
                             32'h53454C46, 3'd4))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
                if (text8_on(xa, ya, 16'd592, 16'd330,
                             32'h54455354, 3'd4))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
                if (text8_on(xa, ya, 16'd768, 16'd330,
                             32'h204F4B20, 3'd4))
                    begin pr = 8'd56; pg = 8'd211; pb = 8'd159; end
            end else begin
                if (!post_status_s2[0]) begin
                    if (text8_on(xa, ya, 16'd452, 16'd300,
                                 32'h454E4320, 3'd4))
                        begin pr = 8'd255; pg = 8'd90; pb = 8'd90; end
                    if (text8_on(xa, ya, 16'd644, 16'd300,
                                 32'h45525220, 3'd4))
                        begin pr = 8'd255; pg = 8'd90; pb = 8'd90; end
                end
                if (!post_status_s2[1]) begin
                    if (text8_on(xa, ya, 16'd452, 16'd390,
                                 32'h50574D20, 3'd4))
                        begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
                    if (text8_on(xa, ya, 16'd644, 16'd390,
                                 32'h45525220, 3'd4))
                        begin pr = 8'd255; pg = 8'd170; pb = 8'd60; end
                end
            end
        end

        pde = act;
        phs = (hcnt < H_SYNC);
        pvs = (vcnt < V_SYNC);
    end

    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 8'd0; g <= 8'd0; b <= 8'd0;
            de <= 1'b0; hs <= 1'b0; vs <= 1'b0;
        end else begin
            r <= pr; g <= pg; b <= pb;
            de <= pde; hs <= phs; vs <= pvs;
        end
    end

endmodule
