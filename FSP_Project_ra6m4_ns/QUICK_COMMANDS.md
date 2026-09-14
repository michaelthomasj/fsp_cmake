# Quick Command Reference - Non-Secure Project (TrustZone + FreeRTOS)

**IMPORTANT**: This non-secure project uses FreeRTOS which requires TrustZone context management functions from the secure project. The current secure project (`FSP_Project_ra6m4_s`) does NOT provide these functions, causing linker errors.

**Status**: Build fails with undefined references to:
- `TZ_StoreContext_S`
- `TZ_LoadContext_S`
- `TZ_AllocModuleContext_S`
- `TZ_InitContextSystem_S`
- `TZ_FreeModuleContext_S`

**Solution**: See [../TRUSTZONE_FREERTOS_REQUIREMENTS.md](../TRUSTZONE_FREERTOS_REQUIREMENTS.md) for detailed explanation and implementation options.

## Build Commands

### Initial Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns"

cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Debug \
      -B build

cmake --build build
```

### Rebuild After Code Changes

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns/build"
cmake --build .
```

### Clean Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns"
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

---

## TrustZone Integration

### Import Secure Project SmartBundle

1. Build the secure project first:
```bash
cd ../FSP_Project_ra6m4_s
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cmake --build build
```

2. Copy the SmartBundle to non-secure project:
```bash
cp FSP_Project_ra6m4_s/build/FSP_Project_ra6m4_s.sbd \
   FSP_Project_ra6m4_ns/
```

3. Extract secure.o using RASC (or manually):
```bash
# RASC will automatically extract secure.o from the .sbd file
# Or manually with RASC command:
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" \
    -nosplash --launcher.suppressErrors \
    --extractsmartbundle FSP_Project_ra6m4_s.sbd
```

4. Rebuild non-secure project:
```bash
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -B build
cmake --build build
```

### Call Secure Functions from Non-Secure

Non-secure code can call secure functions via NSC (Non-Secure Callable) veneers:

```c
// In non-secure code
#include "secure_api.h"  // From SmartBundle

void non_secure_function(void) {
    // Call secure function
    secure_function_name();
}
```

---

## FreeRTOS Specific

### Adding New Task/Thread

1. Use RASC to add a new thread
2. RASC will generate `ra_gen/new_thread<N>.c`
3. Rebuild - the thread is automatically included

### Thread Configuration

Edit `ra_cfg/aws/FreeRTOSConfig.h` to configure:
- Heap size: `configTOTAL_HEAP_SIZE`
- Task priorities
- Stack sizes
- Tick rate

### Common FreeRTOS APIs

```c
// In your thread
void new_thread0_entry(void *pvParameters) {
    while(1) {
        // Your code here
        vTaskDelay(pdMS_TO_TICKS(1000)); // 1 second delay
    }
}
```

---

## Adding New Module (e.g., Timer/GPT)

### 1. Generate in RASC

```bash
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
# Add module → Generate → Close
```

### 2. Create Module File

```bash
cat > cmake/modules/fsp_gpt.cmake << 'EOF'
# FSP GPT (Timer) Module Library
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined.")
endif()

add_library(fsp_gpt STATIC)

target_sources(fsp_gpt PRIVATE
    ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_gpt/r_gpt.c
)

target_link_libraries(fsp_gpt PUBLIC fsp_bsp)

target_compile_options(fsp_gpt PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
    $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
    $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
    $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
EOF
```

### 3. Edit `cmake/GeneratedSrc_Modular.cmake`

Add these lines:

```cmake
# After other includes (around line 8):
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_gpt.cmake)

# In target_link_libraries (around line 35):
        fsp_gpt      # Timer/GPT module
```

### 4. Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

---

## Module Management

### Build Specific Module

```bash
cmake --build build --target fsp_adc
cmake --build build --target fsp_icu
cmake --build build --target fsp_freertos
```

### List All Targets

```bash
cmake --build build --target help
```

### Check Modules Created

```bash
ls -lh build/libfsp_*.a
```

**Expected:**
```
libfsp_bsp.a        # BSP (core)
libfsp_adc.a        # ADC
libfsp_icu.a        # External IRQ
libfsp_freertos.a   # FreeRTOS RTOS
```

---

## Interrupt Handling

### External IRQ (ICU) Usage

The ICU module handles external interrupts. Example:

