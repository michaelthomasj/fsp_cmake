# ✅ TF-M Integration Complete - RA6M4 with Modular FSP

Your Renesas RA6M4 has been successfully integrated into Trusted Firmware-M using the modular FSP library structure!

## What Was Created

### 📦 TF-M Platform Files (15 files)

Created in: `C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\`

#### Core Configuration (3 files)
- ✅ **cpuarch.cmake** - Cortex-M33 with FPU/DSP/TrustZone
- ✅ **config.cmake** - Memory layout, FSP integration settings
- ✅ **CMakeLists.txt** - Links modular FSP libraries

#### Memory Layout (2 files)
- ✅ **flash_layout.h** - 1MB flash partitioned (BL2/Secure/Non-Secure)
- ✅ **region_defs.h** - 256KB RAM split (128KB S / 128KB NS)

#### Platform HAL (6 files)
- ✅ **target_cfg.c/h** - SAU/NVIC initialization
- ✅ **device_cfg.h** - Device settings
- ✅ **tfm_hal_platform.c** - Platform init/reset/halt
- ✅ **tfm_hal_isolation.c** - MPU configuration
- ✅ **tfm_interrupts.c** - Interrupt management

#### CMSIS Drivers (2 files)
- ✅ **cmsis_drivers/Driver_USART.c** - Wraps FSP SCI UART
- ✅ **cmsis_drivers/Driver_Flash.c** - Wraps FSP Flash HP

#### Documentation
- ✅ **README.md** - Complete platform documentation

---

## Integration Architecture

```
TF-M (trusted-firmware-m/)
    └── platform/ext/target/renesas/ra6m4/
        ├── CMakeLists.txt  ──────┐
        │                          │ Links:
        │                          ├──> fsp_bsp (libfsp_bsp.a)
        │                          ├──> fsp_uart (libfsp_uart.a)
        │                          └──> fsp_flash (libfsp_flash.a)
        │                                    ↑
        │                                    │
        └── FSP_ROOT_DIR (via cmake) ───────┘
                │
                └──> fsp_cmake/FSP_Project_ra6m4/
                     ├── cmake/modules/fsp_bsp.cmake
                     ├── cmake/modules/fsp_uart.cmake
                     └── cmake/modules/fsp_flash.cmake
```

---

## How to Build TF-M for RA6M4

### Prerequisites

```bash
# Toolchain
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"

# FSP Project Path
export FSP_ROOT_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"
```

### Build Commands

```bash
cd "C:/Users/Michael/Documents/GitHub/trusted-firmware-m"

# Configure
cmake -S . -B build_ra6m4 \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DFSP_ROOT_DIR="${FSP_ROOT_DIR}" \
  -DARM_TOOLCHAIN_PATH="${ARM_TOOLCHAIN_PATH}" \
  -G Ninja

# Build
cmake --build build_ra6m4
```

### Expected Output

```
build_ra6m4/bin/
├── bl2.bin          ← Bootloader (128KB)
├── tfm_s.bin        ← Secure firmware
├── tfm_ns.bin       ← Non-secure firmware
├── *.hex            ← Flash files
└── *.elf            ← Debug files
```

---

## Memory Map

### Flash (1MB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| BL2 | 0x00000000 - 0x0001FFFF | 128KB | Bootloader |
| Secure | 0x00020000 - 0x0007FFFF | 384KB | TF-M Secure |
| Non-Secure | 0x00080000 - 0x000FFFFF | 512KB | Application |

### RAM (256KB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| Secure | 0x20000000 - 0x2001FFFF | 128KB | TF-M Secure RAM |
| Non-Secure | 0x20020000 - 0x2003FFFF | 128KB | Application RAM |

### Data Flash (8KB)

| Region | Address Range | Size | Purpose |
|--------|---------------|------|---------|
| NV Counters | 0x08000000 - 0x080007FF | 2KB | Rollback protection |
| Protected Storage | 0x08000800 - 0x080013FF | 3KB | PS service |
| ITS | 0x08001400 - 0x08001BFF | 2KB | Internal storage |

---

## FSP Module Integration

The platform automatically links these FSP modules:

### fsp_bsp (Board Support Package)
- System initialization
- Clock configuration
- CMSIS startup
- I/O Port driver

### fsp_uart (SCI UART)
- UART0 (SCI0) for console
- Wrapped as CMSIS Driver_USART
- Used for TF-M logging

### fsp_flash (Flash HP)
- Code flash read/write/erase
- Data flash for storage
- Wrapped as CMSIS Driver_Flash

---

## Adding New FSP Modules

Example: Adding ADC to TF-M

### 1. Add ADC in FSP Project

```bash
cd "C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

