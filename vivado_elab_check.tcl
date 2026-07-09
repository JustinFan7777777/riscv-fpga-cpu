set src_dir [file normalize "cpu_project/cpu_project.srcs/sources_1/new"]
read_verilog [glob -directory $src_dir *.v]
synth_design -rtl -top TopDebug -part xc7a35tcsg324-1
report_compile_order
