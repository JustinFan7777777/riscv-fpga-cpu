# 上板后待办清单

> 以下事项需在 EGO1 开发板上完成验证后方可进行。

---

## 一、Windows/Vivado 端操作

### 1.1 生成 Vivado 工程文件

| 步骤 | 操作 |
|------|------|
| 1 | 打开 Vivado 2017.4 |
| 2 | Tcl Console 中 `cd` 到项目根目录 |
| 3 | 执行 `source create_project.tcl` |
| 4 | 确认工程生成后 `cpu_project/cpu_project.xpr` 存在 |
| 5 | `git add cpu_project/cpu_project.xpr` 并提交 |

### 1.2 综合 → 实现 → 生成比特流

| 步骤 | 操作 |
|------|------|
| 1 | Vivado 中点击 **Run Synthesis** → 等待完成 |
| 2 | 点击 **Run Implementation** → 等待完成 |
| 3 | 点击 **Generate Bitstream** → 等待完成 |
| 4 | 确认 `cpu_project.runs/impl_1/` 下有: |
|    | - `TopDebug.bit` |
|    | - `TopDebug_opt.dcp` |
|    | - `TopDebug_placed.dcp` |
|    | - `TopDebug_routed.dcp` |
| 5 | `git add` 以上 4 个文件并提交 |

---

## 二、上板功能验证

### 2.1 基础功能 — Difftest 33/33

| 步骤 | 操作 |
|------|------|
| 1 | SwitchIn[15] **拨下** (单周期模式) |
| 2 | Micro USB 连接 EGO1，烧录 `TopDebug.bit` |
| 3 | 按下 P15 复位 |
| 4 | PC 端运行 difftest Python 脚本 |
| 5 | 确认终端输出 **33/33 PASS** |
| 6 | 如有 FAIL，记录 Case 编号和实际输出值 |

### 2.2 流水线模式验证

| 步骤 | 操作 |
|------|------|
| 1 | SwitchIn[15] **拨上** (流水线模式) |
| 2 | 通过 UART 加载含 Load-Use 冒险的测试程序 |
| 3 | 单步执行 + 读寄存器验证转发正确 |
| 4 | 测试分支指令 (BEQ/BNE) 确认 flush 正确 |
| 5 | 测试 JAL/JALR 确认跳转 + 写回正确 |
| 6 | 通过 Debug 命令暂停并观察寄存器值 |

### 2.3 VGA 显示验证

| 步骤 | 操作 |
|------|------|
| 1 | VGA 线连接 EGO1 → 显示器 |
| 2 | 通过 UART 写入 VGA 帧缓冲 (0xFFFF_0100) |
| 3 | 确认显示器出现彩色字符 |
| 4 | 测试不同颜色和不同位置 |

### 2.4 贪吃蛇游戏验证

| 步骤 | 操作 |
|------|------|
| 1 | 通过 UART 加载 `other/snake/snake.hex` 到 IMem |
| 2 | 复位 CPU |
| 3 | 按键操作: btn[0]=上, btn[1]=下, btn[2]=左, btn[3]=右 |
| 4 | 确认蛇移动、吃食物增长、撞墙/撞自身游戏结束 |
| 5 | btn[4] 重新开始 |

---

## 三、提交打包

### 3.1 目录重命名

```
原: CO Project/
新: c_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun/
```

### 3.2 排除以下目录/文件（不打包）

| 排除项 | 原因 |
|--------|------|
| `project_log/` | 内部文档，非提交要求 |
| `docs/` | 需求文档，非提交要求 |
| `.claude/` | Claude Code 配置 |
| `.git/` | 版本控制 |
| `.DS_Store` | macOS 系统文件 |

### 3.3 压缩包内容清单

```
c_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun/
├── cpu_project/
│   ├── cpu_project.xpr
│   ├── cpu_project.srcs/*
│   └── cpu_project.runs/impl_1/
│       ├── TopDebug.bit
│       ├── TopDebug_opt.dcp
│       ├── TopDebug_placed.dcp
│       └── TopDebug_routed.dcp
├── assembly/
│   ├── batch_test.asm
│   └── batch_test.hex
├── other/
│   ├── cpu_viz/
│   ├── isa/
│   ├── mul/
│   ├── snake/
│   └── vga/
├── create_project.tcl
└── gitlog.txt
```

压缩为 `.zip` 格式提交 BB。

---

## 四、视频与文档

### 4.1 视频录制

| 项 | 内容 |
|----|------|
| 文件名 | `v_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun.mp4` |
| 格式 | MP4, ≤500MB |
| 脚本 | 参照 `project_log/0_video.md` |
| 禁止 | AI 语音 |
| 上传 | 教师发布的云盘链接 |

### 4.2 文档提交

| 项 | 内容 |
|----|------|
| 平台 | https://f.kdocs.cn/g/5JvFO9aZ/ |
| 内容 | 参照 `project_log/1_report.md` |
| 提交者 | 一人在共享文档中登记 |

---

## 五、检查清单

- [ ] `.xpr` 文件已生成并提交
- [ ] `TopDebug.bit` + 3 个 `.dcp` 已提交
- [ ] difftest 33/33 PASS (单周期)
- [ ] 流水线模式基本指令正确
- [ ] Load-Use 转发正确
- [ ] 分支 flush 正确
- [ ] VGA 显示正常
- [ ] 贪吃蛇可玩
- [ ] 目录已重命名
- [ ] 压缩包内容正确
- [ ] 视频已录制上传
- [ ] 问卷已提交
