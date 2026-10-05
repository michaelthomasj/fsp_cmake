# TF-M Non-Secure FreeRTOS Test Application - Build Guide

This guide shows how to build and test the TF-M RA6M4 integration with a FreeRTOS-based non-secure application that tests all TF-M services.

## What Was Added

### Non-Secure Application Files

Created in: `C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\`

#### Source Files (2 files)
- **src/main_ns.c** - Non-secure entry point with FreeRTOS initialization
- **src/tfm_test_thread.c** - TF-M service test thread

#### Header Files (2 files)
- **include/FreeRTOSConfig.h** - FreeRTOS configuration for TrustZone
- **include/tfm_test_thread.h** - Test thread declaration

#### Build Configuration
- **CMakeLists.txt** - Links FreeRTOS kernel and TF-M APIs

---

## TF-M Services Tested

The test application validates all major TF-M services:

### 1. Initial Attestation Service
```c
psa_initial_attest_get_token_size(32, &size);
psa_initial_attest_get_token(challenge, 32, token_buf, token_buf_size, &token_size);
```
- Gets attestation token size
- Generates attestation token with challenge

### 2. Internal Trusted Storage (ITS)
```c
psa_its_set(uid, data_length, &data1[0], flags);
psa_its_get(uid, 0, data_length, read_buf, &read_length);
```
- Writes data to secure storage
- Reads data back and verifies

### 3. Crypto Service - Random Generation
```c
psa_generate_random(random_data, data_length);
```
- Generates cryptographically secure random numbers

### 4. Crypto Service - SHA-256 Hash
```c
psa_hash_setup(&operation, PSA_ALG_SHA_256);
psa_hash_update(&operation, input, sizeof(input));
psa_hash_verify(&operation, expected_hash, expected_hash_len);
```
- Tests SHA-256 with known test vectors:
  - "abc" → ba7816bf8f01cfea...
  - "abcdddddddd" → 7bd340d029f761d7...

### 5. HUK (Hardware Unique Key) Derivation
```c
psa_key_derivation_setup(&operation, PSA_ALG_HKDF(PSA_ALG_SHA_256));
psa_key_derivation_input_key(&operation, PSA_KEY_DERIVATION_INPUT_SECRET,
                              TFM_BUILTIN_KEY_ID_HUK);
psa_key_derivation_input_bytes(&operation, PSA_KEY_DERIVATION_INPUT_INFO,
                                label, sizeof(label));
psa_key_derivation_output_key(&attributes, &operation, &handle);
psa_export_key(handle, exported_key, sizeof(exported_key), &length);
```
- Derives a 256-bit key from the HUK
- Exports derived key for verification

---

## Prerequisites

### 1. Environment Variables

```bash
# Toolchain
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"

# FSP Project Path (for platform drivers)
export FSP_ROOT_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

# FreeRTOS Kernel (TF-M should include this in lib/ext/freertos)
export FREERTOS_DIR="C:/Users/Michael/Documents/GitHub/trusted-firmware-m/lib/ext/freertos"
```

### 2. FreeRTOS Kernel Setup

TF-M includes FreeRTOS as a submodule. Ensure it's checked out:

```bash
cd "C:/Users/Michael/Documents/GitHub/trusted-firmware-m"
git submodule update --init lib/ext/freertos
```

If FreeRTOS is not available as a submodule, clone it manually:

```bash
cd "C:/Users/Michael/Documents/GitHub/trusted-firmware-m/lib/ext"
git clone https://github.com/FreeRTOS/FreeRTOS-Kernel.git freertos
cd freertos
git checkout V11.0.1  # Or latest stable version
```

---

## Build Commands

### Configure TF-M Build

```bash
cd "C:/Users/Michael/Documents/GitHub/trusted-firmware-m"

cmake -S . -B build_ra6m4_freertos \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DFSP_ROOT_DIR="${FSP_ROOT_DIR}" \
  -DFREERTOS_DIR="${FREERTOS_DIR}" \
  -DARM_TOOLCHAIN_PATH="${ARM_TOOLCHAIN_PATH}" \
  -DCONFIG_TFM_ENABLE_CP10CP11=ON \
  -G Ninja
