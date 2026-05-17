# 项目日志与协作指南

本目录用于三名小组成员的协作指南、操作步骤记录和最终 report 素材汇总。

## 目录结构

| 文件 | 用途 | 面向谁 |
|------|------|--------|
| [1_windows_vivado_guide](1_windows_vivado_guide.md) | Vivado 工程搭建 + 上板测试流程 | Windows 队友 |
| [2_assembly_dev_guide](2_assembly_dev_guide.md) | 汇编代码编译 + 模拟验证流程 | 汇编队友 |
| [3_team_verification_plan](3_team_verification_plan.md) | 三方协同验证清单 | 全员 |
| [4_report_notes](4_report_notes.md) | Report 素材记录 + 开发日志 | 全队 |

## 项目概况

- **指令集**: RISC-V RV32I
- **CPU 架构**: 单周期、哈佛结构
- **开发板**: EGO1 (XC7A35T)
- **开发环境**: Vivado 2017.4, RISC-V GNU Toolchain
- **验证工具**: 差分测试 (difftest) + 传统 I/O (开关/LED)
- **Git 仓库**: GitHub Classroom

## 成员信息

| 姓名 | 学号 | 角色 | 负责内容 |
|------|------|------|---------|
| 范晓乐 | 12412307 | 代码设计 (Mac) | Verilog 代码编写、审查、项目协调 |
| 刘一骏 | 12411922 | 汇编开发 | batch_test.asm 编写与编译、RARS 模拟验证 |
| 陈俊希 | 12411025 | 硬件验证 (Windows) | Vivado 工程、bitstream 生成、上板测试 |

- **GitHub Classroom**: [cpu-project-12412307-12411025-12411922](https://github.com/CS202ComputerOrganization/cpu-project-12412307-12411025-12411922)
- **提交文件夹名**: `c_rv_FanXiaole_ChenJunxi_LiuYijun`
