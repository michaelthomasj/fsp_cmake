# Adding a New FSP Module (e.g., ADC)

This guide shows the exact commands and steps to add a new FSP module when generated from RASC.

## Example: Adding ADC Module

### Step 1: Generate Module in RASC

Open RASC and add the ADC module:

```bash
# Open RASC with your project
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

# Option 1: Open via CMake target
cmake --build build --target open_rasc_FSP_Project_ra6m4

# Option 2: Open directly
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
```

**In RASC GUI:**
1. Click "New Stack" → Select "ADC (r_adc)"
2. Configure ADC settings (channels, resolution, etc.)
3. Click "Generate Project Content"
4. Close RASC

**Generated Files:**
- `ra/fsp/src/r_adc/r_adc.c` (source)
- `ra/fsp/inc/instances/r_adc.h` (header)
- `ra_gen/hal_data.c` (updated with ADC instance)

---

### Step 2: Create Module CMake File

Create `cmake/modules/fsp_adc.cmake`:

```bash
cat > cmake/modules/fsp_adc.cmake << 'EOF'
# FSP ADC Module (Analog-to-Digital Converter)
# Provides ADC functionality

add_library(fsp_adc STATIC)

# ADC source files
target_sources(fsp_adc
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c
)

# ADC requires BSP
target_link_libraries(fsp_adc
    PUBLIC
        fsp_bsp
)

# ADC-specific compile options (inherit from BSP)
target_compile_options(fsp_adc
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
EOF
```

---

### Step 3: Include Module in Build System

Edit `cmake/GeneratedSrc_Modular.cmake` to include the new module:

```bash
# Add include line after existing modules
sed -i '/include.*fsp_flash.cmake/a include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)' \
    cmake/GeneratedSrc_Modular.cmake

# Add library to linker
sed -i '/fsp_flash.*# Flash module/a \        fsp_adc      # ADC module' \
    cmake/GeneratedSrc_Modular.cmake
```

**Or manually edit** `cmake/GeneratedSrc_Modular.cmake`:

```cmake
# Include FSP module definitions
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_bsp.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_uart.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_flash.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)  # ADD THIS LINE

# ...

# Link against FSP modules
target_link_libraries(${PROJECT_NAME}.elf
    PRIVATE
        fsp_bsp      # Board Support Package (always required)
        fsp_uart     # UART module
        fsp_flash    # Flash module
        fsp_adc      # ADC module  # ADD THIS LINE
)
```

---

### Step 4: Reconfigure and Build

```bash
# Set toolchain path
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"

# Navigate to project
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

# Clean build directory (optional but recommended)
rm -rf build

# Reconfigure CMake
cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Debug \
      -B build

# Build the project
cmake --build build
```

**Expected output:**
```
[1/37] Building C object CMakeFiles/fsp_bsp.dir/...
[2/37] Building C object CMakeFiles/fsp_uart.dir/...
[3/37] Building C object CMakeFiles/fsp_flash.dir/...
[4/37] Building C object CMakeFiles/fsp_adc.dir/ra/fsp/src/r_adc/r_adc.c.obj
[5/37] Linking C static library libfsp_adc.a
...
[37/37] Linking C executable FSP_Project_ra6m4.elf
```

---

### Step 5: Verify Build

```bash
# Check that ADC library was created
ls -lh build/libfsp_adc.a

# Check that it's linked into the executable
arm-none-eabi-nm build/FSP_Project_ra6m4.elf | grep -i "adc"

# Or check with objdump
arm-none-eabi-objdump -t build/FSP_Project_ra6m4.elf | grep -i r_adc
```

---

### Step 6: Use ADC in Your Code

Edit `src/hal_entry.c` or your application file:

```c
#include "hal_data.h"

void hal_entry(void)
{
    fsp_err_t err;

    /* Open ADC (g_adc0 defined in hal_data.c) */
    err = R_ADC_Open(&g_adc0_ctrl, &g_adc0_cfg);
    if (FSP_SUCCESS != err)
    {
        /* Handle error */
    }

    /* Start scan */
    err = R_ADC_ScanStart(&g_adc0_ctrl);

    /* Read ADC value */
    uint16_t adc_value;
    err = R_ADC_Read(&g_adc0_ctrl, ADC_CHANNEL_0, &adc_value);

    while (1)
    {
        /* Your application */
    }
}
```

---

## Complete Command Sequence Summary

Here's the complete sequence from start to finish:

