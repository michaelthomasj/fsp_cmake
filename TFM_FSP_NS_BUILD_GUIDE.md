# TF-M + FSP Non-Secure Application - Complete Build Guide

## Overview

This guide demonstrates the **symmetric workflow** for TF-M + FSP integration on Renesas RA6M4:

- **Secure Side**: Create secure project in e2studio, build with modular CMake, integrate with TF-M
- **Non-Secure Side**: Create NS FreeRTOS project in e2studio, build with modular CMake, integrate with TF-M

Both sides follow the same pattern: **e2studio (RASC) → Modular CMake → TF-M Integration**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        TF-M Build                            │
├──────────────────────────────┬──────────────────────────────┤
│        Secure Side           │      Non-Secure Side         │
│  (TF-M PSA Services)         │   (FSP FreeRTOS Project)     │
├──────────────────────────────┼──────────────────────────────┤
│ • Attestation                │ • FreeRTOS Kernel            │
│ • Internal Trusted Storage   │ • FSP Modules (BSP, UART...) │
│ • Crypto (PSA API)           │ • Application Tasks          │
│ • Platform Services (HUK)    │ • TF-M Service Tests         │
└──────────────────────────────┴──────────────────────────────┘
```

## Quick Start

### 1. Build Secure FSP Project

```bash
cd C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_s_rtos
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build build
```

### 2. Build TF-M with External FSP NS Application

```bash
cd C:/Users/Michael/Documents/GitHub/trusted-firmware-m

cmake -S . -B build_ra6m4_fsp \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DFSP_ROOT_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4" \
  -DFSP_NS_APP_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns_rtos" \
  -DCONFIG_TFM_ENABLE_CP10CP11=ON \
  -G Ninja

cmake --build build_ra6m4_fsp
```

### 3. Flash to Hardware

```bash
cd build_ra6m4_fsp/bin

# Option 1: J-Link
JLinkExe -device R7FA6M4AF -if SWD -speed 4000
> loadfile bl2.hex
> loadfile tfm_s.hex
> loadfile tfm_ns.hex
> r
> go

# Option 2: Combined hex
srec_cat bl2.hex -Intel tfm_s.hex -Intel tfm_ns.hex -Intel \
  -o tfm_combined.hex -Intel
# Flash tfm_combined.hex with Renesas Flash Programmer
```

## Detailed Workflow

### Phase 1: Create Non-Secure FreeRTOS Project in e2studio

1. **Open e2studio**
2. **Create New RA Project**:
   - File → New → Renesas C/C++ Project
   - Board: RA6M4
   - RTOS: FreeRTOS
   - TrustZone: Non-Secure Project
   - Name: `FSP_Project_ra6m4_ns_rtos`

3. **Configure in RASC**:
   - Open `configuration.xml`
   - Add components: FreeRTOS, UART (SCI), etc.
   - Configure TrustZone: Non-Secure, link to secure project SmartBundle
   - Generate code

4. **Add Modular CMake Structure**:
   ```bash
   cd FSP_Project_ra6m4_ns_rtos

   # Create module files
   mkdir -p cmake/modules

   # See: cmake/modules/fsp_bsp.cmake
   # See: cmake/modules/fsp_freertos.cmake

   # Update: cmake/GeneratedSrc_Modular.cmake
   ```

### Phase 2: Add TF-M Integration Files

1. **Create TF-M Integration Directory**:
   ```bash
   mkdir -p tfm_integration
   ```

2. **Add Integration CMake**: [`tfm_integration/CMakeLists_tfm.cmake`](FSP_Project_ra6m4_ns_rtos/tfm_integration/CMakeLists_tfm.cmake)
   - Adapts FSP project for TF-M build system
   - Links FSP modules + TF-M NS API
   - Defines `tfm_ns` executable

3. **Add TF-M Service Tests**:
   - [`src/tfm_service_tests.h`](FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.h) - Test API
   - [`src/tfm_service_tests.c`](FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.c) - Test implementation

4. **Update Application Code**:
   Edit [`src/new_thread0_entry.c`](FSP_Project_ra6m4_ns_rtos/src/new_thread0_entry.c):
   ```c
   #include "tfm_service_tests.h"

   void new_thread0_entry(void *pvParameters)
   {
   #ifdef TFM_NS_CLIENT
       int result = run_all_tfm_tests();
       // Handle test results
   #endif
       while (1) {
           vTaskDelay(pdMS_TO_TICKS(1000));
       }
   }
   ```

5. **Update CMake to Include Tests**:
   Edit [`cmake/GeneratedSrc_Modular.cmake`](FSP_Project_ra6m4_ns_rtos/cmake/GeneratedSrc_Modular.cmake):
   ```cmake
   set(App_Source_Files
       ${CMAKE_CURRENT_SOURCE_DIR}/src/hal_warmstart.c
       ${CMAKE_CURRENT_SOURCE_DIR}/src/new_thread0_entry.c
       ${CMAKE_CURRENT_SOURCE_DIR}/src/tfm_service_tests.c  # ← Add
   )
   ```

### Phase 3: Build TF-M with External NS App

TF-M will:
1. Build secure side (PSA services)
2. Build BL2 (MCUboot)
3. Include your FSP NS project via `FSP_NS_APP_DIR`
4. Link everything into final binaries

**Build Command**:
```bash
cmake -S . -B build_ra6m4_fsp \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DFSP_ROOT_DIR="path/to/FSP_Project_ra6m4" \
  -DFSP_NS_APP_DIR="path/to/FSP_Project_ra6m4_ns_rtos" \
  -G Ninja

