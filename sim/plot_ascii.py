#!/usr/bin/env python3
"""把 tb_motor.csv 画成字符图（不需要 numpy / matplotlib）。"""

import csv
import sys


def main(path="tb_motor.csv"):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            try:
                rows.append((int(r["time_ms"]), int(r["target"]),
                             int(r["actual"]), int(r["duty"])))
            except (KeyError, ValueError):
                continue

    if not rows:
        print("没有读到数据，先在 sim 目录跑 vsim")
        return

    width, height = 92, 18
    vmax = max(max(r[1], r[2]) for r in rows) or 1
    step = max(1, len(rows) // width)
    sel = rows[::step][:width]

    grid = [[" "] * len(sel) for _ in range(height)]
    for x, (_, tgt, act, _) in enumerate(sel):
        ty = height - 1 - int(tgt * (height - 1) / vmax)
        ay = height - 1 - int(act * (height - 1) / vmax)
        if 0 <= ty < height:
            grid[ty][x] = "T"
        if 0 <= ay < height:
            grid[ay][x] = "*" if grid[ay][x] == " " else "#"

    print(f"转速曲线  (T=目标, *=实际, #=重合)  0..{vmax} RPM")
    for i, line in enumerate(grid):
        rpm = int(round(vmax * (height - 1 - i) / (height - 1)))
        print(f"{rpm:5d} |" + "".join(line))
    print("      +" + "-" * len(sel))
    t0, t1 = sel[0][0], sel[-1][0]
    print(f"       {t0:.0f} ms -> {t1:.0f} ms")

    last = rows[-1]
    print(f"\n最后一拍: 时间={last[0]:.0f} ms  目标={last[1]}  "
          f"实测={last[2]}  占空比={last[3]}/1023")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "tb_motor.csv")
