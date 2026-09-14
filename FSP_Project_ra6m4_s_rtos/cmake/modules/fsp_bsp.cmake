# FSP BSP (Board Support Package) Module Library
# This module provides core MCU support, CMSIS, and RASC-generated configuration files

# Define base directory for FSP modules (used by other modules)
set(FSP_MODULE_BASE_DIR ${CMAKE_CURRENT_SOURCE_DIR})

add_library(fsp_bsp STATIC)

# BSP source files
target_sources(fsp_bsp
    PRIVATE
        # BSP core
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
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sdram.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_security.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sbrk.c

        # RA6M4-specific BSP
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/mcu/ra6m4/bsp_linker.c

        # CMSIS startup and system
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/startup.c
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/system.c

        # Board-specific files (RA6M4-EK)
        ${FSP_MODULE_BASE_DIR}/ra/board/ra6m4_ek/board_init.c
        ${FSP_MODULE_BASE_DIR}/ra/board/ra6m4_ek/board_leds.c

        # RASC-generated configuration files
        ${FSP_MODULE_BASE_DIR}/ra_gen/common_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/hal_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/pin_data.c
        ${FSP_MODULE_BASE_DIR}/ra_gen/vector_data.c

        # IOPORT driver (always needed for pin configuration)
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_ioport/r_ioport.c
)

# BSP include directories (PUBLIC so dependent modules can use them)
target_include_directories(fsp_bsp
    PUBLIC
        ${FSP_MODULE_BASE_DIR}/ra/arm/CMSIS_6/CMSIS/Core/Include
        ${FSP_MODULE_BASE_DIR}/ra/board/ra6m4_ek
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc/api
        ${FSP_MODULE_BASE_DIR}/ra/fsp/inc/instances
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Include
        ${FSP_MODULE_BASE_DIR}/ra_cfg/fsp_cfg
        ${FSP_MODULE_BASE_DIR}/ra_cfg/fsp_cfg/bsp
        ${FSP_MODULE_BASE_DIR}/ra_gen
        ${FSP_MODULE_BASE_DIR}/src
        ${FSP_MODULE_BASE_DIR}
        ${CMAKE_CURRENT_BINARY_DIR}
)

# BSP compile definitions (PUBLIC so dependent modules inherit them)
target_compile_definitions(fsp_bsp
    PUBLIC
        ${RASC_CMAKE_DEFINITIONS}
)

# BSP compile options
target_compile_options(fsp_bsp
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
