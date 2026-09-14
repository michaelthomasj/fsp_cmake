# FSP UART Module Library
# This library provides SCI UART driver functionality

# Use FSP_MODULE_BASE_DIR set by fsp_bsp.cmake
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_uart STATIC)

# UART source files
target_sources(fsp_uart
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_sci_uart/r_sci_uart.c
)

# UART requires BSP
target_link_libraries(fsp_uart
    PUBLIC
        fsp_bsp
)

# UART-specific compile options (inherit from BSP)
target_compile_options(fsp_uart
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
