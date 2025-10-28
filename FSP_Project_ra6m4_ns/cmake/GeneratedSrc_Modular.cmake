# Modular version of GeneratedSrc.cmake - Non-Secure Project
# This file builds the project using modular FSP libraries

# Include FSP module definitions
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_bsp.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_icu.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_freertos.cmake)

# Application source files (user code in src/)
file(GLOB_RECURSE App_Source_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp
)

# Generated files (main, threads)
set(HAL_Generated_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/new_thread0.c
)

# Emit initial empty secure.o for the generator (will be replaced by SmartBundle)
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/secure.o)
    file(TOUCH ${CMAKE_CURRENT_SOURCE_DIR}/secure.o)
endif()

# Main executable
add_executable(${PROJECT_NAME}.elf
    ${CMAKE_CURRENT_SOURCE_DIR}/secure.o  # Secure project stub/SmartBundle
    ${App_Source_Files}
    ${HAL_Generated_Files}
)

# Link against FSP modules
target_link_libraries(${PROJECT_NAME}.elf
    PRIVATE
        fsp_bsp        # Board Support Package (always required)
        fsp_adc        # ADC module
        fsp_icu        # Interrupt Control Unit / External IRQ
        fsp_freertos   # FreeRTOS RTOS
)

# Application-level include directories (src/)
target_include_directories(${PROJECT_NAME}.elf
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR}/
)

# Application compile options (inherit from RASC config)
target_compile_options(${PROJECT_NAME}.elf
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<COMPILE_LANGUAGE:CXX>:${RASC_CMAKE_CXX_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)

# Linker configuration
target_link_directories(${PROJECT_NAME}.elf
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/script
)

# Linker options for the final executable
target_link_options(${PROJECT_NAME}.elf
    PRIVATE
        $<$<LINK_LANGUAGE:C>:${RASC_CMAKE_EXE_LINKER_FLAGS}>
        $<$<LINK_LANGUAGE:CXX>:${RASC_CMAKE_EXE_LINKER_FLAGS}>
)

# TrustZone SmartBundle Integration
# Mark the SmartBundle as a generated file and make sources depend on it
# RASC will automatically extract secure.o from the SmartBundle during generation
set_source_files_properties(${RASC_SMART_BUNDLE_LOCATION} PROPERTIES GENERATED true)

foreach(c_file ${App_Source_Files} ${HAL_Generated_Files})
    set_source_files_properties(${c_file} OBJECT_DEPENDS "${RASC_SMART_BUNDLE_LOCATION}")
endforeach(c_file)

# Post-build: Create S-record file
add_custom_command(
    TARGET ${PROJECT_NAME}.elf
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O srec ${PROJECT_NAME}.elf ${PROJECT_NAME}.srec
    COMMENT "Creating S-record file in ${PROJECT_BINARY_DIR}"
)

# Pre-build: RASC content generation
# This depends on both configuration.xml AND the SmartBundle
# RASC will extract secure.o from the SmartBundle automatically
add_custom_command(
    OUTPUT configuration.xml.stamp
    COMMAND echo "Running RASC for generating project ${PROJECT_NAME} content since modification is detected in configuration.xml or smart bundle:"
    COMMAND echo ${RASC_EXE_PATH}  -nosplash --launcher.suppressErrors --generate --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml
    COMMAND ${RASC_EXE_PATH}  -nosplash --launcher.suppressErrors --generate --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml 2> rasc_cmd_log.txt
    COMMAND ${CMAKE_COMMAND} -E touch configuration.xml.stamp
    COMMENT "RASC pre-build to generate project content for ${PROJECT_NAME}"
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml "${RASC_SMART_BUNDLE_LOCATION}"
)

add_custom_target(generate_content_${PROJECT_NAME}
    DEPENDS configuration.xml.stamp
)

add_dependencies(${PROJECT_NAME}.elf generate_content_${PROJECT_NAME})

# TrustZone Integration Notes:
# =============================
# This non-secure project automatically imports secure.o from the secure project's SmartBundle.
#
# The SmartBundle location is configured in GeneratedCfg.cmake:
#   RASC_SMART_BUNDLE_LOCATION = "path/to/FSP_Project_ra6m4_s/build/FSP_Project_ra6m4_s.sbd"
#
# When you build this project:
# 1. CMake tracks the SmartBundle as a dependency
# 2. RASC automatically extracts secure.o from the SmartBundle during pre-build
# 3. secure.o contains NSC (Non-Secure Callable) veneers for calling secure functions
# 4. The linker includes secure.o in the final binary
#
# Workflow:
# 1. Build secure project: cd ../FSP_Project_ra6m4_s && cmake --build build
# 2. Build non-secure project: cmake --build build (RASC extracts secure.o automatically)
#
# No manual SmartBundle extraction needed!
