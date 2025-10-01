# FSP Flash Module (Flash HP - High Performance)
# Provides internal flash read/write/erase functionality

add_library(fsp_flash STATIC)

# Flash source files
target_sources(fsp_flash
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_flash_hp/r_flash_hp.c
)

# Flash requires BSP
target_link_libraries(fsp_flash
    PUBLIC
        fsp_bsp
)

# Flash-specific compile options (inherit from BSP)
target_compile_options(fsp_flash
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)