cmake --build build_ra6m4_fsp
```

**Output**:
```
build_ra6m4_fsp/bin/
├── bl2.bin / bl2.hex / bl2.elf
├── tfm_s.bin / tfm_s.hex / tfm_s.elf
└── tfm_ns.bin / tfm_ns.hex / tfm_ns.axf  ← Your FSP NS app
```

## Key Configuration Files

### TF-M Side

| File | Purpose |
|------|---------|
| [`platform/ext/target/renesas/ra6m4/CMakeLists.txt`](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\CMakeLists.txt) | Platform config, checks `FSP_NS_APP_DIR` |
| [`platform/ext/target/renesas/ra6m4/ns/CMakeLists.txt`](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns\CMakeLists.txt) | NS platform library (CMSIS drivers) |
| [`platform/ext/target/renesas/ra6m4/ns/cpuarch_ns.cmake`](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns\cpuarch_ns.cmake) | NS CPU architecture |
| [`platform/ext/target/renesas/ra6m4/ns_app/CMakeLists.txt`](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\CMakeLists.txt) | Built-in test app (used if no external app) |

### FSP NS Project Side

| File | Purpose |
|------|---------|
| [`tfm_integration/CMakeLists_tfm.cmake`](FSP_Project_ra6m4_ns_rtos/tfm_integration/CMakeLists_tfm.cmake) | TF-M integration adapter |
| [`cmake/GeneratedSrc_Modular.cmake`](FSP_Project_ra6m4_ns_rtos/cmake/GeneratedSrc_Modular.cmake) | Modular build system |
| [`cmake/modules/fsp_bsp.cmake`](FSP_Project_ra6m4_ns_rtos/cmake/modules/fsp_bsp.cmake) | BSP module |
| [`cmake/modules/fsp_freertos.cmake`](FSP_Project_ra6m4_ns_rtos/cmake/modules/fsp_freertos.cmake) | FreeRTOS module |
| [`src/tfm_service_tests.c`](FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.c) | TF-M service tests |
| [`src/new_thread0_entry.c`](FSP_Project_ra6m4_ns_rtos/src/new_thread0_entry.c) | Application entry (calls tests) |

## Memory Layout

### Flash (1MB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| BL2 | 0x00000000 - 0x0001FFFF | 128KB | MCUboot bootloader |
| Secure | 0x00020000 - 0x0007FFFF | 384KB | TF-M secure services |
| Non-Secure | 0x00080000 - 0x000FFFFF | 512KB | FSP FreeRTOS application |

### RAM (256KB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| Secure | 0x20000000 - 0x2001FFFF | 128KB | TF-M secure RAM |
| Non-Secure | 0x20020000 - 0x2003FFFF | 128KB | FreeRTOS heap + tasks |

## Adding New FSP Modules to NS Application

### Example: Adding ADC

1. **Open e2studio RASC**:
   - Add ADC component
   - Generate code

2. **Create ADC Module**:
   ```bash
   # cmake/modules/fsp_adc.cmake
   add_library(fsp_adc STATIC)
   target_sources(fsp_adc PRIVATE
       ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c
   )
   target_link_libraries(fsp_adc PUBLIC fsp_bsp)
   target_compile_options(fsp_adc PRIVATE
       $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
   )
   ```

3. **Update Modular Build**:
   ```cmake
   # cmake/GeneratedSrc_Modular.cmake
   include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)

   target_link_libraries(${PROJECT_NAME}.elf
       PRIVATE
           fsp_bsp
           fsp_freertos
           fsp_adc  # ← Add
   )
   ```

4. **Update TF-M Integration**:
   ```cmake
   # tfm_integration/CMakeLists_tfm.cmake
   include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_adc.cmake)

   target_link_libraries(tfm_ns
       PRIVATE
           fsp_bsp
           fsp_freertos
           fsp_adc  # ← Add
           tfm_api_ns
           platform_ns
   )
   ```

5. **Rebuild**:
   ```bash
   cd trusted-firmware-m
   cmake --build build_ra6m4_fsp
   ```

## TF-M Service Tests

### Test Functions

All tests are in [`src/tfm_service_tests.c`](FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.c):

| Function | Tests | Return Value |
|----------|-------|--------------|
| `run_all_tfm_tests()` | All services | 0 = pass, < 0 = fail |
| `test_tfm_attestation()` | Token generation | 0 = pass, -1/-2 = fail |
| `test_tfm_storage()` | ITS write/read | 0 = pass, -1/-2/-3 = fail |
| `test_tfm_crypto_random()` | Random generation | 0 = pass, -1 = fail |
| `test_tfm_crypto_hash()` | SHA-256 hash | 0 = pass, -1 to -8 = fail |
| `test_tfm_huk_derivation()` | HUK key derivation | 0 = pass, -1 to -7 = fail |

### Usage in FreeRTOS Task

```c
#include "tfm_service_tests.h"

