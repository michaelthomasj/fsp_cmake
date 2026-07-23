# Please see README.md for build instructions

cmake_minimum_required(VERSION 3.16.4)

set(CMAKE_SYSTEM_NAME Generic)

set(CMAKE_CONFIGURATION_TYPES Debug Release RelWithDebInfo MinSizeRel)

if(BUILD_KIT)
	message("Build Kit is defined as ${BUILD_KIT}")
endif()

message("CMAKE_CURRENT_BINARY_DIR is defined as ${CMAKE_CURRENT_BINARY_DIR}")

get_property(isMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)

if(isMultiConfig)
    message("Multi-config generator(${CMAKE_GENERATOR}) is active")
else()
    message("Single-config generator(${CMAKE_GENERATOR}) is active")
	if(DEFINED CMAKE_BUILD_TYPE)
	 	message("CMAKE_BUILD_TYPE is defined as ${CMAKE_BUILD_TYPE}")
	elseif(DEFINED BUILD_TYPE)
		set(CMAKE_BUILD_TYPE ${BUILD_TYPE})
		message("CMAKE_BUILD_TYPE is set to BUILD_TYPE ENV ${CMAKE_BUILD_TYPE}")
	else()
		message(FATAL_ERROR "Please specify the CMAKE_BUILD_TYPE with -DCMAKE_BUILD_TYPE=")
	endif()
    #set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_BUILD_TYPE})
	message("CMAKE_RUNTIME_OUTPUT_DIRECTORY is defined as ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")
endif()

cmake_minimum_required(VERSION 3.16.4)

# Project configuration
project(FSP_Project_ra6e1_bl2
	VERSION 1.0.0
	LANGUAGES C CXX ASM)

set(CMAKE_CROSSCOMPILING "TRUE")
set(CMAKE_EXPORT_COMPILE_COMMANDS "TRUE")

include(${CMAKE_CURRENT_LIST_DIR}/Config.cmake)

include(${CMAKE_CURRENT_LIST_DIR}/cmake/GeneratedCfg.cmake)

# If required user can amend RASC generated flags here, e.g. list(REMOVE_ITEM RASC_CMAKE_C_FLAGS "-Wall")

include(${CMAKE_CURRENT_LIST_DIR}/cmake/GeneratedSrc.cmake)

# --- Auto-emit an S-record next to the ELF on every build ---
# Mirrors the TF-M build rule (trusted-firmware-m/toolchain_*.cmake). --srec-forceS3
# keeps 4-byte addresses so RA option/config-area records (0x0100A1xx, incl. BPS/PBPS)
# are captured - the primary artifact for diffing what an image actually programs.
# See fsp_cmake/DESIGN.md 8.4. (Hand-added; re-apply if RASC regenerates CMakeLists.txt.)
find_program(RA_OBJCOPY NAMES arm-none-eabi-objcopy)
if(RA_OBJCOPY)
    add_custom_command(TARGET ${PROJECT_NAME}.elf POST_BUILD
        COMMAND ${RA_OBJCOPY} -O srec --srec-forceS3
                ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf
                ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.srec
        COMMENT "Generating ${PROJECT_NAME}.srec")
else()
    message(WARNING "arm-none-eabi-objcopy not found; ${PROJECT_NAME}.srec will not be auto-generated")
endif()
