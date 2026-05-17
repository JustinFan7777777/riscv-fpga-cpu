# ==============================================================================
# Vivado 2017.4 Project Creation Script
# ==============================================================================
# 用法：
#   1. 打开 Vivado 2017.4
#   2. 在底部 Tcl Console 中 cd 到本脚本所在目录:
#        cd <path-to>/CO Project/
#   3. 执行: source create_project.tcl
#   4. 脚本自动创建 cpu_project 工程、添加全部源文件、加载 XDC 约束
#   5. 确认 assembly/batch_test.hex 已存在后, 点 Generate Bitstream
# ==============================================================================

# ---- 1. 创建工程 ----
# xc7a35tcsg324-1 = EGO1 开发板的 Artix-7 XC7A35T FPGA
create_project cpu_project ./cpu_project -part xc7a35tcsg324-1
set_property target_language Verilog [current_project]
set_property default_lib work [current_project]

# ---- 2. 添加全部 Verilog 源文件 ----
set src_dir "[file dirname [info script]]/cpu_project/cpu_project.srcs/sources_1/new"
add_files -norecurse [glob $src_dir/*.v]
update_compile_order -fileset sources_1

# ---- 3. 设置顶层模块 ----
set_property top TopDebug [current_fileset]
set_property top TopDebug [get_filesets sim_1]

# ---- 4. 添加 XDC 约束文件 ----
set xdc_file "[file dirname [info script]]/cpu_project/cpu_project.srcs/constrs_1/ego1.xdc"
if {[file exists $xdc_file]} {
    add_files -fileset constrs_1 $xdc_file
    puts "XDC constraint file loaded: ego1.xdc"
} else {
    puts "WARNING: ego1.xdc not found at $xdc_file"
    puts "Please ensure the XDC file exists before generating bitstream."
}

# ---- 5. 确认 batch_test.hex 路径 ----
# Ifetch.v 中 INIT_FILE 参数默认指向 "../assembly/batch_test.hex"
# 即 cpu_project/ 的同级目录 assembly/ 下
set hex_file "[file dirname [info script]]/assembly/batch_test.hex"
if {[file exists $hex_file]} {
    puts "batch_test.hex found: $hex_file"
} else {
    puts "NOTE: batch_test.hex not yet created."
    puts "  The assembly teammate should compile batch_test.asm and place it in assembly/"
    puts "  For now, you can still generate bitstream (IMem will be all zeros)."
}

# ---- 完成 ----
puts ""
puts "=================================="
puts "Vivado project 'cpu_project' created."
puts "Top module : TopDebug"
puts "FPGA part  : xc7a35tcsg324-1 (EGO1)"
puts "Source files: [llength [glob $src_dir/*.v]] Verilog files"
puts "=================================="
puts ""
puts "Next steps:"
puts "  1. Confirm assembly/batch_test.hex exists"
puts "  2. Run Synthesis  -> Run Implementation -> Generate Bitstream"
puts "  3. Program EGO1 board with TopDebug.bit"
puts "=================================="