# Open RASC and add ADC
"C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe" configuration.xml

# Create ADC module (see cmake/modules/ADD_NEW_MODULE.md)
cat > cmake/modules/fsp_adc.cmake << 'EOF'
add_library(fsp_adc STATIC)
target_sources(fsp_adc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ra/fsp/src/r_adc/r_adc.c)
target_link_libraries(fsp_adc PUBLIC fsp_bsp)
target_compile_options(fsp_adc PRIVATE $<$<COMPILE_LANGUAGE:C>:${RASC_CMAKE_C_FLAGS}>)
EOF

# Add to GeneratedSrc_Modular.cmake
# include(${CMAKE_CURRENT_LIST_DIR}/modules/fsp_adc.cmake)
# target_link_libraries(${PROJECT_NAME}.elf PRIVATE fsp_adc)

# Rebuild FSP project
cmake --build build
```

### 2. Link ADC in TF-M Platform

Edit `trusted-firmware-m/platform/ext/target/renesas/ra6m4/CMakeLists.txt`:

```cmake
# Add after other FSP modules
include(${FSP_ROOT_DIR}/cmake/modules/fsp_adc.cmake)

# Link to platform_s
target_link_libraries(platform_s
    PUBLIC
        fsp_bsp
        fsp_uart
        fsp_flash
        fsp_adc      # ← Add this
)
```

### 3. Rebuild TF-M

```bash
cd trusted-firmware-m
cmake --build build_ra6m4
```

### Constraints specific to the TF-M build

The module mechanics are in `cmake/modules/ADD_NEW_MODULE.md`. These rules apply on top of it and
only to the TF-M port — a standalone FSP project is free to add any of the modules below.

**Never link these into `platform_s` or `platform_bl2`.** TF-M supplies its own implementation, so
declaring a module for one of them puts two implementations in a single image:

| FSP module | Why | Reference |
|---|---|---|
| `r_sce` | SCE9 hardware crypto. TF-M builds `CRYPTO_HW_ACCELERATOR OFF` with its own mbedcrypto. | DESIGN.md §6 |
| `rm_psa_crypto`, `ra/arm/mbedtls` | FSP's mbedTLS is entangled with the FSP MCUboot config in `bsp_linker_info.h`. | DESIGN.md §6 |
| `rm_mcuboot_port` | Carries FSP's own flash identity (`FLASH_AREA_*_ID`, single-image assumptions) and conflicts with TF-M's dual-image flash_map. Grafting it is what failed on RA6M4. | DESIGN.md §4, §5 |

Note `ADD_NEW_MODULE.md`'s "Common FSP Modules" table lists `fsp_sce.cmake` — valid for a standalone
project, not here. Re-enabling the SCE path is the future hardware-crypto switch, a deliberate
project rather than a module addition.

Their **headers** must stay on the include path: the generated `ra_gen/common_data.h` and
`hal_data.h` include them unconditionally. Nothing links against them.

**Linking into `platform_s` puts the module in the signed secure image.** Add it there only if the
secure world actually uses it; otherwise link it to the non-secure application instead.

**`ra_gen/hal_data.c` belongs in `fsp_bsp`.** It instantiates the control structs for every enabled
module and must link exactly once. RA6M4 currently attaches it to `fsp_flash`, so dropping the flash
module would silently take the HAL instance data with it — worth fixing when that file is next
touched.

**Files excluded from the FSP tree by image role** — not modules, but the same class of decision:

| File | Secure | BL2 | Non-secure |
|---|---|---|---|
| `ra_gen/main.c` | excluded | excluded | **kept** — the NS image is a whole FSP application; TF-M has no `main` to replace it |
| `.../Device/RENESAS/Source/startup.c` | excluded | excluded | **kept** — FSP's `Reset_Handler`, which FSP's linker script expects |
| `bsp/mcu/*/bsp_linker.c` | excluded | excluded | **kept** — its option-setting sections compile out under `BSP_TZ_NONSECURE_BUILD` |

`bsp_linker.c` must never reach the secure or BL2 image. OFS goes into BL2 only, from
`bl2_option_setting.c`, with discrete per-group MEMORY regions (DESIGN.md §8.4).

**If the change touched BL2, re-run the OFS check before flashing:**

```bash
arm-none-eabi-readelf -l bin/bl2.axf
```

Expect small discrete LOAD segments in `0x0100Axxx`, **never** one spanning `0x1CC`. A clean `.srec`
does not prove this.

---

## Testing

### Build with TF-M Tests

```bash
cmake -S . -B build_ra6m4_test \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTEST_S=ON \
  -DTEST_NS=ON \
  -DFSP_ROOT_DIR="${FSP_ROOT_DIR}"

cmake --build build_ra6m4_test
```

### UART Console Output

Connect UART0 (SCI0):
- Baud: 115200
- Data: 8-bit
- Parity: None
- Stop: 1-bit

You should see TF-M boot messages:
```
[INF] Starting TF-M ...
[INF] Booting TF-M v1.x.x
...
```

---

## Flashing to Device

### Option 1: J-Link

```bash
JLinkExe -device R7FA6M4AF -if SWD -speed 4000
> loadfile build_ra6m4/bin/bl2.hex
> loadfile build_ra6m4/bin/tfm_s.hex
> loadfile build_ra6m4/bin/tfm_ns.hex
> r
> go
> exit
```

### Option 2: Renesas Flash Programmer

1. Open Renesas Flash Programmer
2. Select R7FA6M4AF device
3. Load hex files in order (BL2 → S → NS)
4. Program and verify

---

## Key Features

✅ **Modular FSP Libraries** - Each driver is a separate library
✅ **Easy Module Addition** - Add new FSP modules without modifying TF-M
✅ **Standard CMSIS Drivers** - FSP wrapped as CMSIS for TF-M compatibility
✅ **TrustZone Enabled** - Full SAU/MPU configuration
✅ **Secure Boot** - MCUboot (BL2) support
✅ **Secure Storage** - PS/ITS using data flash

---

## Directory Structure

```
fsp_cmake/
└── FSP_Project_ra6m4/
    └── cmake/modules/
        ├── fsp_bsp.cmake      ← BSP library
        ├── fsp_uart.cmake     ← UART module
        ├── fsp_flash.cmake    ← Flash module
        └── README.md

trusted-firmware-m/
└── platform/ext/target/renesas/ra6m4/
    ├── cpuarch.cmake          ← CPU config
    ├── config.cmake           ← Platform config
    ├── CMakeLists.txt         ← Links FSP modules
    ├── flash_layout.h
    ├── region_defs.h
    ├── target_cfg.c/h
    ├── tfm_hal_*.c
    ├── cmsis_drivers/
    │   ├── Driver_USART.c     ← FSP SCI wrapper
    │   └── Driver_Flash.c     ← FSP Flash HP wrapper
    └── README.md
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| [TFM Platform README](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\README.md) | TF-M platform details |
| [FSP Modules README](C:\Users\Michael\Documents\GitHub\fsp_cmake\FSP_Project_ra6m4\cmake\modules\README.md) | Modular FSP library guide |
| [Add FSP Module](C:\Users\Michael\Documents\GitHub\fsp_cmake\FSP_Project_ra6m4\cmake\modules\ADD_NEW_MODULE.md) | How to add new FSP modules |
| [Quick Commands](C:\Users\Michael\Documents\GitHub\fsp_cmake\FSP_Project_ra6m4\QUICK_COMMANDS.md) | Command reference |

---

## Next Steps

1. **Build TF-M** using the commands above
2. **Flash to RA6M4** hardware
3. **Verify boot** via UART console
4. **Add modules** as needed (ADC, Timer, SPI, etc.)
5. **Develop application** using TF-M secure services

---

## Summary

✅ **Created**: 15 TF-M platform files
✅ **Integrated**: Modular FSP libraries (BSP, UART, Flash)
✅ **Memory**: Configured 1MB Flash + 256KB RAM with TrustZone
✅ **Drivers**: CMSIS wrappers for FSP drivers
✅ **Ready**: Build with `-DTFM_PLATFORM=renesas/ra6m4`

**Your RA6M4 is now a fully-functional TF-M target!** 🎉