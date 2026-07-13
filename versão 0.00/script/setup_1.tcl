
#Pasta do RTL
set PROJECT_DIR /home/aluno20/CAN_BTU
#Pasta da Biblioteca de timing
set LIB_DIR /pdk/gpdk045/gsclib045_svt_v4.7/gsclib045/timing
#Pasta da Biblioteca fisica
set LEF_DIR /pdk/gpdk045/gsclib045_svt_v4.7/gsclib045/lef
#Modulo principal (top)
set HDL_NAME "can_btu_top"
#Arquivos HDL - verilog
set HDL_FILES {can_btu_defines.svh can_btu_top.sv}

#Biblioteca pessimista
set WORST_LIST {slow_vdd1v0_basicCells.lib} 
#Biblioteca otimista
set BEST_LIST {fast_vdd1v0_basicCells.lib} 
#Biblioteca fisica
set LEF_LIST {gsclib045_tech.lef gsclib045_macro.lef}


#Set the search paths to the libraries and the HDL files
set_db hdl_search_path "${PROJECT_DIR}/rtl"

set_db lib_search_path "${LIB_DIR} ${LEF_DIR}"

set_db library "${WORST_LIST}"

read_hdl -sv ${HDL_FILES}

elaborate ${HDL_NAME}

set_top_module ${HDL_NAME}

check_design -unresolved ${HDL_NAME}

read_sdc ${PROJECT_DIR}/constraints/${HDL_NAME}.sdc

syn_generic ${HDL_NAME}

syn_map ${HDL_NAME}


# segunda parte:
set_db syn_generic_effort medium

# enable high-effort power optimization
set_db design_power_effort high
# optimize for both leakage and dynamic power equally
set_db opt_leakage_to_dynamic_ratio 0.5
syn_generic ${HDL_NAME}
syn_map ${HDL_NAME}
syn_opt ${HDL_NAME}


#enable high-effort power optimization
#set_db design_power_effort high

#optimize for both leakage and dynamic power equally
#set_db opt_leakage_to_dynamic_ratio 0.5


#syn_generic ${HDL_NAME}

#syn_map ${HDL_NAME}

#report_qor
#report_power -unit W




report_qor
report_power -unit W

report power  > ${HDL_NAME}_power.rpt
report timing -lint > ${HDL_NAME}_time.rpt
report timing > ${HDL_NAME}_slack.rpt
report area > ${HDL_NAME}_area.rpt
report gates > ${HDL_NAME}_gater.rpt
report qor > ${HDL_NAME}_qor.rpt
report messages > ${HDL_NAME}_messages.rpt
report summary > ${HDL_NAME}_summary.rpt
report_multibit_inferencing > ${HDL_NAME}_multibit.rpt

report_timing > ${PROJECT_DIR}/${HDL_NAME}_timing.rpt

write_hdl ${HDL_NAME} > ${PROJECT_DIR}/${HDL_NAME}.v
write_sdf  > ${PROJECT_DIR}/${HDL_NAME}.sdf
write_sdc  > ${PROJECT_DIR}/${HDL_NAME}.sdc


