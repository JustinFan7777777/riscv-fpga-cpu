# Bonus 总览 — 满分 10 分 (全部完成)

> 基础功能 80 分已锁定 (33/33 Difftest PASS)。以下 6 项 Bonus 合计 22 分 (封顶 10 分)。

---

## 总览

| # | Bonus 项目 | 类别 | 最高分 | 状态 | 详细文档 |
|---|-----------|------|--------|------|---------|
| 1 | VGA 文本显示 | 复杂外设接口 | 5 | 完成 | [5_vga.md](5_vga.md) |
| 2 | 贪吃蛇游戏 | 软硬件协同应用 | 5 | 完成 | [6_snake.md](6_snake.md) |
| 3 | 五级流水线 | 架构优化 | 6 | 完成 | [8_pipeline.md](8_pipeline.md) |
| 4 | ISA 扩展 (POPCNT/CLZ/CTZ) | ISA 扩展 | 4 | 完成 | [7_isa.md](7_isa.md) |
| 5 | CPU 数据通路可视化 | 教学效率工具 | 4 | 完成 | [4_visualizer.md](4_visualizer.md) |
| 6 | 软件乘法 (移位相加) | 软硬件协同示例 | — | 溢出展示 | [9_mul.md](9_mul.md) |

---

## 关键文件索引

```
cpu_project/cpu_project.srcs/sources_1/new/
├── VGA.v                    # VGA 控制器
├── CPUTopPipeline.v         # 流水线 CPU 顶层
├── Ifetch_Pipe.v            # 流水线取指
├── PipeRegs.v               # 4 组流水线寄存器
├── HazardUnit.v             # 冒险检测 + 转发
└── RegFile_Pipe.v           # 流水线寄存器堆

other/
├── cpu_viz/visualizer.html  # 数据通路可视化工具
├── snake/snake.asm          # 贪吃蛇 (416 条指令)
├── isa/isa_test.asm         # ISA 扩展测试 (63 条指令)
└── mul/soft_mul.asm         # 软件乘法 (62 条指令)
```

每个 Bonus 的详细实现、演示脚本和创新点见对应 md 文件。
