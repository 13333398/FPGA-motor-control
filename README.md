# Tang Nano 20K 电机闭环控制与故障自恢复工程

本工程实现直流减速电机的编码器测速、PI 闭环调速、PWM 与 TB6612 驱动、
上电自检 POST、堵转颤振脱困、HDMI 状态显示以及 Web Serial 网页监控。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `src/` | FPGA Verilog 源码和 HDMI IP |
| `sim/` | ModelSim 测试平台 |
| `web/` | 网页监控、启动脚本和界面预览 |
| `tools/` | 串口调试脚本 |
| `motor_top.gprj` | Gowin 工程文件 |
| `motor_top.cst` | 引脚约束 |
| `motor_top.sdc` | 时钟约束 |

`impl/`、`work/` 和 `temp/` 是综合、布局布线和仿真生成结果，提交源码时无需上传。

## 主要引脚

| 功能 | 引脚 |
| --- | --- |
| 27 MHz 时钟 | 4 |
| 编码器 A / B | 25 / 26 |
| PWM / AIN1 / AIN2 | 27 / 28 / 29 |
| 蜂鸣器 | 48 |
| USB 串口 TX / RX | 69 / 70 |
| S2 / S1 | 87 / 88 |
| HDMI TMDS | 33 到 40 |

## 主要参数

- PWM 频率：26.37 kHz
- 测速窗口：20 ms
- 编码器计数：1400 计数/圈
- 颤振脉冲：120 ms，间隔 200 ms，最多 3 个周期
- 颤振占空比：350/1023，约 34%
- POST 结果页：3 s

## 网页监控

1. 打开 `web` 目录。
2. 运行 `start.bat`。
3. 浏览器打开 `http://127.0.0.1:8000/dashboard.html`。
4. 点击“连接串口”，选择开发板对应的 COM 口。

网页必须使用桌面版 Edge 或 Chrome，并通过 Web Serial API 工作。
