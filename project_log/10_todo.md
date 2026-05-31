# 项目收尾 TODO — 最终检查清单

> 截止: 15 周周一 23:59 (时间系数=1.0)
> 提交者: 一人负责，在共享文档登记

---

## 一、Vivado / 上板任务 (需要 Windows + Vivado 2017.4)

### 1.1 生成工程文件
- [ ] 在 Vivado 中运行 `source create_project.tcl` 生成 `cpu_project.xpr`
- [ ] 确认 `cpu_project.xpr` 存在且双击可打开
- [ ] 确认所有 16 个 .v 文件已添加到工程
- [ ] 确认 2 个 .txt 文件 (batch_test.txt, batch_test_pipeline.txt) 在 source/new/ 下
- [ ] 确认顶层模块为 TopDebug

### 1.2 综合 → 实现 → 生成比特流
- [ ] Run Synthesis → 无 Error
- [ ] Run Implementation → 无 Error
- [ ] Generate Bitstream → 成功
- [ ] 确认以下文件存在于 `cpu_project.runs/impl_1/`:
  - [ ] `TopDebug.bit`
  - [ ] `TopDebug_opt.dcp`
  - [ ] `TopDebug_placed.dcp`
  - [ ] `TopDebug_routed.dcp`

### 1.3 上板验证
- [ ] 烧录 TopDebug.bit 到 EGO1
- [ ] SwitchIn[15]=0 (单周期模式) → difftest 33/33 PASS
- [ ] SwitchIn[15]=1 (流水线模式) → 基本指令正确
- [ ] VGA 显示器正常显示
- [ ] 按键功能正常 (贪吃蛇操作)
- [ ] Debug UART 通信正常 (读寄存器/读PC/单步)

---

## 二、代码提交任务

### 2.1 目录整理
- [ ] 确认最终目录结构:
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
  │   ├── batch_test.txt
  │   ├── batch_test_pipeline.asm
  │   └── batch_test_pipeline.txt
  ├── other/
  │   ├── cpu_viz/visualizer.html
  │   ├── isa/isa_test.asm, isa_test.txt
  │   ├── mul/soft_mul.asm, soft_mul_isa.asm, soft_mul.txt, soft_mul_test.txt
  │   ├── snake/snake.asm, snake.txt
  │   └── vga/gen_font.py, font_rom.txt, tb_VGA.v, test.py
  └── gitlog.txt
  ```

### 2.2 命名检查
- [ ] 目录名: `c_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun` (无中文字符)
- [ ] zip 名: `c_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun.zip`
- [ ] 顶层模块: `TopDebug`
- [ ] 工程名: `cpu_project`
- [ ] bitstream: `TopDebug.bit`

### 2.3 规则检查
- [ ] 无 Vivado 自带或第三方 IP 核
- [ ] IMem 使用 `$readmemh` 初始化 `batch_test.txt`
- [ ] txt 与 Verilog 同目录 (source/new/ 下有 batch_test.txt 和 batch_test_pipeline.txt)
- [ ] 默认模式 (SwitchIn[15]=0, 单周期) 能通过所有基础 Case
- [ ] 无中文字符在任何目录名/文件名中
- [ ] gitlog.txt 开头列出提交人→成员姓名映射
- [ ] 已 git push 最新代码

### 2.4 排除检查 (不打包进 zip)
- [ ] `project_log/`
- [ ] `docs/`
- [ ] `.claude/`
- [ ] `.git/`
- [ ] `README.md`
- [ ] `assemble.py`
- [ ] `simulate_pipeline.py`
- [ ] `.DS_Store`
- [ ] `__pycache__/`

### 2.5 提交
- [ ] zip 压缩包上传 BB
- [ ] 在共享文档登记提交者姓名

---

## 三、文档任务

### 3.1 问卷提交
- [ ] 打开 https://f.kdocs.cn/g/5JvFO9aZ/
- [ ] 参照 `project_log/1_report.md` 填写各部分:
  - [ ] 开发者说明 (3 人信息 + 贡献比)
  - [ ] 开发环境 (Vivado 2017.4, Windows/macOS, EGO1 XC7A35T)
  - [ ] 开发计划与实施 (GitHub Classroom 团队名 + 仓库地址)
  - [ ] CPU 架构设计说明 (4a–4g 全部 7 小节)
  - [ ] 自测试说明 (RARS + Difftest + Pipeline 模拟器)
  - [ ] Bonus 设计说明 (6 项, 每项简述 + 关键代码)
  - [ ] 问题与总结 (12 个 Bug + 反思 + 建议)

---

## 四、视频任务

### 4.1 录制准备
- [ ] 参照 `project_log/0_video.md` 脚本
- [ ] 确认录制设备 (手机/相机 + 支架)
- [ ] 确认三人均在现场
- [ ] 完整走一遍流程再正式录制

### 4.2 录制内容
- [ ] 镜头 1: 全员介绍 (~30s, 含 AI 工具声明)
- [ ] 镜头 2: 硬件展示 (~40s)
- [ ] 镜头 3: Difftest 33/33 PASS (~60s)
- [ ] 镜头 4: 手动验证 2 个复杂用例 (~60s)
- [ ] 镜头 5: VGA 文本显示 (~60s)
- [ ] 镜头 6: 贪吃蛇游戏 (~90s)
- [ ] 镜头 7: ISA 硬件加速 (~60s)
- [ ] 镜头 8: 五级流水线 + 模式切换 (~90s)
- [ ] 镜头 9: 可视化工具 (~30s)
- [ ] 镜头 10: 软件乘法 (~20s)

### 4.3 后期与提交
- [ ] 剪辑合并为完整视频 (~7-8 分钟)
- [ ] 确认无 AI 生成语音
- [ ] 确认大小 ≤500MB
- [ ] 命名: `v_Tue34_w_10_rv_FanXiaole_ChenJunxi_LiuYijun.mp4`
- [ ] 上传教师发布的云盘链接

---

## 五、现场设计准备 (15 周实验课)

### 5.1 知识准备
- [ ] 熟读 `project_log/2_inclass.md`
- [ ] 记住 INCLASS 标记位置 (Decoder/ALU/CPUTop/Ifetch)
- [ ] 理解控制信号速查表
- [ ] 练习过一次完整修改流程

### 5.2 考试日
- [ ] 全员出席 (不参加 = 0 分 + 自动拆组)
- [ ] 断网环境, 仅用学生机 Vivado 2017.4
- [ ] 严禁个人电脑/手机
- [ ] 收到教师给的指令参数 → 按速查表判断改动范围 → 修改代码 → 注入测试机器码 → 综合上板 → 验证 → 举手请老师确认

---

## 六、最终确认清单 (提交前一晚逐条打勾)

- [ ] `cpu_project.xpr` 已生成并 push
- [ ] `runs/impl_1/` 下 4 个文件已提交
- [ ] difftest 33/33 PASS (单周期默认模式)
- [ ] 流水线模式基本指令正确
- [ ] VGA 显示正常
- [ ] 贪吃蛇可正常游玩
- [ ] gitlog.txt 最新 (含所有提交)
- [ ] 目录已重命名为标准格式
- [ ] 压缩包内容正确 (仅 4 个顶层目录)
- [ ] zip 已上传 BB
- [ ] 视频已上传云盘
- [ ] 问卷已提交
- [ ] 共享文档已登记提交者
