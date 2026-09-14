# Modular version of GeneratedSrc.cmake
# This file builds the project using modular FSP libraries

# Include FSP module definitions
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_bsp.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_uart.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_flash.cmake)

# Application source files (user code in src/)
file(GLOB_RECURSE App_Source_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp
)

# Generated HAL data (peripheral configurations)
set(HAL_Generated_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/hal_data.c
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/main.c
)

# Main executable
add_executable(${PROJECT_NAME}.elf
    ${App_Source_Files}
    ${HAL_Generated_Files}
)

# Link against FSP modules
target_link_libraries(${PROJECT_NAME}.elf
    PRIVATE
        fsp_bsp      # Board Support Package (always required)
        fsp_uart     # UART module
        fsp_flash    # Flash module
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

# Post-build: Create S-record file
add_custom_command(
    TARGET ${PROJECT_NAME}.elf
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O srec ${PROJECT_NAME}.elf ${PROJECT_NAME}.srec
    COMMENT "Creating S-record file in ${PROJECT_BINARY_DIR}"
)

# Pre-build: RASC content generation
add_custom_command(
    OUTPUT configuration.xml.stamp
    COMMAND echo "Running RASC for generating project ${PROJECT_NAME} content since modification is detected in configuration.xml:"
    COMMAND echo ${RASC_EXE_PATH}  -nosplash --launcher.suppressErrors --generate --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml
    COMMAND ${RASC_EXE_PATH}  -nosplash --launcher.suppressErrors --generate --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION} ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml 2> rasc_cmd_log.txt
    COMMAND ${CMAKE_COMMAND} -E touch configuration.xml.stamp
    COMMENT "RASC pre-build to generate project content for ${PROJECT_NAME}"
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml
)

add_custom_target(generate_content_${PROJECT_NAME}
    DEPENDS configuration.xml.stamp
)

add_dependencies(${PROJECT_NAME}.elf generate_content_${PROJECT_NAME})

# Post-build: Generate SmartBundle file
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.sbd
    COMMAND echo "Running RASC post-build to generate Smart Bundle file for ${PROJECT_NAME}:"
    COMMAND echo ${RASC_EXE_PATH} -nosplash --launcher.suppressErrors --gensmartbundle --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION}  ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf
    COMMAND ${RASC_EXE_PATH} -nosplash --launcher.suppressErrors --gensmartbundle --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION}  ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf  2> rasc_cmd_log.txt
)

add_custom_target(generate_sbd_${PROJECT_NAME} ALL
    DEPENDS
        ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.sbd
        ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf
    VERBATIM
)

add_dependencies(generate_sbd_${PROJECT_NAME} ${PROJECT_NAME}.elf)

add_custom_command(
    TARGET ${PROJECT_NAME}.elf
    POST_BUILD
    COMMAND echo ${RASC_EXE_PATH} -nosplash --launcher.suppressErrors --gensmartbundle --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION}  ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf
    COMMAND ${RASC_EXE_PATH} -nosplash --launcher.suppressErrors --gensmartbundle --devicefamily ra --compiler GCC --toolchainversion ${CMAKE_C_COMPILER_VERSION}  ${CMAKE_CURRENT_SOURCE_DIR}/configuration.xml ${CMAKE_CURRENT_BINARY_DIR}/${PROJECT_NAME}.elf  2> rasc_cmd_log.txt
    VERBATIM
)