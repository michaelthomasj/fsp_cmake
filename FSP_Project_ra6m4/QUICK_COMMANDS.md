# Quick Command Reference

## Build Commands

### Initial Build

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Debug \
      -B build

cmake --build build
```

### Rebuild After Code Changes

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4/build"
cmake --build .
```

### Clean Build

```bash
rm -rf build
cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build
cmake --build build
```

### Release Build

```bash
cmake -G "Ninja" \
      -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -B build_release

cmake --build build_release
```

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
add_library(fsp_adc STATIC)
target_sources(fsp_adc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c)
target_link_libraries(fsp_adc PUBLIC fsp_bsp)
target_compile_options(fsp_adc PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>
    $<$<CONFIG:Debug>:${RASC_DEBUG_FLAGS}>
    $<$<CONFIG:Release>:${RASC_RELEASE_FLAGS}>
)
EOF
```

### 3. Edit `cmake/GeneratedSrc_Modular.cmake`

Add these lines:

```cmake
# After other includes:
include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)

# In target_link_libraries:
    fsp_adc      # ADC module
```

### 4. Build

```bash
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

### Check Module Created

```bash
ls -lh build/libfsp_*.a
```

**Expected:**
```
libfsp_bsp.a      # BSP (core)
libfsp_uart.a     # UART
libfsp_flash.a    # Flash
libfsp_adc.a      # ADC (if added)
```

---

## Verification Commands

### Check Binary Size

```bash
arm-none-eabi-size build/FSP_Project_ra6m4.elf
```

### Check Linked Modules

```bash
arm-none-eabi-nm build/FSP_Project_ra6m4.elf | grep -i "R_UART"
arm-none-eabi-nm build/FSP_Project_ra6m4.elf | grep -i "R_FLASH"
arm-none-eabi-nm build/FSP_Project_ra6m4.elf | grep -i "R_ADC"
```

### View Map File

```bash
cat build/FSP_Project_ra6m4.map | less
```

---

## Common Module Templates

### Timer (GPT)

```bash
cat > cmake/modules/fsp_gpt.cmake << 'EOF'
add_library(fsp_gpt STATIC)
target_sources(fsp_gpt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_gpt/r_gpt.c)
target_link_libraries(fsp_gpt PUBLIC fsp_bsp)
target_compile_options(fsp_gpt PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF
```

### SPI

```bash
cat > cmake/modules/fsp_spi.cmake << 'EOF'
add_library(fsp_spi STATIC)
target_sources(fsp_spi PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_spi/r_spi.c)
target_link_libraries(fsp_spi PUBLIC fsp_bsp)
target_compile_options(fsp_spi PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF
```

### I2C

```bash
cat > cmake/modules/fsp_i2c.cmake << 'EOF'
add_library(fsp_i2c STATIC)
target_sources(fsp_i2c PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_iic_master/r_iic_master.c)
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

---

## File Locations

| File | Purpose |
|------|---------|
| `cmake/modules/fsp_*.cmake` | Module definitions |
| `cmake/GeneratedSrc_Modular.cmake` | Modular build system |
| `build/libfsp_*.a` | Compiled module libraries |
| `build/FSP_Project_ra6m4.elf` | Final executable |
| `build/FSP_Project_ra6m4.srec` | S-record for flashing |

---

## One-Liner Shortcuts

```bash
# Full rebuild
rm -rf build && cmake -G "Ninja" -DCMAKE_TOOLCHAIN_FILE=cmake/gcc.cmake -DCMAKE_BUILD_TYPE=Debug -B build && cmake --build build

# Quick incremental build
cmake --build build

# Build and check size
cmake --build build && arm-none-eabi-size build/FSP_Project_ra6m4.elf

# List libraries
ls -lh build/libfsp_*.a
```

---

## Documentation

- [Module README](cmake/modules/README.md) - Detailed module documentation
- [Add New Module Guide](cmake/modules/ADD_NEW_MODULE.md) - Step-by-step guide for adding modules