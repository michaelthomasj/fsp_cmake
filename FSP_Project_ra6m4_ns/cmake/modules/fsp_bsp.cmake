# FSP BSP (Board Support Package) Library - Non-Secure
# This library contains core BSP functionality required by all modules

# Set base directory for FSP if not already set
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    set(FSP_MODULE_BASE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
endif()

add_library(fsp_bsp STATIC)

# BSP source files
target_sources(fsp_bsp
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_common.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_clocks.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_delay.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_group_irq.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_guard.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_io.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_ipc.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_irq.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_macl.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_register_protection.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sbrk.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sdram.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_security.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/ra6m4/bsp_linker.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/startup.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/system.c
        ${FSP_MODULE_BASE_DIR}/ra/board/ra6m4_ek/board_init.c
        ${FSP_MODULE_BASE_DIR}/ra/board/ra6m4_ek/board_leds.c
        # Generated files
        ${FSP_MODULE_BASE_DIR}/ra_gen/common_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/pin_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/vector_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/hal_data.c
)

# BSP include directories (PUBLIC so dependent modules can use them)
target_include_directories(fsp_bsp
    PUBLIC
        ${FSP_MODULE_BASE_DIR}/ra/arm/CMSIS_6/CMSIS/Core/Include
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc/api
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc/instances
        ${FSP_MODULE_BASE_DIR}/ra_cfg/fsp_cfg
        ${FSP_MODULE_BASE_DIR}/ra_cfg/fsp_cfg/bsp
        ${FSP_MODULE_BASE_DIR}/ra_gen
        ${FSP_MODULE_BASE_DIR}
)

# BSP compile definitions
target_compile_definitions(fsp_bsp
    PUBLIC
        ${RASC_CMAKE_DEFINITIONS}
)

# BSP compile options
target_compile_options(fsp_bsp
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<COMPILE_LANGUAGE:CXX>:${RASC_CMAKE_CXX_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)

# I/O Port driver (required by most peripherals)
target_sources(fsp_bsp
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_ioport/r_ioport.c
)
