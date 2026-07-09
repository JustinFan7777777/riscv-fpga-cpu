open_project D:/Code/riscv-fpga-cpu/cpu_project/cpu_project.xpr
open_run impl_2
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
write_bitstream -force D:/Code/riscv-fpga-cpu/cpu_project/cpu_project.runs/impl_2/TopDebug_spi4.bit
write_cfgmem -force -format mcs -size 4 -interface SPIx4 -loadbit {up 0x00000000 D:/Code/riscv-fpga-cpu/cpu_project/cpu_project.runs/impl_2/TopDebug_spi4.bit} D:/Code/riscv-fpga-cpu/cpu_project/TopDebug_spi4.mcs
exit
