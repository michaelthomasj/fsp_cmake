# FSP Flash Module Library
# This module provides Flash HP (High Performance) driver support

if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_flash STATIC)

# Flash source files
target_sources(fsp_flash
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_flash_hp/r_flash_hp.c
)

# Flash requires BSP
target_link_libraries(fsp_flash
    PUBLIC
        fsp_bsp
)

# Flash compile options
target_compile_options(fsp_flash
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
