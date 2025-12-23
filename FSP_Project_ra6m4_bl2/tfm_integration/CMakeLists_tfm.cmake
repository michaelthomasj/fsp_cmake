#-------------------------------------------------------------------------------
# Copyright (c) 2025, Renesas Electronics Corporation. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# TF-M Integration Layer for FSP MCUboot Bootloader (BL2)
#-------------------------------------------------------------------------------

# This file provides FSP-based MCUboot sources and configuration to TF-M's BL2 build
# It's included by TF-M platform CMakeLists.txt when FSP_BL2_APP_DIR is set

cmake_minimum_required(VERSION 3.21)

set(FSP_BL2_PROJECT_DIR ${CMAKE_CURRENT_LIST_DIR}/..)

message(STATUS "FSP BL2 Integration: Using FSP MCUboot from ${FSP_BL2_PROJECT_DIR}")

# Include FSP project configuration
include(${FSP_BL2_PROJECT_DIR}/Config.cmake)
include(${FSP_BL2_PROJECT_DIR}/cmake/GeneratedCfg.cmake)

# Filter FP flags to match TF-M's soft float ABI
string(REGEX REPLACE "(-mfloat-abi=[^ ]+|-mfpu=[^ ]+|--specs=[^ ]+|-specs=[^ ]+)" "" RASC_CMAKE_C_FLAGS "${RASC_CMAKE_C_FLAGS}")
string(REGEX REPLACE "(-mfloat-abi=[^ ]+|-mfpu=[^ ]+|--specs=[^ ]+|-specs=[^ ]+)" "" RASC_CMAKE_EXE_LINKER_FLAGS "${RASC_CMAKE_EXE_LINKER_FLAGS}")

#===============================================================================
# FSP BSP Library for BL2 (separate from secure/NS BSP)
#===============================================================================

if(NOT TARGET fsp_bsp_bl2)
    add_library(fsp_bsp_bl2 STATIC)

    # BSP core source files
    target_sources(fsp_bsp_bl2
        PRIVATE
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_common.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_clocks.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_delay.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_group_irq.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_guard.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_io.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_irq.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_register_protection.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_sbrk.c
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/bsp_security.c
            # Linker init (provides g_init_info, OFS data)
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/ra6m4/bsp_linker.c
            # System init
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/system.c
            # Startup (provides Reset_Handler, vector table)
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/startup.c
            # I/O Port driver
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_ioport/r_ioport.c
            # Generated files
            ${FSP_BL2_PROJECT_DIR}/ra_gen/common_data.c
            ${FSP_BL2_PROJECT_DIR}/ra_gen/pin_data.c
            ${FSP_BL2_PROJECT_DIR}/ra_gen/vector_data.c
    )

    # BSP include directories
    target_include_directories(fsp_bsp_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/arm/CMSIS_6/CMSIS/Core/Include
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/api
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/instances
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/ra6m4
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/fsp_cfg
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/fsp_cfg/bsp
            ${FSP_BL2_PROJECT_DIR}/ra_gen
            ${FSP_BL2_PROJECT_DIR}
    )

    # BSP compile definitions
    target_compile_definitions(fsp_bsp_bl2
        PUBLIC
            ${RASC_CMAKE_DEFINITIONS}
    )

    # BSP compile options
    target_compile_options(fsp_bsp_bl2
        PRIVATE
            -mfloat-abi=soft
            -mcpu=cortex-m33
            -mthumb
            $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
            $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
            $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
    )
endif()

#===============================================================================
# FSP Flash Driver for BL2
#===============================================================================

if(NOT TARGET fsp_flash_bl2)
    add_library(fsp_flash_bl2 STATIC)

    target_sources(fsp_flash_bl2
        PRIVATE
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_flash_hp/r_flash_hp.c
    )

    target_include_directories(fsp_flash_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/api
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/instances
    )

    target_link_libraries(fsp_flash_bl2
        PUBLIC
            fsp_bsp_bl2
    )

    target_compile_options(fsp_flash_bl2
        PRIVATE
            -mfloat-abi=soft
            -mcpu=cortex-m33
            -mthumb
            $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    )
endif()

#===============================================================================
# FSP MCUboot Port Library
#===============================================================================