```

### Build TF-M

```bash
cmake --build build_ra6m4_freertos
```

### Expected Output

```
build_ra6m4_freertos/bin/
├── bl2.bin          ← Bootloader (128KB)
├── bl2.hex
├── bl2.elf
├── tfm_s.bin        ← Secure firmware with TF-M services
├── tfm_s.hex
├── tfm_s.elf
├── tfm_ns.bin       ← Non-secure FreeRTOS test application
├── tfm_ns.hex
├── tfm_ns.axf
└── *.map            ← Map files
```

---

## Build Options Explained

### Required Options

| Option | Description |
|--------|-------------|
| `-DTFM_PLATFORM=renesas/ra6m4` | Select RA6M4 platform |
| `-DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake` | Use ARM GCC toolchain |
| `-DFSP_ROOT_DIR=...` | Path to FSP modular libraries |
| `-DFREERTOS_DIR=...` | Path to FreeRTOS kernel |

### Optional Performance Options

| Option | Default | Description |
|--------|---------|-------------|
| `-DCONFIG_TFM_ENABLE_CP10CP11=ON` | OFF | Enable FPU (Cortex-M33 has FPU) |
| `-DCMAKE_BUILD_TYPE=Release` | Debug | Optimized build |

### Optional Test Options

| Option | Default | Description |
|--------|---------|-------------|
| `-DTEST_S=ON` | OFF | Build TF-M secure tests |
| `-DTEST_NS=ON` | OFF | Build TF-M non-secure tests |
| `-DBL2=ON` | ON | Include MCUboot bootloader |

---

## Memory Map

The test application uses the standard RA6M4 TF-M memory layout:

### Flash (1MB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| BL2 | 0x00000000 - 0x0001FFFF | 128KB | MCUboot bootloader |
| Secure | 0x00020000 - 0x0007FFFF | 384KB | TF-M secure firmware |
| Non-Secure | 0x00080000 - 0x000FFFFF | 512KB | FreeRTOS test app |

### RAM (256KB)

| Region | Address Range | Size | Description |
|--------|---------------|------|-------------|
| Secure | 0x20000000 - 0x2001FFFF | 128KB | TF-M secure RAM |
| Non-Secure | 0x20020000 - 0x2003FFFF | 128KB | FreeRTOS heap + tasks |

### FreeRTOS Configuration

From [FreeRTOSConfig.h](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\include\FreeRTOSConfig.h):

- **Heap Size**: 64KB (`configTOTAL_HEAP_SIZE`)
- **Tick Rate**: 1000 Hz (1ms tick)
- **CPU Clock**: 200 MHz
- **Task Stack**: 4096 words (16KB) for TF-M test task
- **TrustZone**: Enabled (`configENABLE_TRUSTZONE = 1`)

---

## Expected Test Execution Flow

### Boot Sequence

1. **BL2 (MCUboot)** validates and boots TF-M
2. **TF-M Secure** initializes all secure services:
   - Attestation
   - Internal Trusted Storage
   - Crypto (PSA Crypto API)
   - Platform services (HUK)
3. **Non-Secure FreeRTOS** starts:
   - `main()` creates TF-M test task
   - `vTaskStartScheduler()` starts FreeRTOS
4. **TF-M Test Task** runs:
   - Calls `tfm_ns_interface_init()`
   - Runs all service tests sequentially
   - Enters idle loop with 1-second delay

### Test Sequence

```
[main_ns.c:32]  xTaskCreate("TFM_Test", ...)
[main_ns.c:48]  vTaskStartScheduler()

[tfm_test_thread.c:220]  tfm_ns_interface_init()
[tfm_test_thread.c:223]  test_attestation_service()
    ↳ psa_initial_attest_get_token_size() → PASS
    ↳ psa_initial_attest_get_token() → PASS

[tfm_test_thread.c:224]  test_storage_service()
    ↳ psa_its_set(uid=1, data=0x11223344...) → PASS
    ↳ psa_its_get(uid=1, ...) → PASS

[tfm_test_thread.c:225]  test_crypto_random()
    ↳ psa_generate_random(10 bytes) → PASS

[tfm_test_thread.c:226]  test_crypto_hash()
    ↳ SHA-256("abc") → PASS
    ↳ SHA-256("abcdddddddd") → PASS

[tfm_test_thread.c:227]  test_huk_derivation()
    ↳ psa_key_derivation_setup(HKDF-SHA256) → PASS
    ↳ psa_key_derivation_input_key(HUK) → PASS
    ↳ psa_key_derivation_output_key() → PASS
    ↳ psa_export_key() → 256-bit derived key

[tfm_test_thread.c:230]  while(1) vTaskDelay(1000ms)
```

---

## Debugging Build Issues

### Issue 1: FreeRTOS Not Found

**Error**: `FreeRTOS directory not found: .../lib/ext/freertos`

**Fix**:
```bash
cd trusted-firmware-m
git submodule update --init lib/ext/freertos
```

Or set `FREERTOS_DIR` to a manual clone:
```bash
export FREERTOS_DIR="/path/to/FreeRTOS-Kernel"
```

### Issue 2: FSP Libraries Not Found

**Error**: `Could not find fsp_bsp.cmake`

**Fix**: Ensure FSP_ROOT_DIR points to the modular FSP project:
```bash
export FSP_ROOT_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4"

