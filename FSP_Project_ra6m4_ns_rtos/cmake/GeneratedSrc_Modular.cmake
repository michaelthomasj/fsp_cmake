# Modular FSP Build System for Non-Secure TrustZone Project with FreeRTOS
# This file replaces the monolithic GLOB_RECURSE approach with explicit module definitions

# Include FSP module definitions
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_bsp.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_freertos.cmake)

# Application source files
set(App_Source_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/src/hal_warmstart.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/new_thread0_entry.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/tfm_service_tests.c
)

# RASC-generated files (note: common_data.c, hal_data.c, pin_data.c, vector_data.c
# are in fsp_bsp module to ensure they're built first)
set(HAL_Generated_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/ra_gen/new_thread0.c
)

# Emit initial empty secure.o (will be replaced by SmartBundle)
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/secure.o)
    file(TOUCH ${CMAKE_CURRENT_SOURCE_DIR}/secure.o)
endif()

# Main executable
add_executable(${PROJECT_NAME}.elf
    ${CMAKE_CURRENT_SOURCE_DIR}/secure.o  # Secure project interface (from SmartBundle)
    ${App_Source_Files}
    ${HAL_Generated_Files}
)

# Link against FSP modules
target_link_libraries(${PROJECT_NAME}.elf
    PRIVATE
        fsp_bsp        # Board Support Package
        fsp_freertos   # FreeRTOS RTOS
)

# Target compile definitions
target_compile_definitions(${PROJECT_NAME}.elf
    PRIVATE
        ${RASC_CMAKE_DEFINITIONS}
)

# Target compile options
target_compile_options(${PROJECT_NAME}.elf
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
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

# Post-build: Generate SmartBundle (.sbd) file
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

# TrustZone Integration Notes:
# =============================
# This non-secure project automatically imports secure.o from the secure project's SmartBundle.
#
# The SmartBundle location is configured in GeneratedCfg.cmake:
#   RASC_SMART_BUNDLE_LOCATION = "path/to/FSP_Project_ra6m4_s_rtos/build/FSP_Project_ra6m4_s_rtos.sbd"
#
# When you build this project:
# 1. CMake tracks the SmartBundle as a dependency
# 2. RASC automatically extracts secure.o from the SmartBundle during pre-build
# 3. secure.o contains NSC (Non-Secure Callable) veneers for calling secure functions
# 4. The linker includes secure.o in the final binary
#
# The secure project (FSP_Project_ra6m4_s_rtos) provides TrustZone context management functions
# required by FreeRTOS in the non-secure world:
#   - TZ_InitContextSystem_S
#   - TZ_AllocModuleContext_S
#   - TZ_FreeModuleContext_S
#   - TZ_LoadContext_S
#   - TZ_StoreContext_S
#
# Workflow:
# 1. Build secure project: cd ../FSP_Project_ra6m4_s_rtos && cmake --build build
# 2. Build non-secure project: cmake --build build (RASC extracts secure.o automatically)
#
# No manual SmartBundle extraction needed!
