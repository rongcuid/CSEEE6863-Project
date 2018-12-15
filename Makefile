################################################################################
#               Copyright 2006-2016 Mentor Graphics Corporation
#                            All Rights Reserved.
#               THIS WORK CONTAINS TRADE SECRET AND PROPRIETARY
#             INFORMATION WHICH IS THE PROPERTY OF MENTOR GRAPHICS 
#         CORPORATION OR ITS LICENSORS AND IS SUBJECT TO LICENSE TERMS.
################################################################################
# V10.5 Formal Quick Start Tutorial
################################################################################
run: clean compile formal 

###### Define Variables ########################################################
VLIB = ${QHOME}/modeltech/plat/vlib
VMAP = ${QHOME}/modeltech/plat/vmap
VLOG = ${QHOME}/modeltech/plat/vlog

###### Compile Design ##########################################################
compile:
	$(VLIB) work
	$(VMAP) work work
	#$(VLOG) ./src/vlog/wb_arbiter.v -pslfile ./src/assertions/arbiter_vlog.psl
	$(VLOG) -sv -mfcu -cuname mmu_sva \
		./src/vlog/BRAM_SSP.v ./src/vlog/mmu.sv
	#$(VLOG) -sv -mfcu -cuname my_bind_ovl \
	#	./src/assertions/ovl_bind.sv ./src/assertions/ovl_arbiter.sv \
	#	+libext+.v+.sv -y ${QHOME}/share/assertion_lib/OVL/verilog \
	#	+incdir+${QHOME}/share/assertion_lib/OVL/verilog \
	#	+define+OVL_SVA+OVL_ASSERT_ON+OVL_COVER_ON+OVL_XCHECK_OFF

###### Run Formal Analysis #####################################################
formal:
	qverify -c -od Output_Results -do "\
		do qs_files/directives.tcl; \
		formal compile -d mmu -cuname mmu_sva; \
		formal verify -init qs_files/mmu.init \
		-timeout 5m; \
		exit"

###### Debug Results ###########################################################
debug: 
	qverify Output_Results/formal_verify.db &

###### Clean Data ##############################################################
clean:
	qverify_clean
	\rm -rf work modelsim.ini *.wlf *.log replay* transcript *.db
	\rm -rf Output_Results *.tcl 

################################################################################
# Regressions 
################################################################################
REGRESS_FILE_LIST = \
	Output_Results/formal_property.rpt \
	Output_Results/formal_verify.rpt

regression: clean compile formal
	@rm -f regress_file_list
	@echo "# This file was generated by make" > regress_file_list
	@/bin/ls -1 $(REGRESS_FILE_LIST) >> regress_file_list
	@chmod -w regress_file_list
