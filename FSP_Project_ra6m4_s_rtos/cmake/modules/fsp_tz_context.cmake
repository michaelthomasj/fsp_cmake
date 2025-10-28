# FSP TrustZone Context Module Library
# This module provides TrustZone context management for non-secure FreeRTOS
#
# Exports NSC (Non-Secure Callable) functions:
#   - TZ_InitContextSystem_S
#   - TZ_AllocModuleContext_S
#   - TZ_FreeModuleContext_S
#   - TZ_LoadContext_S
#   - TZ_StoreContext_S

if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_tz_context STATIC)

# TrustZone context source files
target_sources(fsp_tz_context
    PRIVATE
        ${FSP_MODULE_BASE_DIR}/ra/fsp/src/rm_tz_context/tz_context.c
)

# TZ context requires BSP
target_link_libraries(fsp_tz_context
    PUBLIC
        fsp_bsp
)

# TZ context compile options
target_compile_options(fsp_tz_context
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
