# FSP UART Module (SCI UART)
# Provides UART functionality via the SCI (Serial Communications Interface)

add_library(fsp_uart STATIC)

# UART source files
target_sources(fsp_uart
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_sci_uart/r_sci_uart.c
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