#-------------------------------------------------------------------------------
# Copyright (c) 2025-2026, Renesas Electronics Corporation. All rights reserved.
# SPDX-License-Identifier: BSD-3-Clause
#
# TF-M Integration Layer for FSP MCUboot Bootloader (BL2)
#-------------------------------------------------------------------------------
#
# Provides the FSP-generated BL2 sources to TF-M's BL2 build, organized into the
# module separation TF-M requires. Sources are SELECTED FROM THE RASC-GENERATED
# TREE VIA DIRECTORY GLOBS (never a hand-maintained file list, and never editing
# RASC output), so newer RASC/FSP/mbedTLS versions are picked up automatically.
#
# Division of responsibility (see fsp_cmake/TFM_RA6M4_STATUS.md):
#   - MCUboot bootutil core : TF-M builds it from MCUBOOT_PATH, which config.cmake
#                             points at THIS project's ra/mcu-tools/MCUboot (no download).
#   - Flash abstraction     : RASC rm_mcuboot_port/flash_map.c (RA 32K region-1 geometry).
#   - Boot/app-jump port    : RASC rm_mcuboot_port.c.
#   - Crypto                : software mbedTLS (MCUBOOT_USE_MBED_TLS + a USER config that
#                             disables the SCE9 ALT macros; TRNG entropy kept).
#   - NV counters / signing : TF-M's security_cnt.c / the RASC signing script (wired in
#                             the platform CMakeLists.txt).
#-------------------------------------------------------------------------------

cmake_minimum_required(VERSION 3.21)

set(FSP_BL2_PROJECT_DIR ${CMAKE_CURRENT_LIST_DIR}/..)

message(STATUS "FSP BL2 Integration: Using FSP MCUboot/port from ${FSP_BL2_PROJECT_DIR}")

# Include FSP project configuration (flags/definitions)
include(${FSP_BL2_PROJECT_DIR}/Config.cmake)
include(${FSP_BL2_PROJECT_DIR}/cmake/GeneratedCfg.cmake)

# Filter FP flags to match TF-M's soft float ABI
string(REGEX REPLACE "(-mfloat-abi=[^ ]+|-mfpu=[^ ]+|--specs=[^ ]+|-specs=[^ ]+)" "" RASC_CMAKE_C_FLAGS "${RASC_CMAKE_C_FLAGS}")
string(REGEX REPLACE "(-mfloat-abi=[^ ]+|-mfpu=[^ ]+|--specs=[^ ]+|-specs=[^ ]+)" "" RASC_CMAKE_EXE_LINKER_FLAGS "${RASC_CMAKE_EXE_LINKER_FLAGS}")

# Common soft-float/CM33 options for every FSP BL2 library
set(FSP_BL2_COMMON_OPTS
    -mfloat-abi=soft -mcpu=cortex-m33 -mthumb
    $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
    $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
)

