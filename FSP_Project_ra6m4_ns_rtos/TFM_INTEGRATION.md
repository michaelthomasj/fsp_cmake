# TF-M Integration Guide for FSP Non-Secure FreeRTOS Project

This guide explains how to integrate this FSP-based FreeRTOS non-secure project with Trusted Firmware-M (TF-M) for the Renesas RA6M4.

## Overview

This approach allows you to:
1. **Create and modify** your non-secure FreeRTOS application in e2studio using RASC
2. **Build with CMake** using the modular FSP structure
3. **Integrate with TF-M** to use PSA secure services
4. **Test TF-M services** from your FreeRTOS tasks

## Architecture

```
TF-M Build System
    ├── Secure Side (built by TF-M)
    │   ├── PSA Attestation Service
    │   ├── PSA Internal Trusted Storage
    │   ├── PSA Crypto Service
    │   └── Platform Services (HUK)
    │
    └── Non-Secure Side (your FSP project)
        ├── FreeRTOS Kernel
        ├── FSP Modules (BSP, UART, etc.)
        ├── Your Application Code
        └── TF-M Service Tests
```

## Prerequisites

1. **FSP Project Setup**: This project already configured with:
   - FreeRTOS component
   - TrustZone non-secure configuration
   - Modular CMake build system

2. **TF-M Repository**: Clone and set up TF-M:
   ```bash
   cd C:/Users/Michael/Documents/GitHub
   git clone https://github.com/ARM-software/trusted-firmware-m.git
   cd trusted-firmware-m
   git submodule update --init
   ```

3. **Toolchain**:
   ```bash
   export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
   ```

## Step 1: Add TF-M Test Code to Your FreeRTOS Task

The TF-M service test functions are available in:
- [`src/tfm_service_tests.h`](src/tfm_service_tests.h) - Header with test function declarations
- [`src/tfm_service_tests.c`](src/tfm_service_tests.c) - Implementation of all TF-M service tests

### Update Your FreeRTOS Thread

Edit [`src/new_thread0_entry.c`](src/new_thread0_entry.c) to call TF-M tests:

```c
#include "new_thread0.h"
#include "tfm_service_tests.h"  // ← Add this

/* New Thread entry function */
void new_thread0_entry(void *pvParameters)
{
    FSP_PARAMETER_NOT_USED(pvParameters);

#ifdef TFM_NS_CLIENT
    /* Run all TF-M service tests */
    int result = run_all_tfm_tests();

    if (result == 0) {
        /* All tests passed */
        while (1) {
            vTaskDelay(pdMS_TO_TICKS(1000));
            /* Application code here */
        }
    } else {
        /* Test failed - error code in result */
        while (1) {
            /* Error handling */
        }
    }
#else
    /* Standalone FSP project without TF-M */
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
#endif
}
```

### Available Test Functions

- `run_all_tfm_tests()` - Runs all tests sequentially
- `test_tfm_attestation()` - Test Initial Attestation
- `test_tfm_storage()` - Test Internal Trusted Storage
- `test_tfm_crypto_random()` - Test random number generation
- `test_tfm_crypto_hash()` - Test SHA-256 hashing
- `test_tfm_huk_derivation()` - Test HUK key derivation

All functions return 0 on success, negative values on failure.

## Step 2: Update CMake to Include TF-M Tests

Edit [`cmake/GeneratedSrc_Modular.cmake`](cmake/GeneratedSrc_Modular.cmake):

```cmake
# Application source files
set(App_Source_Files
    ${CMAKE_CURRENT_SOURCE_DIR}/src/hal_warmstart.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/new_thread0_entry.c
    ${CMAKE_CURRENT_SOURCE_DIR}/src/tfm_service_tests.c  # ← Add this
)
```

## Step 3: Build TF-M with External FSP NS Application

### Configure TF-M Build

