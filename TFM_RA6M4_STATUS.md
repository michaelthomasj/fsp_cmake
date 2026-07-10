# TF-M + FSP CMake Port for RA6M4 — Status & Running TODO

**Purpose:** Port Trusted Firmware-M to the Renesas RA6M4 (R7FA6M4AF, Cortex-M33) using
RASC-generated FSP driver sources, wired into TF-M as a platform under
`platform/ext/target/renesas/ra6m4/`. Drivers are exposed as modular CMake libraries in
this repo (`fsp_cmake`) and consumed by TF-M via `FSP_*_APP_DIR` variables.

**Repos in scope (only these two):**
- `fsp_cmake` — RASC-generated FSP projects + modular CMake modules.
- `trusted-firmware-m` — branch `FSPRA-5483_FSP_TFM_Cmake_framework`, TF-M base `TF-Mv2.2.0-26`.

**Last substantive work:** December 23, 2025 (attestation HAL, cmse flag, BL2 header offsets).
**This refresh:** July 10, 2026.

---

## ✅ 2026-07-10 RESULT: core build produces all three images

`build_ra6m4_core` (default MCUboot BL2 + external FSP NS) **builds clean and signs all three images**
after one one-line fix (see below). This confirms the December secure+NS work is sound — the November
NS/region and multiple-definition failures are **gone**.

| Image | Flash (text+data) | BSS/RAM | Signed image | Slot (flash_layout.h) |
|---|---|---|---|---|
| bl2   | ~35 KB  | 19 KB | bl2.bin 35 KB          | BL2 128 KB (0x20000) |
| tfm_s | ~127 KB | 48 KB | tfm_s_signed.bin 192 KB | S primary 192 KB (0x30000) |
| tfm_ns| ~9 KB   | 4 KB  | tfm_ns_signed.bin 128 KB| NS primary 128 KB (0x20000) |

Flash map fills exactly 1 MB: BL2 128 + S 192 + NS 128 + S-sec 192 + NS-sec 128 + scratch 256.
Output dir: `trusted-firmware-m/build_ra6m4_core/bin/`.

**The one fix applied:** `attest_hal.c` (December) `#include "tfm_strnlen.h"` had no include path (the port
sets `PLATFORM_DEFAULT_ATTEST_HAL OFF`, so it doesn't inherit `tfm_sprt`'s includes like the default HAL does).
Added `secure_fw/partitions/lib/runtime/include` to `platform_s` includes in the port's `CMakeLists.txt`.

## 2026-07-10 (cont.): observable boot image over SEGGER RTT

The `build_ra6m4_core` images are **not observable** (secure/SPM logging compiled to SILENCE in
Release; BL2 no logging; the FSP NS app just spins in `while(1) vTaskDelay(1)` and its smoke tests
are dead code). A silently-booting board would look identical to a hung one. So for the basic boot
test, use the instrumented build below.

**`build_ra6m4_boot`** = same core build (default MCUboot BL2 + external FSP NS) but with:
- `-DCMAKE_BUILD_TYPE=Debug -DMCUBOOT_LOG_LEVEL=INFO -DTFM_SPM_LOG_LEVEL=..._INFO
  -DTFM_PARTITION_LOG_LEVEL=..._INFO` → BL2 + TF-M secure now emit boot logs.
- **stdout routed to SEGGER RTT** (no UART wiring, no S/NS peripheral contention).

