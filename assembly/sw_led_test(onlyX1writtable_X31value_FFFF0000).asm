.text 		        # instructions	
main: 	       	
	# MMIO base address(x31) = 0xFFFF0000, +0(switch), +8(LED)
	lw   x1, 0(x31)	   #copy data from switch to register x1
	sw  x1, 8(x31)	   #copy data from register x1 to led			
	j main                     # jump to the instructions labled by main