```bash
cd C:/Users/Michael/Documents/GitHub/trusted-firmware-m

cmake -S . -B build_ra6m4_fsp \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DFSP_ROOT_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4" \
  -DFSP_NS_APP_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns_rtos" \
  -DCONFIG_TFM_USE_EXTERNAL_NS_APP=ON \
  -DCONFIG_TFM_ENABLE_CP10CP11=ON \
  -G Ninja
```

### Build

```bash
cmake --build build_ra6m4_fsp
```

### Output

```
build_ra6m4_fsp/bin/
├── bl2.bin          ← MCUboot bootloader (128KB)
├── bl2.hex
├── tfm_s.bin        ← TF-M secure firmware (384KB)
├── tfm_s.hex
├── tfm_ns.bin       ← Your FSP NS FreeRTOS app (512KB)
├── tfm_ns.hex
└── tfm_ns.axf       ← NS application ELF with debug symbols
```

## Step 4: Flash to Hardware

### Option 1: J-Link Commander

```bash
JLinkExe -device R7FA6M4AF -if SWD -speed 4000

# Inside J-Link prompt:
> loadfile build_ra6m4_fsp/bin/bl2.hex
> loadfile build_ra6m4_fsp/bin/tfm_s.hex
> loadfile build_ra6m4_fsp/bin/tfm_ns.hex
> r
> go
> exit
```

### Option 2: Combined Hex File

```bash
cd build_ra6m4_fsp/bin
srec_cat bl2.hex -Intel tfm_s.hex -Intel tfm_ns.hex -Intel \
  -o tfm_combined.hex -Intel

# Flash tfm_combined.hex using Renesas Flash Programmer or J-Link
```

## Memory Layout

### Flash (1MB)

| Region | Address | Size | Content |
|--------|---------|------|---------|
| BL2 | 0x00000000 | 128KB | MCUboot bootloader |
| Secure | 0x00020000 | 384KB | TF-M secure services |
| Non-Secure | 0x00080000 | 512KB | Your FSP FreeRTOS app |

### RAM (256KB)

| Region | Address | Size | Content |
|--------|---------|------|---------|
| Secure | 0x20000000 | 128KB | TF-M secure RAM |
| Non-Secure | 0x20020000 | 128KB | FreeRTOS heap + stacks |

## Workflow: Modifying Your NS Application

### 1. Add New FSP Modules in e2studio

1. Open project in e2studio
2. Open RASC (configuration.xml)
3. Add new component (e.g., ADC, Timer, SPI)
4. Generate code
5. Create modular CMake file: `cmake/modules/fsp_<module>.cmake`
6. Add to `cmake/GeneratedSrc_Modular.cmake`

Example: Adding ADC

```cmake
# cmake/modules/fsp_adc.cmake
add_library(fsp_adc STATIC)
target_sources(fsp_adc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c)
target_link_libraries(fsp_adc PUBLIC fsp_bsp)
target_compile_options(fsp_adc PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
```

```cmake
# cmake/GeneratedSrc_Modular.cmake
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)

target_link_libraries(${PROJECT_NAME}.elf
    PRIVATE
        fsp_bsp
        fsp_freertos
        fsp_adc      # ← Add new module
)
```

### 2. Update TF-M Integration File

Edit [`tfm_integration/CMakeLists_tfm.cmake`](tfm_integration/CMakeLists_tfm.cmake) to include new module:

```cmake
# Include FSP module definitions
include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_bsp.cmake)
include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_freertos.cmake)
include(${FSP_NS_PROJECT_DIR}/cmake/modules/fsp_adc.cmake)  # ← Add this

# Link against FSP modules
target_link_libraries(tfm_ns
    PRIVATE
        fsp_bsp
        fsp_freertos
        fsp_adc      # ← Add this
        tfm_api_ns
        platform_ns
)
```

### 3. Rebuild TF-M

```bash
cd trusted-firmware-m
cmake --build build_ra6m4_fsp
```

## Testing TF-M Services