```bash
# 1. Open RASC and add ADC module
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
# (Add ADC in GUI, generate, close)

# 2. Create module definition
cat > cmake/modules/fsp_adc.cmake << 'EOF'
add_library(fsp_adc STATIC)
target_sources(fsp_adc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c)
target_link_libraries(fsp_adc PUBLIC fsp_bsp)
target_compile_options(fsp_adc PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
    $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
)
EOF

# 3. Edit GeneratedSrc_Modular.cmake
# Manually add these two lines:
#   include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)
#   fsp_adc      # in target_link_libraries

# 4. Reconfigure and build
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build

# 5. Verify
ls -lh build/libfsp_adc.a
```

---

## Quick Reference: Common FSP Modules

| Module | RASC Name | Source File | Module CMake |
|--------|-----------|-------------|--------------|
| ADC | r_adc | `ra/fsp/src/r_adc/r_adc.c` | `fsp_adc.cmake` |
| Timer | r_gpt | `ra/fsp/src/r_gpt/r_gpt.c` | `fsp_gpt.cmake` |
| SPI | r_spi | `ra/fsp/src/r_spi/r_spi.c` | `fsp_spi.cmake` |
| I2C | r_iic_master | `ra/fsp/src/r_iic_master/r_iic_master.c` | `fsp_i2c.cmake` |
| CAN | r_canfd | `ra/fsp/src/r_canfd/r_canfd.c` | `fsp_can.cmake` |
| USB | r_usb_basic | `ra/fsp/src/r_usb_basic/r_usb_basic.c` | `fsp_usb.cmake` |
| Ethernet | r_ether | `ra/fsp/src/r_ether/r_ether.c` | `fsp_ether.cmake` |
| Crypto | r_sce | `ra/fsp/src/r_sce/r_sce.c` | `fsp_sce.cmake` |

---

## Template for Any Module

Copy and modify this template for any FSP module:

```bash
# Replace <MODULE> with your module name (e.g., adc, gpt, spi)
cat > cmake/modules/fsp_<MODULE>.cmake << 'EOF'
# FSP <MODULE> Module
add_library(fsp_<MODULE> STATIC)

target_sources(fsp_<MODULE>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_<MODULE>/r_<MODULE>.c
        # Add additional source files if needed
        # ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_<MODULE>/r_<MODULE>_helper.c
)

target_link_libraries(fsp_<MODULE>
    PUBLIC
        fsp_bsp
        # Add dependencies if module requires others
        # fsp_uart  # Example: if module needs UART
)

target_compile_options(fsp_<MODULE>
    PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
        $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
        $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
        $<$<CONFIG:MinSizeRel>:${RASC_MIN_SIZE_RELEASE_FLAGS}>
        $<$<CONFIG:RelWithDebInfo>:${RASC_RELEASE_WITH_DEBUG_INFO}>
)
EOF
```

---

## Troubleshooting

### Build Error: Source file not found

```
CMake Error: Cannot find source file: ra/fsp/src/r_adc/r_adc.c
```

**Solution:**
- Verify RASC generated the module (check `ra/fsp/src/r_adc/` exists)
- Re-run RASC generation
- Check module name matches (case-sensitive)

### Link Error: Undefined reference

```
undefined reference to `R_ADC_Open'
```

**Solution:**
- Ensure module is added to `target_link_libraries` in `GeneratedSrc_Modular.cmake`
- Rebuild: `cmake --build build --clean-first`

### Module not building

**Solution:**
```bash
# Force reconfigure
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -B build
cmake --build build
```

---

## Incremental Build

After adding a module, subsequent changes only rebuild affected files:

```bash
# Make changes to your app code
vim src/hal_entry.c

# Quick rebuild (only changed files)
cmake --build build

# Build specific module
cmake --build build --target fsp_adc

# Clean and rebuild everything
cmake --build build --clean-first
```

---

## Multi-Module Example: Adding ADC + Timer

```bash
# 1. Add both in RASC (ADC + GPT Timer)

# 2. Create both module files
cat > cmake/modules/fsp_adc.cmake << 'EOF'
add_library(fsp_adc STATIC)
target_sources(fsp_adc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c)
target_link_libraries(fsp_adc PUBLIC fsp_bsp)
target_compile_options(fsp_adc PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF

cat > cmake/modules/fsp_gpt.cmake << 'EOF'
add_library(fsp_gpt STATIC)
target_sources(fsp_gpt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_gpt/r_gpt.c)
target_link_libraries(fsp_gpt PUBLIC fsp_bsp)
target_compile_options(fsp_gpt PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF

# 3. Edit GeneratedSrc_Modular.cmake to add:
#    include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)
#    include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_gpt.cmake)
#    And in target_link_libraries: fsp_adc, fsp_gpt

# 4. Build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -B build
cmake --build build
```

---

## Done!

Your new module is now integrated and ready to use in your application.