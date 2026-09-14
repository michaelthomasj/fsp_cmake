# Quick Command Reference - Secure Project (TrustZone)

## Build Commands

### Initial Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_s"

cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Debug \
      -B build

cmake --build build
```

### Rebuild After Code Changes

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_s/build"
cmake --build .
```

### Clean Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_s"
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

### Release Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -B build_release

cmake --build build_release
```

---

## TrustZone Specific

### Generate SmartBundle (.sbd)

The SmartBundle file is automatically generated post-build and contains:
- Secure project API information
- NSC (Non-Secure Callable) function definitions
- Configuration for non-secure projects

```bash
ls -lh build/*.sbd
```

### Extract SmartBundle in Non-Secure Project

When building a non-secure project that uses this secure project:

1. Copy the `.sbd` file to the non-secure project
2. RASC will automatically extract NSC APIs

---

## Adding New Module (e.g., ADC)

### 1. Generate in RASC

```bash
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
# Add module → Generate → Close
```

### 2. Create Module File

```bash
cat > cmake/modules/fsp_adc.cmake << 'EOF'
# FSP ADC Module Library
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined. Include fsp_bsp.cmake first.")
endif()

add_library(fsp_adc STATIC)

target_sources(fsp_adc PRIVATE
    ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_adc/r_adc.c
)

target_link_libraries(fsp_adc PUBLIC fsp_bsp)

target_compile_options(fsp_adc PRIVATE
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
# After other includes (around line 7):
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)

# In target_link_libraries (around line 30):
        fsp_adc      # ADC module
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
cmake --build build --target fsp_uart
cmake --build build --target fsp_flash
cmake --build build --target fsp_adc
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
libfsp_bsp.a      # BSP (core) - 451 KB
libfsp_uart.a     # UART - 114 KB
libfsp_flash.a    # Flash - 106 KB
libfsp_adc.a      # ADC (if added)
```

---

## Verification Commands

### Check Binary Size

```bash
arm-none-eabi-size build/FSP_Project_ra6m4_s.elf
```

### Check Linked Modules

```bash
arm-none-eabi-nm build/FSP_Project_ra6m4_s.elf | grep -i "R_UART"
arm-none-eabi-nm build/FSP_Project_ra6m4_s.elf | grep -i "R_FLASH"
arm-none-eabi-nm build/FSP_Project_ra6m4_s.elf | grep -i "R_ADC"
```

### Check SmartBundle Generated

```bash
ls -lh build/*.sbd
```

### View Map File

```bash
cat build/FSP_Project_ra6m4_s.map | less
```

---

## Common Module Templates

### Timer (GPT)

```bash
cat > cmake/modules/fsp_gpt.cmake << 'EOF'
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined.")
endif()

add_library(fsp_gpt STATIC)
target_sources(fsp_gpt PRIVATE ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_gpt/r_gpt.c)
target_link_libraries(fsp_gpt PUBLIC fsp_bsp)
target_compile_options(fsp_gpt PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF
```

### SPI

```bash
cat > cmake/modules/fsp_spi.cmake << 'EOF'
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined.")
endif()

add_library(fsp_spi STATIC)
target_sources(fsp_spi PRIVATE ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_spi/r_spi.c)
target_link_libraries(fsp_spi PUBLIC fsp_bsp)
target_compile_options(fsp_spi PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF
```

### I2C

```bash
cat > cmake/modules/fsp_i2c.cmake << 'EOF'
if(NOT DEFINED FSP_MODULE_BASE_DIR)
    message(FATAL_ERROR "FSP_MODULE_BASE_DIR not defined.")
endif()

add_library(fsp_i2c STATIC)
target_sources(fsp_i2c PRIVATE ${FSP_MODULE_BASE_DIR}/ra/fsp/src/r_iic_master/r_iic_master.c)
target_link_libraries(fsp_i2c PUBLIC fsp_bsp)
target_compile_options(fsp_i2c PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF
```

---

## Troubleshooting

### "Source file not found"

```bash
# Verify RASC generated the file
ls ra/fsp/src/r_<module>/

# Re-generate in RASC
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml
```

### "Undefined reference"

```bash
# Ensure module is linked
grep -n "fsp_<module>" cmake/GeneratedSrc_Modular.cmake

# Clean rebuild
rm -rf build && cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -B build && cmake --build build
```

### "Ninja not found"

```bash
# Install Ninja
choco install ninja

# Or check if installed
which ninja
```

### "ARM_TOOLCHAIN_PATH not defined"

```bash
# Set environment variable
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"

# Or add to ~/.bashrc for persistence
echo 'export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"' >> ~/.bashrc
```

---

## File Locations

| File | Purpose |
|------|---------|
| `cmake/modules/fsp_*.cmake` | Module definitions |
| `cmake/GeneratedSrc_Modular.cmake` | Modular build system |
| `build/libfsp_*.a` | Compiled module libraries |
| `build/FSP_Project_ra6m4_s.elf` | Final secure executable |
| `build/FSP_Project_ra6m4_s.srec` | S-record for flashing |
| `build/FSP_Project_ra6m4_s.sbd` | SmartBundle for non-secure project |
| `UserNscApiFiles.txt` | List of NSC API headers to export |

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
cmake --build build && arm-none-eabi-size build/FSP_Project_ra6m4_s.elf

# List libraries
ls -lh build/libfsp_*.a
```

---

## Documentation

- [Module README](cmake/modules/README.md) - Detailed module documentation
- [Add New Module Guide](cmake/modules/ADD_NEW_MODULE.md) - Step-by-step guide for adding modules
- [TrustZone Guide](https://renesas.github.io/fsp/group___r_e_n_e_s_a_s___t_z___s_e_c_u_r_e.html) - Official Renesas TrustZone documentation

---

## Next Steps

After building the secure project:

1. **Create Non-Secure Project** - Generate a non-secure project in RASC
2. **Import SmartBundle** - Copy `build/FSP_Project_ra6m4_s.sbd` to non-secure project
3. **Call NSC Functions** - Non-secure code can call secure functions defined in `UserNscApiFiles.txt`
4. **Link Both Projects** - Final image combines secure + non-secure binaries