void new_thread0_entry(void *pvParameters)
{
#ifdef TFM_NS_CLIENT
    int result = run_all_tfm_tests();

    if (result == 0) {
        printf("TF-M Tests: ALL PASSED\n");
    } else {
        printf("TF-M Tests: FAILED (code: %d)\n", result);
        // Error handling
    }
#endif

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        // Your application code
    }
}
```

### Test Sequence

```
1. tfm_ns_interface_init()      → Initialize TF-M NS interface
2. test_tfm_attestation()        → Get attestation token
3. test_tfm_storage()            → Write/read secure storage
4. test_tfm_crypto_random()      → Generate 10 bytes random
5. test_tfm_crypto_hash()        → SHA-256 with test vectors
6. test_tfm_huk_derivation()     → Derive 256-bit key from HUK
```

## Standalone FSP Build (Without TF-M)

The FSP NS project can still be built standalone for testing:

```bash
cd FSP_Project_ra6m4_ns_rtos

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build build
```

**Requirements**:
- Secure project must be built first (generates SmartBundle)
- `RASC_SMART_BUNDLE_LOCATION` in `Config.cmake` must point to SmartBundle
- TF-M test functions will be stubbed (return -1)

**Use Cases**:
- Test FreeRTOS task scheduling
- Debug FSP module integration
- Develop application logic without TF-M

## Build Options

### Required Options

| Option | Description | Example |
|--------|-------------|---------|
| `-DTFM_PLATFORM` | Select platform | `renesas/ra6m4` |
| `-DFSP_ROOT_DIR` | FSP standalone project | Path to `FSP_Project_ra6m4` |
| `-DFSP_NS_APP_DIR` | FSP NS application | Path to `FSP_Project_ra6m4_ns_rtos` |

### Optional Options

| Option | Default | Description |
|--------|---------|-------------|
| `-DCONFIG_TFM_ENABLE_CP10CP11` | OFF | Enable FPU (recommended for M33) |
| `-DCMAKE_BUILD_TYPE` | Debug | Release / Debug / MinSizeRel |
| `-DBL2` | ON | Include MCUboot bootloader |
| `-DTEST_S` | OFF | Build TF-M secure tests |
| `-DTEST_NS` | OFF | Build TF-M non-secure tests |

## Debugging

### UART Console

Connect UART0 (SCI0) at 115200 baud. Add logging in your FreeRTOS task:

```c
#include <stdio.h>

