# FSP BSP (Board Support Package) Library
# This library contains core BSP functionality required by all modules

add_library(fsp_bsp STATIC)

# BSP source files
target_sources(fsp_bsp
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_common.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_clocks.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_delay.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_group_irq.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_guard.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_io.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_ipc.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_irq.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_macl.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_register_protection.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sbrk.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sdram.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/all/bsp_security.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/mcu/ra6m4/bsp_linker.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/startup.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/system.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/board/ra6m4_ek/board_init.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/board/ra6m4_ek/board_leds.c
        # Generated files
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/common_data.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/pin_data.c
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/vector_data.c
)

# BSP include directories (PUBLIC so dependent modules can use them)
target_include_directories(fsp_bsp
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/arm/CMSIS_6/CMSIS/Core/Include
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/inc
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/inc/api
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/inc/instances
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_cfg/fsp_cfg
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_cfg/fsp_cfg/bsp
        ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen
        ${CMAKE_CURRENT_SOURCE_DIR}
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
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_ioport/r_ioport.c
)