### RTT stdout backend (clean, switchable — does NOT touch the FSP UART driver)
- New files in the port: `rtt/rtt_stdout.c` (implements TF-M's `stdio_*` backend over RTT),
  `rtt/SEGGER_RTT.c` + `SEGGER_RTT.h` + `SEGGER_RTT_Conf.h` (from the ra8d2_gcm workspace, SEGGER v7.x).
- One switch: **`RA6M4_STDOUT_RTT`** (default ON) in `config.cmake`. ON → RTT backend, common
  `uart_stdout.c` disabled (`PLATFORM_DEFAULT_UART_STDOUT` forced OFF). OFF → back to FSP SCI UART
  via the untouched `cmsis_drivers/Driver_USART.c`. Flipping the flag is the entire switch.
- Verified in the binaries: `_SEGGER_RTT` CB in secure image @ `0x2000baf8`, in BL2 @ `0x20002ed0`;
  exactly one `stdio_output_string` (RTT one; UART backend not linked). Build clean.
- Note: BL2 and the secure image are separate binaries with **separate RTT control blocks** at
  different addresses. J-Link RTT Viewer auto-search finds the currently-running image's CB; seeing
  the secure "Booting TF-M" over RTT already proves BL2 validated the image and jumped to secure.

### How to flash + watch (basic boot bring-up)
1. Flash `build_ra6m4_boot/bin/`: `bl2.hex`, then `tfm_s_signed.bin` @ `0x20000`, `tfm_ns_signed.bin`
   @ `0x40000` (J-Link or Renesas Flash Programmer, device `R7FA6M4AF`).
2. J-Link RTT Viewer / `JLinkRTTClient`, device `R7FA6M4AF`, SWD. Auto-detect RTT (or set CB address
   to the secure CB above).
3. Reset. Expected over RTT:
   - BL2: `[INF] Starting bootloader` → `[INF] Bootloader chainload address offset: 0x20000` →
     `[INF] Jumping to the first image slot`
   - Secure: `Booting TF-M v2.2.0+...` → `[Sec Thread] Secure image initializing!`
   - Reaching the secure banner = BL2 works + jumped into the app. TF-M then starts the NS agent
     (the S→NS transition). **Positive NS-side proof still TODO** — the FSP NS app currently produces
     no output/LED (see open TODO).

## ⛔ 2026-07-10 KEY BLOCKER: NS linker regions don't match TF-M's NS partition

Found while wiring the NS RTT banner. The FSP NS app (`FSP_Project_ra6m4_ns_rtos/memory_regions.ld`)
is linked for a **standalone** layout that does NOT match where TF-M puts the non-secure image:

| | NS FSP app linked for | TF-M expects (region_defs.h / config) |
|---|---|---|
| RAM  | `RAM_START=0x20002000`, len `0x3e000` (**inside SECURE RAM** 0x20000000–0x2001FFFF) | `NS_RAM_ALIAS_BASE=0x20020000`, `0x20000` |
| Flash| `FLASH_START=0x00008000`, len `0xf8000` | NS partition `0x40000` (config.cmake) |

Consequences on hardware:
- NS is linked to run from **secure RAM** → SAU/SecureFault the instant TF-M jumps to NS.
- NS absolute addresses point at `0x8xxx` flash while the signed image is placed at the NS slot
  (`0x40000`/`0x50000`) → wrong vector table / reset handler.
- **Net: the secure→non-secure jump will fault.** BL2→secure is unaffected (TF-M links secure correctly).

**Also: the NS flash offset is itself inconsistent** — `config.cmake` says NS `0x40000`, but
`flash_layout.h` computes `FLASH_AREA_1` (NS primary) at `0x50000` (S primary is 0x30000, not 0x20000).
The memory map has **three disagreeing sources of truth** (config.cmake, flash_layout.h, FSP
memory_regions.ld) that must be reconciled before NS can boot.

### Fix required (next task)
1. Pick ONE authoritative NS flash/RAM layout and make config.cmake, flash_layout.h, region_defs.h,
   and the FSP NS `memory_regions.ld`/`fsp.ld` all agree.
2. Re-link the FSP NS app for NS RAM `0x20020000` (size 0x20000) and the NS code slot
   (flash `0x40000 + BL2_HEADER 0x400`, size ≈ `0x1F400`). Likely regenerate via RASC with the
   correct linker settings, or hand-edit `memory_regions.ld`.
3. Re-verify the signed NS image offset used for flashing matches the reconciled NS partition.

The NS RTT banner (`new_thread0_entry.c`) is in place and correct — it just needs the NS image to
actually run, which the above unblocks.

## Big picture: where things stand

- The port is **structurally complete and was build-worked through Dec 2025**, but the
  **last captured build logs (Nov 19, 2025) end in failures** that the December commits were
  meant to fix. After those December fixes, **no clean end-to-end build was ever captured**,
  and **no hardware testing was ever done**.
- Goal of this effort: (1) reproduce a clean full build producing all three images
  (bl2 / tfm_s / tfm_ns), (2) verify boot on EK-RA6M4 over UART, (3) run the TF-M test suite.

## Key facts / gotchas discovered

- **Secure side uses the embedded `fsp/` tree** inside the TF-M port dir — it does NOT need
  `FSP_S_APP_DIR`. Only **BL2** (`FSP_BL2_APP_DIR`) and **NS** (`FSP_NS_APP_DIR`) consume
  external RASC projects (they have `tfm_integration/CMakeLists_tfm.cmake`; the `_s`/`_s_rtos`
  projects do not).
- The built-in fallback `ns_app/` needs FreeRTOS at `lib/ext/freertos`, which is **not checked
  out** (submodule absent). So the NS side must use the **external** `FSP_Project_ra6m4_ns_rtos`.
- `fsp_cmake` working tree had **~900 uncommitted deletions** of RASC vendor sources (FreeRTOS,
  BSP, MCUboot, mbedTLS). These were **restored** from git on 2026-07-10 — needed for the
  external BL2/NS builds. Do not re-delete them without gitignoring/regenerating.
- Config pins: software crypto only (`CRYPTO_HW_ACCELERATOR OFF`), BL2 = Renesas MCUboot fork
  `2.1.0+renesas.3` (`MCUBOOT_IMAGE_NUMBER=2`), asymmetric attestation (256-bit), PS encrypted (GCM).

## Full build command (December-intended configuration)

```bash
export ARM_TOOLCHAIN_PATH="C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin"
cd C:/Users/Michael/Documents/GitHub/trusted-firmware-m
cmake -S . -B build_ra6m4_full \
  -DTFM_PLATFORM=renesas/ra6m4 \
  -DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DBL2=ON \
  -DFSP_BL2_APP_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_bl2" \
  -DFSP_NS_APP_DIR="C:/Users/Michael/Documents/GitHub/fsp_cmake/FSP_Project_ra6m4_ns_rtos" \
  -G Ninja
cmake --build build_ra6m4_full
```

---

## Findings from the 2026-07-10 build attempt

- **External FSP BL2 integration is broken at configure time.**
  `FSP_Project_ra6m4_bl2/tfm_integration/CMakeLists_tfm.cmake` references files that do not exist
  in the RASC project (confirmed absent on disk *and* in git — never committed):
  - `ra/arm/mbedtls/library/hash_info.c` — the project ships a **newer mbedTLS** (~141 files,
    includes `psa_crypto_mlkem.c` etc.) where `hash_info.c` was folded into `md.c`. The integration
    script was written against an older mbedTLS 3.x layout.
  - `ra/fsp/src/rm_mcuboot_port/flash_map_backend/flash_map_backend.c` — only `flash_map_backend.h`
    exists; the backend `.c` logic appears to live in `ra/fsp/src/rm_mcuboot_port/flash_map.c`.
  - Result: `fsp_mcuboot_port` and `fsp_mbedtls_bl2` get "No SOURCES given to target".
  - **This is why no clean external-BL2 build was ever produced.** Fixing it means reconciling the
    BL2 integration cmake with the actual RASC 6.1.0 mbedTLS + mcuboot_port file layout (separate task).
- **Workaround in progress:** build the core (secure + NS) with TF-M's **default downloaded MCUboot**
  (drop `FSP_BL2_APP_DIR`, keep `FSP_NS_APP_DIR`). This validates the December NS/region fixes, which
  is where the November failures actually were.

## Regression suite: how it actually works in TF-M v2.2 (investigated 2026-07-10)

- **`TEST_S` / `TEST_NS` are NOT valid flags here.** Passing them to the main build yields
  `Manually-specified variables were not used by the project` and they are silently ignored — the
  build just produces a normal non-test image. **This is almost certainly why the November test
  attempt was malformed** (`build_tfm_api_test.log` multiple-definition cascade).
- TF-M v2.2 uses a **split SPE/NSPE build**:
  1. **SPE (secure):** configure + `cmake --build <spe> -- install`. Installs an `api_ns/` export tree
     containing `spe-CMakeLists.cmake`, `toolchain_ns_GNUARM.cmake`, platform NS sources, and the
     secure interface. (The RA6M4 port already installs its NS toolchain + platform NS bits — good.)
  2. **NSPE (tests):** configure the **fetched `tf-m-tests`** NS app against the installed SPE via
     `-DCONFIG_SPE_PATH=<spe>/api_ns`, with the regression flags (standard names
     `TFM_S_REG_TEST=ON` / `TFM_NS_REG_TEST=ON` — confirm exact names from the fetched
     `lib/ext/tf-m-tests` once downloaded). Then build → produces the NS regression `tfm_ns`.
- **Port gap:** the port's `CMakeLists.txt` NS logic is only
  `if(FSP_NS_APP_DIR) <FSP FreeRTOS app> else() add_subdirectory(ns_app)` — there is **no branch for
  the standard tf-m-tests NS app**, and the `ns_app` fallback needs `lib/ext/freertos` (absent). So
  the standard NSPE regression app has **never been built** against this port. The FSP FreeRTOS app
  (with its bespoke smoke tests) was the only NS path exercised.

### Two viable routes to run the official suite (decide before doing)
- **Route A — proper split build (recommended, more work):** do the SPE install, fetch tf-m-tests,
  build the NSPE regression app against the installed SPE. Requires confirming the RA6M4 NS platform
  (startup, linker script, `platform_ns`, syscalls) links cleanly against the standard tf-m-tests NS
  app — untested territory.
- **Route B — extend the FSP smoke test (faster, less "official"):** add the tf-m-tests NS regression
  suite sources to the existing FSP FreeRTOS `tfm_ns` app (the smoke test already calls PSA APIs).
  Keeps the working NS build; less canonical but exercises the same test content.

## TODO (open)

- [ ] **Fix the FSP BL2 integration cmake** to match the actual RASC 6.1.0 file layout (mbedTLS
      `hash_info.c` → drop/use `md.c`; `flash_map_backend.c` → `flash_map.c`). Then re-attempt the
      full external-BL2 build.
- [x] **Reproduce clean build (core: default BL2 + external NS)** — DONE 2026-07-10. All three images
      produced and signed. Nov failures gone.
- [ ] Reconcile `config.cmake` (`FLASH_S_PARTITION_SIZE 0x20000`) vs `flash_layout.h`
      (`FLASH_AREA_0_SIZE 0x30000`) — same-named macro, different values. Build works (flash_layout.h wins
      for MCUboot), but the stale config.cmake value/comment is confusing. Not a blocker.
- [ ] Confirm Dec fixes resolved the Nov failures:
      - [ ] NS linker: `undefined symbol NS_HEAP_SIZE`, `invalid origin/length for FLASH/RAM`.
      - [ ] `multiple definition` cascade / `cannot use executable 'bin/tfm_s.axf' as input` (test build).
      - [ ] `FLASH_DEVICE_ID` redefinition warning (flash_layout.h vs mcuboot).
- [ ] Verify output image sizes fit the flash layout (S primary 128KB, NS primary 128KB).
- [ ] **Flash `build_ra6m4_boot` + watch RTT** — confirm BL2 boots and jumps into TF-M secure
      (see "observable boot image" section). IMAGES READY 2026-07-10.
- [x] **Add positive NS-side signal** — DONE: `new_thread0_entry.c` now inits SEGGER RTT and prints
      `[NS] non-secure world running (TF-M S->NS jump OK)` + heartbeat. (Won't appear until the NS
      linker blocker below is fixed.)
- [ ] **⛔ FIX NS linker regions** (see "KEY BLOCKER" above) — NS is linked for secure RAM
      (0x20002000) and flash 0x8000; must be NS RAM 0x20020000 + NS flash slot. Blocks the S→NS jump.
- [ ] **Reconcile the memory map** across config.cmake / flash_layout.h / region_defs.h / FSP
      memory_regions.ld (NS flash 0x40000 vs 0x50000; S slot 0x20000 vs 0x30000).
- [ ] Get the bespoke NS smoke test passing (attestation / ITS / crypto random / SHA-256 / HUK).
- [ ] Wire in the **official TF-M regression suite** — see "Regression suite" section above. NOT a
      flag flip: needs the split SPE-install + NSPE(tf-m-tests) build (Route A) or extending the FSP
      NS app (Route B). `TEST_S`/`TEST_NS` are ignored on the main build (v2.2 model).
- [ ] Fix bad hash test vector: `FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.c` (and the TF-M
      `ns_app/src/tfm_test_thread.c:127`) has `0xcb4` — an out-of-range `uint8_t` literal.

## TODO (cleanup / hardening — lower priority)

- [ ] Remove committed backup/scratch files in the TF-M port: `CMakeLists.txt.bak`,
      `CMakeLists.txt.backup`, `flash_layout.h.bak`, `cmsis_drivers/Driver_Flash_original.c`,
      `flash_temp.txt`, duplicate `README_FULL.md`.
- [ ] Decide on the dead `tfm_hal_isolation.c` (v7M-style, superseded by common `tfm_hal_isolation_v8m.c`).
- [ ] Replace stubs before any production use: `tfm_platform_hal_ioctl` (returns NOT_SUPPORTED),
      `tfm_attest_hal_get_platform_config` (dummy `0xDEADBEEF`), flash-based NV counters, dummy provisioning.
- [ ] Consider enabling RA6M4 HW crypto (SCE9/RSIP) instead of software mbedTLS.
- [ ] Add a `.gitignore` in `fsp_cmake` (build dirs, e.g. `FSP_Project_ra6m4_s_rtos/build/`).
- [ ] Refresh the Nov-dated status docs (`TFM_INTEGRATION_COMPLETE.md`, `BUILD_TEST_RESULTS.md`) or
      mark them superseded by this file.

## DONE

- [x] Reconstructed project state from docs + git history (Nov docs are stale; real work ran to Dec 23, 2025).
- [x] Confirmed toolchain present: Arm GNU 13.2 Rel1 (`arm-none-eabi-gcc`).
- [x] Confirmed TF-M base = `TF-Mv2.2.0-26-g292f82c23`, branch `FSPRA-5483_FSP_TFM_Cmake_framework`.
- [x] Restored ~900 uncommitted-deleted FSP vendor sources in `fsp_cmake` (needed for BL2/NS builds).
- [x] Mapped the build wiring: secure = embedded fsp/; BL2 + NS = external via `FSP_*_APP_DIR`.
- [x] Started clean full-build configure into `build_ra6m4_full` (2026-07-10) — found external BL2 broken.
- [x] Built core (default BL2 + external NS) end-to-end: bl2 + tfm_s + tfm_ns all produced & signed (2026-07-10).
- [x] Applied fix: added runtime include dir for `attest_hal.c`'s `tfm_strnlen.h` (TF-M `CMakeLists.txt`).

## Reference: file map

| Thing | Path |
|---|---|
| TF-M platform port | `trusted-firmware-m/platform/ext/target/renesas/ra6m4/` |
| Platform config | `.../ra6m4/config.cmake`, `.../ra6m4/CMakeLists.txt` |
| Custom attest HAL | `.../ra6m4/attest_hal.c` |
| Modular FSP modules (secure) | `.../ra6m4/cmake/modules/fsp_{bsp,uart,flash}.cmake` |
| BL2 RASC project + integration | `fsp_cmake/FSP_Project_ra6m4_bl2/tfm_integration/CMakeLists_tfm.cmake` |
| NS RASC project + integration | `fsp_cmake/FSP_Project_ra6m4_ns_rtos/tfm_integration/CMakeLists_tfm.cmake` |
| NS smoke tests | `fsp_cmake/FSP_Project_ra6m4_ns_rtos/src/tfm_service_tests.c` |
| FSP / RASC version | FSP 6.1.0 / RASC `sc_v2025-07` |

---
_Update this file as items move between TODO and DONE._