printf("Starting TF-M tests...\n");
int result = run_all_tfm_tests();
printf("Test result: %d\n", result);
```

### GDB Debugging

```bash
arm-none-eabi-gdb build_ra6m4_fsp/bin/tfm_ns.axf

(gdb) target remote localhost:2331
(gdb) load
(gdb) break test_tfm_attestation
(gdb) break test_tfm_storage
(gdb) break test_tfm_crypto_hash
(gdb) continue
```

### Breakpoint Locations

| Location | Purpose |
|----------|---------|
| `new_thread0_entry` | NS application entry |
| `run_all_tfm_tests` | Start of test sequence |
| `test_tfm_attestation:49` | After token size query |
| `test_tfm_storage:87` | After ITS read |
| `test_tfm_crypto_hash:146` | After first SHA-256 verify |
| `test_tfm_huk_derivation:204` | After key export |

## Troubleshooting

### Issue 1: TF-M Integration File Not Found

**Error**:
```
TF-M integration file not found in FSP NS application.
Expected: .../FSP_Project_ra6m4_ns_rtos/tfm_integration/CMakeLists_tfm.cmake
```

**Fix**: Create `tfm_integration/CMakeLists_tfm.cmake` in your FSP NS project

### Issue 2: FSP Module Not Found

**Error**:
```
Could not find fsp_bsp.cmake
```

**Fix**: Ensure FSP_ROOT_DIR and FSP_NS_APP_DIR have modular CMake structure:
```bash
# Check FSP_ROOT_DIR has base modules
ls "${FSP_ROOT_DIR}/cmake/modules/"
# Should show: fsp_bsp.cmake, fsp_uart.cmake, fsp_flash.cmake

# Check FSP_NS_APP_DIR has FreeRTOS module
ls "${FSP_NS_APP_DIR}/cmake/modules/"
# Should show: fsp_bsp.cmake, fsp_freertos.cmake
```

### Issue 3: TF-M APIs Undefined at Link Time

**Error**:
```
undefined reference to 'psa_initial_attest_get_token'
```

**Fix**: Ensure `tfm_api_ns` is linked in `tfm_integration/CMakeLists_tfm.cmake`:
```cmake
target_link_libraries(tfm_ns
    PRIVATE
        tfm_api_ns  # ← Required
        platform_ns
        fsp_bsp
        fsp_freertos
)
```

### Issue 4: Stack Overflow in FreeRTOS

**Symptom**: Hangs or crashes after starting tests

**Fix**: Increase FreeRTOS heap or task stack:
```c
// In FreeRTOSConfig.h
#define configTOTAL_HEAP_SIZE  ((size_t)(128 * 1024))  // Increase from 64KB

// In new_thread0.c (or RASC configuration)
#define NEW_THREAD0_STACK_SIZE (8192)  // Increase from 4096
```

## Summary

✅ **Symmetric Workflow**: NS side follows same pattern as secure side (e2studio → CMake → TF-M)
✅ **Modular FSP**: Easy to add new modules via RASC
✅ **External NS App**: TF-M uses your FSP project directly
✅ **TF-M Services**: Test PSA APIs from FreeRTOS tasks
✅ **Standalone Build**: Can build FSP project without TF-M

**Key Concept**: Just like you can create a secure project in e2studio and integrate it with TF-M, you can now create a non-secure FreeRTOS project in e2studio and integrate it with TF-M!

## Next Steps

1. ✅ Add `tfm_service_tests.c` to your FSP NS project
2. ✅ Call `run_all_tfm_tests()` in your FreeRTOS task
3. ✅ Build with TF-M: `cmake ... -DFSP_NS_APP_DIR=...`
4. ⬜ Flash to hardware
5. ⬜ Verify tests pass via UART or GDB

## References

- [TF-M RA6M4 Platform README](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\README.md)
- [TF-M Integration Complete](C:\Users\Michael\Documents\GitHub\fsp_cmake\TFM_INTEGRATION_COMPLETE.md)
- [FSP NS Project TF-M Integration](C:\Users\Michael\Documents\GitHub\fsp_cmake\FSP_Project_ra6m4_ns_rtos\TFM_INTEGRATION.md)
- [FSP Modular CMake Guide](C:\Users\Michael\Documents\GitHub\fsp_cmake\FSP_Project_ra6m4\cmake\modules\README.md)
