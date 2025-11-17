#-------------------------------------------------------------------------------
# Copyright (c) 2024, Renesas Electronics Corporation. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# TF-M Integration Layer for FSP Non-Secure FreeRTOS Application
#-------------------------------------------------------------------------------

# This file adapts the FSP non-secure project to work with TF-M's build system
# It's included by TF-M when CONFIG_TFM_USE_EXTERNAL_NS_APP=ON

cmake_minimum_required(VERSION 3.21)

set(FSP_NS_PROJECT_DIR ${CMAKE_CURRENT_LIST_DIR}/..)

# Include FSP project configuration
include(${FSP_NS_PROJECT_DIR}/Config.cmake)
include(${FSP_NS_PROJECT_DIR}/cmake/GeneratedCfg.cmake)

# Include FSP module definitions (modular build)
include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_bsp.cmake)
include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_freertos.cmake)

# Application source files
set(FSP_App_Source_Files
    ${FSP_NS_PROJECT_DIR}/src/hal_warmstart.c
    ${FSP_NS_PROJECT_DIR}/src/new_thread0_entry.c
)

# RASC-generated files
set(FSP_HAL_Generated_Files
    ${FSP_NS_PROJECT_DIR}/ra_gen/main.c
    ${FSP_NS_PROJECT_DIR}/ra_gen/new_thread0.c
)

# TF-M non-secure application target
# Note: TF-M expects the target to be named 'tfm_ns'
add_executable(tfm_ns
    ${FSP_App_Source_Files}
    ${FSP_HAL_Generated_Files}
)

# Link against FSP modules
target_link_libraries(tfm_ns
    PRIVATE
        fsp_bsp        # Board Support Package
        fsp_freertos   # FreeRTOS RTOS
        tfm_api_ns     # TF-M non-secure API
        platform_ns    # Platform NS library (CMSIS drivers, etc.)
)

# Compile definitions
target_compile_definitions(tfm_ns
    PRIVATE
        ${RASC_CMAKE_DEFINITIONS}
        TFM_NS_CLIENT=1
        DOMAIN_NS=1
        __DOMAIN_NS=1
)

# Compile options
target_compile_options(tfm_ns
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
)

# TF-M interface include directories
target_include_directories(tfm_ns
    PRIVATE
        ${FSP_NS_PROJECT_DIR}/src
        ${CMAKE_BINARY_DIR}/generated/interface/include
        ${CMAKE_SOURCE_DIR}/interface/include
        ${CMAKE_SOURCE_DIR}/interface/include/psa
        ${CMAKE_SOURCE_DIR}/interface/include/crypto
        ${CMAKE_SOURCE_DIR}/interface/include/tfm
)

# Linker options
target_link_options(tfm_ns
    PRIVATE
        $<$<LINK_LANGUAGE:C>:${RASC_CMAKE_EXE_LINKER_FLAGS}>
        -Wl,--gc-sections
        -Wl,-Map=${CMAKE_CURRENT_BINARY_DIR}/tfm_ns.map
)

# Set output properties
set_target_properties(tfm_ns
    PROPERTIES
        SUFFIX ".axf"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Generate hex and bin files
add_custom_command(TARGET tfm_ns
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O ihex $<TARGET_FILE:tfm_ns> ${CMAKE_BINARY_DIR}/bin/tfm_ns.hex
    COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:tfm_ns> ${CMAKE_BINARY_DIR}/bin/tfm_ns.bin
    COMMAND ${CMAKE_SIZE} $<TARGET_FILE:tfm_ns>
    COMMENT "Generating FSP NS application hex and bin files"
)

# Note: Secure project (secure.o / SmartBundle) integration
# =========================================================
# When building standalone FSP project, secure.o is extracted from SmartBundle
# When building with TF-M, the secure side is built by TF-M itself
# The SmartBundle is not needed in TF-M build mode
