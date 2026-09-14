# FSP ADC Module Library
# This library provides ADC (Analog-to-Digital Converter) driver functionality

# Use FSP_MODULE_BASE_DIR set by fsp_bsp.cmake
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_adc STATIC)

# ADC source files
target_sources(fsp_adc
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_adc/r_adc.c
)

# ADC requires BSP
target_link_libraries(fsp_adc
    PUBLIC
        fsp_bsp
)

# ADC-specific compile options (inherit from BSP)
target_compile_options(fsp_adc
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
