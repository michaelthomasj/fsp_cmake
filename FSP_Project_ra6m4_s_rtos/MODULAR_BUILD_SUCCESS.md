# Modular Build System - Secure Project with TrustZone Context

## Build Status: ✅ SUCCESS

**Date**: 2025-10-28
**Project**: FSP_Project_ra6m4_s_rtos (Secure TrustZone with TZ Context Support)

## Summary

Successfully converted RASC-generated secure TrustZone project with TrustZone context management to modular CMake structure. This secure project exports the required NSC functions for non-secure FreeRTOS applications.

## Modular Libraries Built

All FSP modules compiled into separate static libraries:

```
libfsp_bsp.a          452 KB   Board Support Package (BSP)
libfsp_uart.a         114 KB   UART (SCI) driver
libfsp_flash.a        106 KB   Flash HP (High Performance) driver
libfsp_tz_context.a    12 KB   TrustZone context management ⭐
```

**Total FSP modules size**: ~684 KB

## Build Outputs

```
FSP_Project_ra6m4_s_rtos.elf     213 KB   Final secure executable
FSP_Project_ra6m4_s_rtos.srec   9.9 KB   S-record format
FSP_Project_ra6m4_s_rtos.sbd    6.0 KB   SmartBundle for non-secure projects ⭐
FSP_Project_ra6m4_s_rtos.map     96 KB   Link map
```

## TrustZone Context Functions Exported ⭐

The `libfsp_tz_context.a` module exports all required NSC functions for non-secure FreeRTOS:

```
✅ TZ_InitContextSystem_S       Initialize secure context system
✅ TZ_AllocModuleContext_S      Allocate context memory for task
✅ TZ_FreeModuleContext_S       Free allocated context memory
✅ TZ_LoadContext_S             Restore secure context on task switch
✅ TZ_StoreContext_S            Save secure context on task switch
```

Plus ARM Compiler Secure Entry veneers:
- `__acle_se_TZ_InitContextSystem_S`
- `__acle_se_TZ_AllocModuleContext_S`
- `__acle_se_TZ_FreeModuleContext_S`
- `__acle_se_TZ_LoadContext_S`
- `__acle_se_TZ_StoreContext_S`

## Module Structure

### 1. BSP Module ([fsp_bsp.cmake](cmake/modules/fsp_bsp.cmake))
**Purpose**: Core board support and RASC-generated files

**Source Files**:
- BSP core: `bsp_common.c`, `bsp_clocks.c`, `bsp_io.c`, etc.
- CMSIS startup: `startup.c`, `system.c`
- RASC generated: `hal_data.c`, `vector_data.c`, `pin_data.c`, `common_data.c`
- IOPORT driver: `r_ioport.c`

**Dependencies**: None (base module)

### 2. UART Module ([fsp_uart.cmake](cmake/modules/fsp_uart.cmake))
**Purpose**: SCI UART driver

**Source Files**:
- `ra/fsp/src/r_sci_uart/r_sci_uart.c`

**Dependencies**: `fsp_bsp`

### 3. Flash Module ([fsp_flash.cmake](cmake/modules/fsp_flash.cmake))
**Purpose**: Flash HP (High Performance) driver

**Source Files**:
- `ra/fsp/src/r_flash_hp/r_flash_hp.c`

**Dependencies**: `fsp_bsp`

### 4. TrustZone Context Module ([fsp_tz_context.cmake](cmake/modules/fsp_tz_context.cmake)) ⭐
**Purpose**: TrustZone context management for non-secure FreeRTOS

**Source Files**:
- `ra/fsp/src/rm_tz_context/tz_context.c`

**Dependencies**: `fsp_bsp`

**Key Features**:
- Implements CMSIS TrustZone context management API
- Exports NSC functions for non-secure world
- Manages secure context stacks (8 slots, 256 bytes each)
- Stack overflow protection with seal values

## Application Files

**Main Application**:
- `src/hal_entry.c` - Application entry point
- `src/hal_warmstart.c` - Warm start handling
- `ra_gen/main.c` - RASC-generated main

## Build Configuration

- **Toolchain**: ARM GCC 13.2.1 (`arm-none-eabi-gcc`)
- **Build System**: CMake 3.16.4 + Ninja
- **Build Type**: Debug
- **Architecture**: ARM Cortex-M33 with FPU (Hard Float)
- **Target MCU**: Renesas RA6M4 (TrustZone Secure)
- **TrustZone**: Secure world with NSC exports

## SmartBundle Verification

The SmartBundle (`.sbd`) file is **6.0 KB** and contains NSC veneers for all TrustZone context functions. This is significantly larger than a project without TZ context support (which would be ~300 bytes).

**Non-secure projects** can import this SmartBundle to access the TZ context management functions required by FreeRTOS.

## Usage for Non-Secure Projects

1. **Build this secure project** to generate the SmartBundle:
   ```bash
   cd FSP_Project_ra6m4_s_rtos
   export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
   cmake --build build
   ```

2. **Reference the SmartBundle** in non-secure project's `GeneratedCfg.cmake`:
   ```cmake
   SET(RASC_SMART_BUNDLE_LOCATION "path/to/FSP_Project_ra6m4_s_rtos/build/FSP_Project_ra6m4_s_rtos.sbd")
   ```

3. **Build non-secure project** - RASC will automatically extract `secure.o` from SmartBundle

4. **Link succeeds** - TZ context functions resolved from `secure.o`

## Build Commands

### Initial Configuration
```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd FSP_Project_ra6m4_s_rtos
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
```

### Build
```bash
cmake --build build
```

### Clean Rebuild
```bash
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

### Build Individual Module
```bash
cmake --build build --target fsp_tz_context
```

## Modular Build System Benefits

1. **Clear Separation**: Each FSP module in its own static library
2. **Explicit Dependencies**: Module dependency tree visible in CMake files
3. **Incremental Builds**: Only modified modules rebuild
4. **Easy Module Addition**: Follow documented pattern
5. **Debug Support**: Build individual modules
6. **TZ Context Visibility**: Clear separation of security-critical code

## Documentation

- [cmake/modules/README.md](cmake/modules/README.md) - Detailed module documentation
- [cmake/modules/ADD_NEW_MODULE.md](cmake/modules/ADD_NEW_MODULE.md) - Guide for adding new modules
- [cmake/GeneratedSrc_Modular.cmake](cmake/GeneratedSrc_Modular.cmake) - Modular build definition

## Comparison: Monolithic vs Modular

| Aspect | Monolithic Build | Modular Build |
|--------|-----------------|---------------|
| **Structure** | All sources in one target | Separate library per module |
| **Visibility** | Hidden in GLOB_RECURSE | Explicit source files |
| **Dependencies** | Implicit | Explicit with target_link_libraries |
| **Build Time** | Full rebuild on any change | Incremental per module |
| **Debugging** | Build all or nothing | Build individual modules |
| **TZ Context** | Mixed with other code | Isolated in fsp_tz_context module |

## Next Steps

This secure project is ready to be used with non-secure FreeRTOS projects. The SmartBundle exports all required TrustZone context management functions.

**To use with non-secure project**:
1. Update non-secure `GeneratedCfg.cmake` to point to this SmartBundle
2. Rebuild non-secure project
3. Verify linker successfully resolves TZ_* functions
4. Test FreeRTOS task switching with TrustZone context management

---

**Generated**: 2025-10-28
**Toolchain**: ARM GCC 13.2.1
**CMake**: 3.16.4
**Generator**: Ninja
**TrustZone Context**: CMSIS TZ API v1.0
