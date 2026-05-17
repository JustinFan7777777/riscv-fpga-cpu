# ==============================================================================
# Vivado 2017.4 Project Creation Script
# 用法：打开 Vivado 2017.4, 在 Tcl Console 中 cd 到 cpu_project/ 的同级目录,
#       然后执行: source create_project.tcl
# 这条脚本会自动创建 cpu_project 工程, 添加全部源文件, 并创建约束文件模板.
# ==============================================================================

# ---- 1. 创建工程 ----
create_project cpu_project ./cpu_project -part xc7a35tcsg324-1
# xc7a35tcsg324-1 是 EGO1 开发板的 FPGA 型号 (Artix-7 XC7A35T)

# ---- 2. 设置工程属性 ----
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

# ---- 3. 添加全部 Verilog 源文件 ----
# 所有 .v 文件位于 cpu_project/cpu_project.srcs/sources_1/new/
set src_dir "[file dirname [info script]]/cpu_project/cpu_project.srcs/sources_1/new"

add_files -norecurse [glob $src_dir/*.v]
update_compile_order -fileset sources_1

# ---- 4. 标记顶层模块为 TopDebug ----
set_property top TopDebug [current_fileset]
# 如果有 simulation, 同样设置顶层
set_property top TopDebug [get_filesets sim_1]

# ---- 5. 创建约束文件 (可空, 引脚映射等 teammate 拿到 XDC 后更新) ----
set xdc_file "[file dirname [info script]]/cpu_project/cpu_project.srcs/constrs_1/ego1.xdc"
file mkdir "[file dirname $xdc_file]"

# 如果 XDC 文件还没创建, 生成一个模板
if {![file exists $xdc_file]} {
    set fh [open $xdc_file w]
    puts $fh "# =============================================================================="
    puts $fh "# EGO1 XDC Constraint File"
    puts $fh "# TODO: 填入 EGO1 开发板引脚约束 (从课程提供的模板文件复制)"
    puts $fh "# =============================================================================="
    puts $fh ""
    puts $fh "# ---- 时钟 (100MHz) ----"
    puts $fh "# set_property PACKAGE_PIN P17 \[get_ports clk\]"
    puts $fh "# set_property IOSTANDARD LVCMOS33 \[get_ports clk\]"
    puts $fh "# create_clock -period 10.000 -name sys_clk \[get_ports clk\]"
    puts $fh ""
    puts $fh "# ---- 复位 (低有效按钮) ----"
    puts $fh "# set_property PACKAGE_PIN P15 \[get_ports rst_n\]"
    puts $fh "# set_property IOSTANDARD LVCMOS33 \[get_ports rst_n\]"
    puts $fh ""
    puts $fh "# ---- UART ----"
    puts $fh "# set_property PACKAGE_PIN N5 \[get_ports uart_rxd\]"
    puts $fh "# set_property IOSTANDARD LVCMOS33 \[get_ports uart_rxd\]"
    puts $fh "# set_property PACKAGE_PIN T4 \[get_ports uart_txd\]"
    puts $fh "# set_property IOSTANDARD LVCMOS33 \[get_ports uart_txd\]"
    puts $fh ""
    puts $fh "# ---- 拨码开关 (8位) ----"
    puts $fh "# TODO: 填入开关引脚 (如 R1, P2, P3, P4, P5, R6, T1, U2)"
    puts $fh "# set_property PACKAGE_PIN R1 \[get_ports {SwitchIn[0]}\]"
    puts $fh "# ..."
    puts $fh ""
    puts $fh "# ---- LED (8位) ----"
    puts $fh "# TODO: 填入 LED 引脚 (如 F6, G4, G3, J4, J3, J2, K2, K1)"
    puts $fh "# set_property PACKAGE_PIN F6 \[get_ports {LEDOut[0]}\]"
    puts $fh "# ..."
    puts $fh ""
    puts $fh "# ---- 按键 (5位) ----"
    puts $fh "# TODO: 填入按键引脚 (如 R17, R15, V1, U4, U1)"
    puts $fh "# set_property PACKAGE_PIN R17 \[get_ports {ButtonIn[0]}\]"
    puts $fh "# ..."
    puts $fh ""
    puts $fh "# ---- 数码管 ----"
    puts $fh "# TODO: 填入数码管段选+位选引脚"
    puts $fh ""
    close $fh
    puts "Created XDC template at $xdc_file"
}
add_files -fileset constrs_1 $xdc_file

# ---- 6. 设置 IMem 初始化 hex 文件路径 ----
# batch_test.hex 需放在 cpu_project/ 的同级目录 assembly/ 下
# Ifetch.v 中已通过 INIT_FILE 参数指向 "../assembly/batch_test.hex"

# ---- 完成 ----
puts "=================================="
puts "Vivado project 'cpu_project' created successfully."
puts "Top module: TopDebug"
puts "Source files: 11 Verilog files added"
puts ""
puts "Next steps:"
puts "  1. Fill in ego1.xdc with actual EGO1 pin mappings"
puts "  2. Ensure assembly/batch_test.hex exists"
puts "  3. Click 'Generate Bitstream'"
puts "=================================="
