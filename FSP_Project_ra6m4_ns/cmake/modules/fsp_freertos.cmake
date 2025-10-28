# FSP FreeRTOS Module Library
# This library provides FreeRTOS RTOS with Renesas FSP port for ARM Cortex-M33 Non-TrustZone

# Use FSP_MODULE_BASE_DIR set by fsp_bsp.cmake
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_freertos STATIC)

# FreeRTOS kernel source files
# Note: This is a minimal FreeRTOS distribution. Heap and ARM portable layer
# are handled by the Renesas FSP FreeRTOS port (rm_freertos_port).
target_sources(fsp_freertos
    PRIVATE
        # FreeRTOS kernel core (only files present in this distribution)
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/tasks.c
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/queue.c
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/list.c
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/timers.c
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/event_groups.c
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/stream_buffer.c

        # Renesas FSP FreeRTOS port (handles memory management and ARM port)
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/rm_freertos_port/port.c
)

# FreeRTOS include directories (PUBLIC so application can use them)
target_include_directories(fsp_freertos
    PUBLIC
        ${FSP_MODULE_BASE_DIR}/ra/aws/FreeRTOS/FreeRTOS/Source/include
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/rm_freertos_port
        ${FSP_MODULE_BASE_DIR}/ra_cfg/aws
)

# FreeRTOS requires BSP
target_link_libraries(fsp_freertos
    PUBLIC
        fsp_bsp
)

# FreeRTOS-specific compile options
target_compile_options(fsp_freertos
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
