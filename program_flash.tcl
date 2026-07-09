open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t_0] 0]
current_hw_device $dev
refresh_hw_device $dev
set part [lindex [get_cfgmem_parts {n25q32-3.3v-spi-x1_x2_x4}] 0]
create_hw_cfgmem -hw_device $dev $part
set cfg [current_hw_cfgmem]
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfg
set_property PROGRAM.FILES {D:/Code/riscv-fpga-cpu/cpu_project/TopDebug_spi4.mcs} $cfg
set_property PROGRAM.PRM_FILE {D:/Code/riscv-fpga-cpu/cpu_project/TopDebug_spi4.prm} $cfg
set_property PROGRAM.ERASE 1 $cfg
set_property PROGRAM.CFG_PROGRAM 1 $cfg
set_property PROGRAM.VERIFY 1 $cfg
set_property PROGRAM.BLANK_CHECK 0 $cfg
program_hw_cfgmem $cfg
boot_hw_device $dev
exit