# Verify FSP modules exist
ls "${FSP_ROOT_DIR}/cmake/modules/"
# Should show: fsp_bsp.cmake, fsp_uart.cmake, fsp_flash.cmake
```

### Issue 3: Linker Errors (Undefined TF-M APIs)

**Error**: `undefined reference to 'tfm_ns_interface_init'`

**Fix**: Ensure the ns_app CMakeLists.txt links `tfm_api_ns`:
```cmake
target_link_libraries(tfm_ns
    PRIVATE
        tfm_api_ns    # ← TF-M non-secure API library
        platform_ns
)
```

### Issue 4: Stack Overflow at Runtime

**Symptom**: Hangs in `vApplicationStackOverflowHook()`

**Fix**: Increase task stack size in [main_ns.c:17](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\src\main_ns.c#L17):
```c
#define TFM_TEST_TASK_STACK_SIZE    (8192)  // Increase from 4096
```

---

## Flashing to Hardware

### Option 1: J-Link Commander

```bash
JLinkExe -device R7FA6M4AF -if SWD -speed 4000

# Inside J-Link prompt:
> loadfile build_ra6m4_freertos/bin/bl2.hex
> loadfile build_ra6m4_freertos/bin/tfm_s.hex
> loadfile build_ra6m4_freertos/bin/tfm_ns.hex
> r
> go
> exit
```

### Option 2: Renesas Flash Programmer

1. Open Renesas Flash Programmer
2. Select **R7FA6M4AF** device
3. Load and program in order:
   - `bl2.hex` → 0x00000000
   - `tfm_s.hex` → 0x00020000
   - `tfm_ns.hex` → 0x00080000
4. Click **Start** to program and verify

### Option 3: Combined Hex File

Create a single hex file with all regions:

```bash
cd build_ra6m4_freertos/bin
srec_cat bl2.hex -Intel tfm_s.hex -Intel tfm_ns.hex -Intel -o tfm_combined.hex -Intel
```

Then flash `tfm_combined.hex` in one operation.

---

## Verifying Test Results

### UART Console Output

Connect to UART0 (SCI0) on RA6M4:
- **Baud**: 115200
- **Data**: 8-bit, No parity, 1 stop bit

Expected output (if TF-M has UART logging enabled):

```
[INF] Starting TF-M v2.x.x
[INF] Booting from slot 0
[INF] Image index: 1, Swap type: none
[INF] Jumping to the first image slot
[INF] TF-M secure side initialized
[INF] Non-secure interface initialized

[TFM_NS] FreeRTOS Test Task Starting...
[TFM_NS] Attestation Service: PASS
[TFM_NS] Storage Service: PASS
[TFM_NS] Crypto Random: PASS
[TFM_NS] Crypto Hash: PASS
[TFM_NS] HUK Derivation: PASS
[TFM_NS] All tests completed successfully
```

### Debug with GDB

```bash
arm-none-eabi-gdb build_ra6m4_freertos/bin/tfm_ns.axf

(gdb) target remote localhost:2331
(gdb) load
(gdb) break tfm_test_thread_entry
(gdb) continue
```

Set breakpoints at key test functions:
- `test_attestation_service:49` - After `psa_initial_attest_get_token_size()`
- `test_storage_service:87` - After `psa_its_get()`
- `test_crypto_hash:146` - After first SHA-256 verify
- `test_huk_derivation:204` - After `psa_export_key()`

---

## Adding More Tests

To add additional TF-M service tests, edit [tfm_test_thread.c:215](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\src\tfm_test_thread.c#L215):

```c
void tfm_test_thread_entry(void *pvParameters)
{
    tfm_ns_interface_init();

    // Existing tests
    test_attestation_service();
    test_storage_service();
    test_crypto_random();
    test_crypto_hash();
    test_huk_derivation();

    // Add new tests here
    test_crypto_aes();           // AES encryption
    test_protected_storage();    // PS service
    test_firmware_update();      // FWU service

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

---

## Summary

✅ **Created**: FreeRTOS-based non-secure test application
✅ **Integrated**: TF-M PSA API calls for all major services
✅ **Memory**: Configured for RA6M4 (512KB NS flash, 128KB NS RAM)
✅ **Build**: Modular CMake with FreeRTOS and FSP integration
✅ **Tests**: Attestation, ITS, Crypto (Random, SHA-256), HUK derivation

**Build Command**:
```bash
cmake -S . -B build_ra6m4_freertos -DTFM_PLATFORM=renesas/ra6m4 \
  -DFSP_ROOT_DIR="${FSP_ROOT_DIR}" -G Ninja
cmake --build build_ra6m4_freertos
```

**Flash**: Load `bl2.hex`, `tfm_s.hex`, `tfm_ns.hex` to RA6M4 hardware
**Verify**: Check UART console for test results or debug with GDB

---

## References

| Document | Purpose |
|----------|---------|
| [TF-M Platform README](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\README.md) | RA6M4 platform details |
| [TF-M Integration Complete](C:\Users\Michael\Documents\GitHub\fsp_cmake\TFM_INTEGRATION_COMPLETE.md) | Full TF-M integration guide |
| [FreeRTOSConfig.h](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\include\FreeRTOSConfig.h) | FreeRTOS configuration |
| [tfm_test_thread.c](C:\Users\Michael\Documents\GitHub\trusted-firmware-m\platform\ext\target\renesas\ra6m4\ns_app\src\tfm_test_thread.c) | Test implementation |

---

**Your RA6M4 TF-M integration is ready for testing!**