```c
// In your code
#include "hal_data.h"

void external_irq_callback(external_irq_callback_args_t *p_args) {
    // Handle interrupt
    if (p_args->channel == 0) {
        // IRQ0 triggered
    }
}

void init_interrupts(void) {
    fsp_err_t err;
    err = R_ICU_ExternalIrqOpen(&g_external_irq0_ctrl, &g_external_irq0_cfg);
    err = R_ICU_ExternalIrqEnable(&g_external_irq0_ctrl);
}
```

### FreeRTOS Interrupt Priorities

Ensure interrupt priorities are configured correctly:
- FreeRTOS kernel interrupts: Priority 1-3
- Application interrupts: Priority 4-15

Configure in RASC or `vector_data.c`.

---

## Verification Commands

### Check Binary Size

```bash
arm-none-eabi-size build/FSP_Project_ra6m4_ns.elf
```

### Check Linked Modules

```bash
arm-none-eabi-nm build/FSP_Project_ra6m4_ns.elf | grep -i "R_ADC"
arm-none-eabi-nm build/FSP_Project_ra6m4_ns.elf | grep -i "vTaskDelay"
arm-none-eabi-nm build/FSP_Project_ra6m4_ns.elf | grep -i "R_ICU"
```

### Check FreeRTOS Linked

```bash
arm-none-eabi-nm build/FSP_Project_ra6m4_ns.elf | grep -E "xTaskCreate|vTaskDelay|xQueueCreate"
```

### View Map File

```bash
cat build/FSP_Project_ra6m4_ns.map | less
```

---

## Troubleshooting

### "undefined reference to secure function"

```bash
# Ensure secure.o is present
ls -lh secure.o

# Re-extract from SmartBundle
cp ../FSP_Project_ra6m4_s/build/*.sbd .
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" \
    --extractsmartbundle *.sbd
```

### "FreeRTOS tasks not running"

```bash
# Check if FreeRTOS module is linked
grep "fsp_freertos" cmake/GeneratedSrc_Modular.cmake

# Verify heap size in FreeRTOSConfig.h
grep "configTOTAL_HEAP_SIZE" ra_cfg/aws/FreeRTOSConfig.h

# Ensure vTaskStartScheduler() is called in main.c
grep "vTaskStartScheduler" ra_gen/main.c
```

### "Interrupt not firing"

```bash
# Verify ICU module is linked
grep "fsp_icu" cmake/GeneratedSrc_Modular.cmake

# Check interrupt priority
grep "IRQ" ra_gen/vector_data.c

# Ensure interrupt is enabled in RASC
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
```

---

## File Locations

| File | Purpose |
|------|---------|
| `cmake/modules/fsp_*.cmake` | Module definitions |
| `cmake/GeneratedSrc_Modular.cmake` | Modular build system |
| `build/libfsp_*.a` | Compiled module libraries |
| `build/FSP_Project_ra6m4_ns.elf` | Final non-secure executable |
| `build/FSP_Project_ra6m4_ns.srec` | S-record for flashing |
| `secure.o` | Secure project interface (from SmartBundle) |
| `ra_gen/new_thread0.c` | FreeRTOS thread entry point |
| `ra_cfg/aws/FreeRTOSConfig.h` | FreeRTOS configuration |

---

## One-Liner Shortcuts

```bash
# Set toolchain (add to all commands)
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"

# Full rebuild
rm -rf build && cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build && cmake --build build

# Quick incremental build
cmake --build build

# Build and check size
cmake --build build && arm-none-eabi-size build/FSP_Project_ra6m4_ns.elf

# List libraries
ls -lh build/libfsp_*.a
```

---

## Documentation

- [Module README](cmake/modules/README.md) - Detailed module documentation
- [Add New Module Guide](cmake/modules/ADD_NEW_MODULE.md) - Step-by-step guide for adding modules
- [FreeRTOS Documentation](https://www.freertos.org/Documentation/RTOS_book.html) - Official FreeRTOS guide
- [TrustZone Guide](https://renesas.github.io/fsp/group___r_e_n_e_s_a_s___t_z___s_e_c_u_r_e.html) - Renesas TrustZone documentation

---

## Complete TrustZone Build Flow

### 1. Build Secure Project
```bash
cd FSP_Project_ra6m4_s
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

### 2. Copy SmartBundle
```bash
cp build/FSP_Project_ra6m4_s.sbd ../FSP_Project_ra6m4_ns/
```

### 3. Build Non-Secure Project
```bash
cd ../FSP_Project_ra6m4_ns
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

### 4. Flash Combined Image
```bash
# Use Renesas Flash Programmer or J-Link to flash both:
# 1. FSP_Project_ra6m4_s.srec (secure)
# 2. FSP_Project_ra6m4_ns.srec (non-secure)
```