#===============================================================================
# FSP BSP Library for BL2
#===============================================================================
if(NOT TARGET fsp_bsp_bl2)
    add_library(fsp_bsp_bl2 STATIC)

    # Select BSP/driver/generated sources from the RASC tree by directory glob.
    file(GLOB FSP_BSP_BL2_SRC CONFIGURE_DEPENDS
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/all/*.c
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/ra6m4/*.c
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/cmsis/Device/RENESAS/Source/*.c
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_ioport/*.c
        ${FSP_BL2_PROJECT_DIR}/ra_gen/*.c
    )
    # TF-M/MCUboot provides the bootloader entry point; drop the FSP app main().
    list(FILTER FSP_BSP_BL2_SRC EXCLUDE REGEX "/ra_gen/main\\.c$")
    target_sources(fsp_bsp_bl2 PRIVATE ${FSP_BSP_BL2_SRC})

    # Apply the SAME include set RASC enumerates for the project (GeneratedSrc.cmake),
    # PUBLIC so the other FSP BL2 libs inherit it. The RASC ra_gen HAL data references
    # the project's full module set (mbedTLS, rm_psa_crypto, r_sce, mcuboot, ...), so
    # the whole RASC include set is required - mirroring it here keeps this drift-proof.
    target_include_directories(fsp_bsp_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/arm/CMSIS_6/CMSIS/Core/Include
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/include
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/api
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/instances
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/bsp/mcu/ra6m4
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_sce
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_sce/common
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_sce/crypto_procedures/src/sce9/plainkey/primitive
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_sce/crypto_procedures/src/sce9/plainkey/private/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_sce/crypto_procedures/src/sce9/plainkey/public/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_psa_crypto/inc
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/include
            ${FSP_BL2_PROJECT_DIR}/ra/mcu-tools/MCUboot/boot/bootutil/src
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/arm
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/arm/mbedtls
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/fsp_cfg
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/fsp_cfg/bsp
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/mcuboot_config
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/sysflash
            ${FSP_BL2_PROJECT_DIR}/ra_gen
            ${FSP_BL2_PROJECT_DIR}/src
            ${FSP_BL2_PROJECT_DIR}
            ${CMAKE_CURRENT_LIST_DIR}   # mbedtls_user_config.h
    )
    target_compile_definitions(fsp_bsp_bl2
        PUBLIC
            ${RASC_CMAKE_DEFINITIONS}
        PRIVATE
            # Only fsp_bsp_bl2's own RASC ra_gen sources (common_data.c/hal_data.c)
            # pull mbedTLS headers. Keep these PRIVATE so the FSP mbedTLS config does
            # not leak into the bl2 executable / bootutil (which use TF-M's crypto).
            MBEDTLS_CONFIG_FILE="config.h"
            MBEDTLS_USER_CONFIG_FILE="mbedtls_user_config.h"
    )
    target_compile_options(fsp_bsp_bl2 PRIVATE ${FSP_BL2_COMMON_OPTS})
endif()

#===============================================================================
# FSP Flash Driver for BL2
#===============================================================================
if(NOT TARGET fsp_flash_bl2)
    add_library(fsp_flash_bl2 STATIC)
    file(GLOB FSP_FLASH_BL2_SRC CONFIGURE_DEPENDS
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/r_flash_hp/*.c
    )
    target_sources(fsp_flash_bl2 PRIVATE ${FSP_FLASH_BL2_SRC})
    target_include_directories(fsp_flash_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/api
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/inc/instances
    )
    target_link_libraries(fsp_flash_bl2 PUBLIC fsp_bsp_bl2)
    target_compile_options(fsp_flash_bl2 PRIVATE ${FSP_BL2_COMMON_OPTS})
endif()

#===============================================================================
# FSP MCUboot Port: flash abstraction (flash_map.c) + boot/app-jump (rm_mcuboot_port.c)
# Provides flash_area_* with the correct RA6M4 32K region-1 erase geometry.
#===============================================================================
if(NOT TARGET fsp_mcuboot_port)
    add_library(fsp_mcuboot_port STATIC)
    # Top-level .c only (flash_map.c, rm_mcuboot_port.c); excludes the SCE9
    # custom_crypto_stacks/ subdirs (hardware crypto - deferred).
    file(GLOB FSP_MCUBOOT_PORT_SRC CONFIGURE_DEPENDS
        ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/*.c
    )
    target_sources(fsp_mcuboot_port PRIVATE ${FSP_MCUBOOT_PORT_SRC})
    target_include_directories(fsp_mcuboot_port
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/flash_map
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/flash_map_backend
            ${FSP_BL2_PROJECT_DIR}/ra/fsp/src/rm_mcuboot_port/os
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/mcuboot_config
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/sysflash
            ${MCUBOOT_PATH}/boot/bootutil/include
    )
    target_link_libraries(fsp_mcuboot_port PUBLIC fsp_bsp_bl2 fsp_flash_bl2)
    target_compile_options(fsp_mcuboot_port PRIVATE ${FSP_BL2_COMMON_OPTS})
endif()

#===============================================================================
# FSP mbedTLS for BL2 crypto - SOFTWARE mode.
# MCUBOOT_USE_MBED_TLS selects mbedTLS in the MCUboot crypto stack; the USER
# config disables the SCE9 crypto ALT macros (keeping TRNG entropy) so the
# portable software implementations are used. (HW/SCE9: stop passing the user
# config later.)
#===============================================================================
if(NOT TARGET fsp_mbedtls_bl2)
    add_library(fsp_mbedtls_bl2 STATIC)
    file(GLOB FSP_MBEDTLS_BL2_SRC CONFIGURE_DEPENDS
        ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library/*.c
    )
    target_sources(fsp_mbedtls_bl2 PRIVATE ${FSP_MBEDTLS_BL2_SRC})
    target_include_directories(fsp_mbedtls_bl2
        PUBLIC
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/include
            ${FSP_BL2_PROJECT_DIR}/ra/arm/mbedtls/library
            ${FSP_BL2_PROJECT_DIR}/ra_cfg/arm/mbedtls
            ${CMAKE_CURRENT_LIST_DIR}   # for mbedtls_user_config.h
    )
    target_compile_definitions(fsp_mbedtls_bl2
        PUBLIC
            MBEDTLS_CONFIG_FILE="config.h"
            MBEDTLS_USER_CONFIG_FILE="mbedtls_user_config.h"
    )
    target_link_libraries(fsp_mbedtls_bl2 PUBLIC fsp_bsp_bl2)
    target_compile_options(fsp_mbedtls_bl2 PRIVATE ${FSP_BL2_COMMON_OPTS} -Wno-conversion)
endif()

#===============================================================================
# Export for the TF-M platform CMakeLists.txt to consume
#===============================================================================
set(FSP_BL2_LINKER_SCRIPT ${FSP_BL2_PROJECT_DIR}/script/fsp.ld CACHE INTERNAL "FSP BL2 linker script")

# Libraries to link into the bl2 target (bootutil comes from TF-M via MCUBOOT_PATH).
# Option A (software crypto via TF-M's mbedcrypto): the flash port + BSP + flash
# driver are linked; fsp_mbedtls_bl2 is intentionally NOT linked (bootutil uses
# TF-M's crypto). The RASC HAL data (hal_data.c) only instantiates the flash
# module, so no FSP crypto symbols are needed. fsp_mbedtls_bl2 is still defined
# above for the future HW-crypto (SCE9) switch.
set(FSP_BL2_LIBRARIES
    fsp_bsp_bl2
    fsp_flash_bl2
    fsp_mcuboot_port
    CACHE INTERNAL "FSP BL2 libraries"
)

set(FSP_BL2_INCLUDE_DIRS
    ${FSP_BL2_PROJECT_DIR}
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/mcuboot_config
    ${FSP_BL2_PROJECT_DIR}/ra_cfg/mcu-tools/include/sysflash
    CACHE INTERNAL "FSP BL2 include directories"
)

# Software crypto for MCUboot bootutil (built by TF-M from MCUBOOT_PATH)
set(FSP_BL2_MCUBOOT_USE_MBED_TLS ON CACHE INTERNAL "MCUboot uses software mbedTLS crypto")

message(STATUS "FSP BL2 Integration: Libraries: ${FSP_BL2_LIBRARIES}")
message(STATUS "FSP BL2 Integration: MCUBOOT_PATH: ${MCUBOOT_PATH}")