if(NOT TARGET fsp_mcuboot_port)
    add_library(fsp_mcuboot_port STATIC)

    target_sources(fsp_mcuboot_port
        PRIVATE
            # MCUboot port for FSP
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/rm_mcuboot_port.c
            # Flash map backend
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/flash_map_backend/flash_map_backend.c
    )

    target_include_directories(fsp_mcuboot_port
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/flash_map
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/flash_map_backend
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/os
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/mcuboot_config
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/sysflash
    )

    target_link_libraries(fsp_mcuboot_port
        PUBLIC
            fsp_bsp_bl2
            fsp_flash_bl2
    )

    target_compile_options(fsp_mcuboot_port
        PRIVATE
            -mfloat-abi=soft
            -mcpu=cortex-m33
            -mthumb
            $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    )
endif()

#===============================================================================
# MCUboot Core Library (Renesas Fork v2.1.0+renesas.3)
#===============================================================================

if(NOT TARGET fsp_mcuboot)
    add_library(fsp_mcuboot STATIC)

    target_sources(fsp_mcuboot
        PRIVATE
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/boot_record.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/bootutil_misc.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/bootutil_public.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/caps.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/encrypted.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/fault_injection_hardening.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/fault_injection_hardening_delay_rng_mbedtls.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/image_ecdsa.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/image_validate.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/loader.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/swap_misc.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/swap_move.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/swap_scratch.c
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src/tlv.c
    )

    target_include_directories(fsp_mcuboot
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/include
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src
    )

    target_link_libraries(fsp_mcuboot
        PUBLIC
            fsp_mcuboot_port
    )

    target_compile_options(fsp_mcuboot
        PRIVATE
            -mfloat-abi=soft
            -mcpu=cortex-m33
            -mthumb
            $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    )
endif()

#===============================================================================
# mbedTLS Library for MCUboot (crypto operations)
#===============================================================================

if(NOT TARGET fsp_mbedtls_bl2)
    add_library(fsp_mbedtls_bl2 STATIC)

    # Core mbedTLS sources needed by MCUboot
    target_sources(fsp_mbedtls_bl2
        PRIVATE
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/aes.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/asn1parse.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/bignum.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/bignum_core.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/constant_time.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/ecdsa.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/ecp.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/ecp_curves.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/hash_info.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/md.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/oid.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/pk.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/pk_ecc.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/pk_wrap.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/pkparse.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/platform.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/platform_util.c
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/sha256.c
    )

    target_include_directories(fsp_mbedtls_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/include
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/arm/mbedtls
    )

    target_link_libraries(fsp_mbedtls_bl2
        PUBLIC
            fsp_bsp_bl2
    )

    target_compile_definitions(fsp_mbedtls_bl2
        PRIVATE
            MBEDTLS_CONFIG_FILE="config.h"
    )

    target_compile_options(fsp_mbedtls_bl2
        PRIVATE
            -mfloat-abi=soft
            -mcpu=cortex-m33
            -mthumb
            $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
            -Wno-conversion  # mbedTLS has many conversion warnings
    )
endif()

#===============================================================================
# Export variables for TF-M platform integration
#===============================================================================

# The FSP BL2 project linker script (includes OFS regions)
set(FSP_BL2_LINKER_SCRIPT ${FSP_BL2_PROJECT_DIR}/script/fsp.ld CACHE INTERNAL "FSP BL2 linker script")

# FSP BL2 libraries to link
set(FSP_BL2_LIBRARIES
    fsp_bsp_bl2
    fsp_flash_bl2
    fsp_mcuboot_port
    fsp_mcuboot
    fsp_mbedtls_bl2
    CACHE INTERNAL "FSP BL2 libraries"
)

# FSP BL2 include directories
set(FSP_BL2_INCLUDE_DIRS
    ${FSP_BL2_PROJECT_DIR}
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/mcuboot_config
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/sysflash
    CACHE INTERNAL "FSP BL2 include directories"
)

message(STATUS "FSP BL2 Integration: Libraries: ${FSP_BL2_LIBRARIES}")
message(STATUS "FSP BL2 Integration: Linker script: ${FSP_BL2_LINKER_SCRIPT}")
