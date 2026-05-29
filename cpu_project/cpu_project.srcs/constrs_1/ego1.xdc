# ==============================================================================
# EGO1 XDC Constraint File — for TopDebug (RISC-V RV32I CPU Project)
# 基于课程提供的 EGo1.xdc, 将引脚名映射到 TopDebug 模块的端口名.
# ==============================================================================

# ============================ 系统时钟和复位 ====================================
# 100MHz 系统时钟
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# 复位按钮 (按下=低电平)
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports rst_n]

# ============================ 串口 (PC ↔ FPGA) =================================
set_property -dict {PACKAGE_PIN N5 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports uart_txd]

# ============================ 蓝牙串口 (不使用, 约束防止综合报错) ===============
# set_property -dict {PACKAGE_PIN L3 IOSTANDARD LVCMOS33} [get_ports ...]
# 注: 蓝牙端口不使用则无需约束, Vivado 会自动处理悬空引脚.

# ============================ 5个按键 ==========================================
# btn_pin[4:0] → TopDebug.ButtonIn[4:0]
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {ButtonIn[0]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {ButtonIn[1]}]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {ButtonIn[2]}]
set_property -dict {PACKAGE_PIN V1  IOSTANDARD LVCMOS33} [get_ports {ButtonIn[3]}]
set_property -dict {PACKAGE_PIN U4  IOSTANDARD LVCMOS33} [get_ports {ButtonIn[4]}]

# ============================ 拨码开关 (左8: sw_pin) ============================
# sw_pin[7:0] → TopDebug.SwitchIn[7:0]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[0]}]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[1]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[2]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[3]}]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[4]}]
set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[5]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[6]}]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[7]}]

# ============================ 拨码开关 (右8: dip_pin) ===========================
# dip_pin[7:0] → TopDebug.SwitchIn[15:8]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[8]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[9]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[10]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[11]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[12]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[13]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[14]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports {SwitchIn[15]}]

# ============================ LED (16个) ======================================
# led_pin[15:0] → TopDebug.LEDOut[15:0]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {LEDOut[0]}]
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33} [get_ports {LEDOut[1]}]
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS33} [get_ports {LEDOut[2]}]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports {LEDOut[3]}]
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33} [get_ports {LEDOut[4]}]
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports {LEDOut[5]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {LEDOut[6]}]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports {LEDOut[7]}]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports {LEDOut[8]}]
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS33} [get_ports {LEDOut[9]}]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {LEDOut[10]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {LEDOut[11]}]
set_property -dict {PACKAGE_PIN K6 IOSTANDARD LVCMOS33} [get_ports {LEDOut[12]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {LEDOut[13]}]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports {LEDOut[14]}]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD LVCMOS33} [get_ports {LEDOut[15]}]

# ============================ 数码管位选 (8个) =================================
# seg_cs_pin[7:0] → TopDebug.seg_cs[7:0]   (共阳极, 0=选中该位)
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {seg_cs[0]}]
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports {seg_cs[1]}]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports {seg_cs[2]}]
set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports {seg_cs[3]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {seg_cs[4]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {seg_cs[5]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {seg_cs[6]}]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {seg_cs[7]}]

# ============================ 数码管段选 组0 (左4位数字) =========================
# seg_data_0_pin[7:0] → TopDebug.seg_data_0[7:0]  (共阳极, 0=点亮该段)
# 段映射: [0]=A [1]=B [2]=C [3]=D [4]=E [5]=F [6]=G [7]=DP
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[0]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[1]}]
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[2]}]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[3]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[4]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[5]}]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[6]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {seg_data_0[7]}]

# ============================ 数码管段选 组1 (右4位数字) =========================
# seg_data_1_pin[7:0] → TopDebug.seg_data_1[7:0]  (共阳极, 0=点亮该段)
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[0]}]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[1]}]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[2]}]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[3]}]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[4]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[5]}]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[6]}]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports {seg_data_1[7]}]

# ============================ VGA 显示接口 =====================================
# VGA 水平同步 — vga_hs
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS33} [get_ports vga_hs]

# VGA 垂直同步 — vga_vs
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports vga_vs]

# VGA 红色通道 [3:0] — vga_r[3:0]
set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS33} [get_ports {vga_r[0]}]
set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports {vga_r[1]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports {vga_r[2]}]
set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports {vga_r[3]}]

# VGA 绿色通道 [3:0] — vga_g[3:0]
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports {vga_g[0]}]
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {vga_g[1]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {vga_g[2]}]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports {vga_g[3]}]

# VGA 蓝色通道 [3:0] — vga_b[3:0]
set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports {vga_b[0]}]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {vga_b[1]}]
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {vga_b[2]}]
set_property -dict {PACKAGE_PIN E7 IOSTANDARD LVCMOS33} [get_ports {vga_b[3]}]

# ============================ 生成时钟约束 ======================================
# VGA 像素时钟: 100MHz / 4 = 25MHz (clk_div[1] → BUFG_vga_clk → vga_clk)
create_generated_clock -name vga_clk -source [get_ports clk] \
    -divide_by 4 [get_pins BUFG_vga_clk/O]

# CPU 时钟: 100MHz / 8 = 12.5MHz (clk_div[2] → BUFG_cpu_clk → cpu_clk)
create_generated_clock -name cpu_clk -source [get_ports clk] \
    -divide_by 8 [get_pins BUFG_cpu_clk/O]

# ============================ 未使用外设: 全部不约束 =============================
# DAC, PS2, SDRAM, 蓝牙, 音频, IIC, XADC, PMOD — 本项目不使用.
# Vivado 会自动将未约束的输出引脚置为悬空, 输入引脚拉低.