### Expected Test Results

When you run `run_all_tfm_tests()` in your FreeRTOS task:

```
Test Sequence:
1. tfm_ns_interface_init() → Initialize TF-M NS interface
2. test_tfm_attestation()   → Generate attestation token
3. test_tfm_storage()        → Write/read secure storage
4. test_tfm_crypto_random()  → Generate random data
5. test_tfm_crypto_hash()    → Verify SHA-256 with test vectors
6. test_tfm_huk_derivation() → Derive key from HUK

Return Values:
- 0: All tests passed
- -1: TF-M interface init failed
- -10 to -19: Attestation test failed
- -20 to -29: Storage test failed
- -30 to -39: Crypto random test failed
- -40 to -49: Crypto hash test failed
- -50 to -59: HUK derivation test failed
```

### Debug with UART

Connect UART0 (SCI0) at 115200 baud. Add logging to your FreeRTOS task:

```c
#include <stdio.h>

int result = run_all_tfm_tests();
if (result == 0) {
    printf("TF-M Tests: ALL PASSED\n");
} else {
    printf("TF-M Tests: FAILED (code: %d)\n", result);
}
```

### Debug with GDB

```bash
arm-none-eabi-gdb build_ra6m4_fsp/bin/tfm_ns.axf

(gdb) target remote localhost:2331
(gdb) load
(gdb) break test_tfm_attestation
(gdb) break test_tfm_storage
(gdb) continue
```

## Standalone FSP Build (Without TF-M)

You can still build this project standalone without TF-M:

```bash
cd FSP_Project_ra6m4_ns_rtos

# Configure (requires SmartBundle from secure project)
cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -G Ninja

# Build
cmake --build build
```

When built standalone, the TF-M test functions are stubbed out (return -1).

## Key Files

| File | Purpose |
|------|---------|
| [`src/tfm_service_tests.c`](src/tfm_service_tests.c) | TF-M service test implementation |
| [`src/tfm_service_tests.h`](src/tfm_service_tests.h) | Test function declarations |
| [`tfm_integration/CMakeLists_tfm.cmake`](tfm_integration/CMakeLists_tfm.cmake) | TF-M build adapter |
| [`cmake/GeneratedSrc_Modular.cmake`](cmake/GeneratedSrc_Modular.cmake) | Modular FSP build |
| [`cmake/modules/fsp_*.cmake`](cmake/modules/) | FSP module definitions |

## TrustZone Context Management

When building with TF-M, the secure side provides FreeRTOS TrustZone context management functions:

- `TZ_InitContextSystem_S` - Initialize secure context system
- `TZ_AllocModuleContext_S` - Allocate secure context for task
- `TZ_FreeModuleContext_S` - Free task secure context
- `TZ_LoadContext_S` - Load secure context on task switch
- `TZ_StoreContext_S` - Store secure context on task switch

These are automatically called by FreeRTOS when `configENABLE_TRUSTZONE=1` in FreeRTOSConfig.h.

When building standalone, these functions come from the secure project's SmartBundle (secure.o).

## Summary

✅ **Symmetric Workflow**: Just like secure projects, NS projects are created in e2studio
✅ **Modular FSP**: Add FSP modules easily via RASC + modular CMake
✅ **TF-M Integration**: Build with TF-M using external app configuration
✅ **TF-M Services**: Test PSA services from FreeRTOS tasks
✅ **Standalone Build**: Can build without TF-M for testing

**Next Steps**:
1. Add `tfm_service_tests.c` to your project's CMakeLists
2. Call `run_all_tfm_tests()` from your FreeRTOS task
3. Build with TF-M using the commands above
4. Flash and verify tests pass

---

For questions or issues, see:
- [TF-M RA6M4 Platform README](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\README.md)
- [TF-M Integration Complete Guide](C:\Users\Michael\Documents\GitHub\fsp_cmake\TFM_INTEGRATION_COMPLETE.md)
