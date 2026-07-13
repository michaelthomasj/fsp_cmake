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
   @ `0x50000` (J-Link or Renesas Flash Programmer, device `R7FA6M4AF`).
   RTT control blocks after the NS layout fix: BL2 `0x20002ed0`, Secure `0x2000baf8`, NS `0x20020854`.
2. J-Link RTT Viewer / `JLinkRTTClient`, device `R7FA6M4AF`, SWD. Auto-detect RTT (or set CB address
   to the secure CB above).
3. Reset. Expected over RTT:
   - BL2: `[INF] Starting bootloader` → `[INF] Bootloader chainload address offset: 0x20000` →
     `[INF] Jumping to the first image slot`
   - Secure: `Booting TF-M v2.2.0+...` → `[Sec Thread] Secure image initializing!`
   - Reaching the secure banner = BL2 works + jumped into the app. TF-M then starts the NS agent
     (the S→NS transition). **Positive NS-side proof still TODO** — the FSP NS app currently produces
     no output/LED (see open TODO).

## ⛔ 2026-07-10 KEY BLOCKER + authoritative memory map

Found while wiring the NS RTT banner: the FSP NS app is linked for a standalone layout that puts NS in
**secure RAM**, so the S→NS jump will SecureFault. Full investigation below.

### Authoritative memory map (source of truth = `flash_layout.h` + `region_defs.h`)
`flash_layout.h` is a **static** header that hardcodes `FLASH_AREA_*`; config.cmake's
`FLASH_*_PARTITION_*` cache vars are **vestigial for ra6m4** (only mps3 platforms consume them) and do
NOT affect the build. Signing confirms it: `tfm_s_signed.bin`=0x30000, `tfm_ns_signed.bin`=0x20000 match
`flash_layout.h` slot sizes, not config.cmake. NOTE: the inline comments in `flash_layout.h`
(`/* 0x40000 */` etc.) are STALE — the computed offsets below are what actually build.

| Region | Offset | Size | Notes |
|---|---|---|---|
| BL2 | `0x00000` | 128K (0x20000) | MCUboot |
| **S primary** (AREA_0) | `0x20000` | **192K (0x30000)** | flash tfm_s_signed.bin here |
| **NS primary** (AREA_1) | **`0x50000`** | 128K (0x20000) | flash tfm_ns_signed.bin here (NOT 0x40000) |
| S secondary (AREA_2) | `0x70000` | 192K | swap slot |
| NS secondary (AREA_3) | `0xA0000` | 128K | swap slot |
| scratch | `0xC0000` | 256K | fills to 1MB exactly |
| S RAM | `0x20000000` | 128K | secure |
| NS RAM | `0x20020000` | 128K | non-secure |

Derived (region_defs.h): `BL2_HEADER_SIZE`=0x400, `BL2_TRAILER_SIZE`=0x800.
- **NS code runs at `NS_CODE_START` = 0x50000 + 0x400 = `0x50400`**, size `NS_CODE_SIZE` = 0x20000 − 0x400 − 0x800 = **`0x1F400`**.
- NS data RAM = `0x20020000`, size `0x20000`.

### The bug (FSP NS `memory_regions.ld`, RASC-generated standalone layout)
| | NS app linked for (WRONG) | Must be (authoritative) |
|---|---|---|
| RAM  | `0x20002000`, len `0x3e000` (**in SECURE RAM**) | `0x20020000`, len `0x20000` |
| Flash| `0x00008000`, len `0xf8000` | `0x50400`, len `0x1F400` |

→ NS runs from secure RAM (SecureFault on S→NS) and its vectors reference `0x8xxx` while flashed at
`0x50000`. BL2→secure is unaffected (TF-M links secure correctly).

### Correct flash offsets for hardware (supersedes earlier 0x40000 guidance)
`bl2.hex` @ `0x00000` · `tfm_s_signed.bin` @ **`0x20000`** · `tfm_ns_signed.bin` @ **`0x50000`**.

### Fix (applied 2026-07-10)
1. `memory_regions.ld` → NS RAM `0x20020000`/`0x20000`, NS flash `0x50400`/`0x1F400`.
2. config.cmake stale FLASH_S/NS values aligned to flash_layout.h for clarity (functionally inert).
   NOTE: `memory_regions.ld` is RASC-"generated" — regeneration must reproduce these values (set the
   FSP project's linker/BSP config accordingly) or re-apply the edit.
3. Watch: NS FreeRTOS heap (`FreeRTOSConfig.h` `configTOTAL_HEAP_SIZE`) must fit the 128K NS RAM.

## 2026-07-13: BL2 must use the RASC MCUboot port (flash geometry)

The current BL2 uses TF-M's downloaded Renesas MCUboot fork + the generic CMSIS `Driver_Flash.c`
path (MCUboot → `ARM_DRIVER_FLASH` → `R_FLASH_HP`). **That path has the wrong RA6M4 flash geometry
and would fail on hardware:**
- RA6M4 HP code flash: **region 0** `0x0–0xFFFF` = 8 KB blocks; **region 1** `0x10000`+ = **32 KB blocks**.
- S primary (`0x20000`) and NS primary (`0x50000`) are both in **region 1 → 32 KB erase blocks**.
- But `Driver_Flash.c` assumes 8 KB (`sector_size = FLASH_AREA_IMAGE_SECTOR_SIZE = 0x2000`, block size
  from `REGION0_BLOCK_SIZE`, and it errors if page size != 0x2000). MCUboot erase/swap of the region-1
  slots would fail.
- `rm_mcuboot_port/flash_map.c` handles this natively: `..._INTERNAL_FLASH_BLOCK_SIZE (0x8000)` / "erase
  sector size to 32K". This is why the RASC port + the fork's "flash block alignment" changes go together.

**RESOLUTION (2026-07-13): fixed the geometry in TF-M's OWN flash path — did NOT graft FSP's flash_map.c.**
Attempting to graft the RASC `rm_mcuboot_port/flash_map.c` into TF-M's bootutil revealed a fundamental
incompatibility: the RASC BL2 project is configured for **single-image** MCUboot (`bsp_linker_info.h`:
`MCUBOOT_IMAGE_NUMBER 1`, FSP area IDs `FLASH_AREA_0P/0S/S_ID`), but TF-M here is **dual-image**
(`MCUBOOT_IMAGE_NUMBER=2`, separate S+NS). FSP's flash_map.c carries FSP's whole flash identity
(layout/area-IDs/config via `bsp_linker_info.h`), which cascaded into config, `flash_device_base`, and
linker-symbol conflicts and would not boot even if linked. So the graft was reverted.

The actual bug — RA6M4 region-1 32KB erase geometry — was fixed directly in TF-M's flash driver
(commit `f9c13269a`): `FLASH_AREA_IMAGE_SECTOR_SIZE = 0x8000` (32KB) and `Driver_Flash.c`
`FLASH_HP_BLOCK_SIZE` → `REGION1` (32KB). This keeps TF-M's correct dual-image flash_map/area-IDs and
builds clean via the **default BL2 path** (`build_ra6m4_boot`, TF-M MCUboot + fixed Driver_Flash.c).
All three signed images still produced (bl2, tfm_s 192KB @0x20000, tfm_ns 128KB @0x50000).

Deferred: the external FSP BL2 path (`FSP_BL2_APP_DIR`) — to actually use the RASC MCUboot port would
require reconfiguring the RASC BL2 project to dual-image in RASC and regenerating. The staged work
(glob-refactored `tfm_integration/CMakeLists_tfm.cmake`, `mbedtls_user_config.h`) remains for that future
effort. NOTE: the earlier BL2 integration was also unfinished scaffolding — `FSP_BL2_LIBRARIES` linked
nowhere; hand-typed file lists referenced files absent in FSP 6.1.0 (`hash_info.c`, `flash_map_backend.c`).

**Design rule (per user):** do NOT modify RASC output (GeneratedSrc.cmake globs stay as-is). The TF-M BL2
CMakeLists must SELECT the needed files from the RASC-generated tree via directory globs, organized into
the module separation TF-M requires — excluding files TF-M provides itself (e.g. `ra_gen/main.c`).

### Finalized BL2 integration decisions (2026-07-13)
- **MCUboot bootutil:** use the RASC copy in-place (`FSP_BL2_APP_DIR/ra/mcu-tools/MCUboot`) via
  `MCUBOOT_PATH` — do NOT download (identical to the RASC one).
- **Flash abstraction:** RASC `rm_mcuboot_port/flash_map.c` (correct 32 KB region-1 geometry) + `rm_mcuboot_port.c`.
  Disable TF-M's CMSIS `Driver_Flash` flash-map path.
- **Crypto:** software mbedTLS. `MCUBOOT_USE_MBED_TLS` + `MBEDTLS_USER_CONFIG_FILE =
  tfm_integration/mbedtls_user_config.h` which `#undef`s the 17 SCE9 crypto ALT macros. **KEEP
  `MBEDTLS_ENTROPY_HARDWARE_ALT`** — mbedTLS needs it to pull entropy from the RA TRNG.
- **Signing:** keep TF-M's default signing flow (it already calls `${MCUBOOT_PATH}/scripts/imgtool.py`).
  Because `MCUBOOT_PATH` points at the RASC MCUboot, this **automatically uses RASC's `imgtool.py`** — no
  changes needed. (`rm_mcuboot_port_sign.py` is only for standalone RASC MCUboot projects; not used for TF-M.)
- **bootutil build glue:** RASC strips TF-M's `boot/bootutil/CMakeLists.txt` (its MCUboot is built by
  RASC's own CMake). TF-M's `add_subdirectory(${MCUBOOT_PATH}/boot/bootutil)` needs it, and the bootutil
  `src/` set is identical, so the 35-line generic ARM/TF-M `bootutil/CMakeLists.txt` was copied into the
  RASC MCUboot tree (a build file, not RASC-generated source). Re-copy if RASC regeneration removes it.
- **NV counters + image versioning + boot_hal:** keep TF-M's (`bl2/src/security_cnt.c`).
- **Sources:** directory-glob from the RASC tree per module; exclude TF-M-provided files (`ra_gen/main.c`).

### Two integration points to handle during the switch
1. **MCUboot NV (rollback) counters:** TF-M's BL2 provides the MCUboot non-volatile security-counter
   implementation; `rm_mcuboot_port` does NOT. Must keep/incorporate TF-M's NV-counter backend in the
   build when switching to the RASC MCUboot.
2. **mbedTLS crypto ALT flags:** the RASC MCUboot ships crypto via mbedTLS with `*_ALT` flags routing to
   RA hardware (SCE9/RSIP). For now use **software crypto** → disable the mbedTLS ALT flags in the BL2
   mbedTLS config. **TODO later: switch to hardware crypto** (re-enable ALT / SCE9-RSIP path).

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

## Hardware bring-up: TrustZone boundaries + flash/RTT

**Bring-up scripts:** `bringup/flash_ra6m4.jlink` (J-Link flash) + `bringup/bringup_ra6m4.sh`
(flash + RTT stream). `./bringup_ra6m4.sh` flashes and streams the SECURE RTT block;
`bl2`/`ns`/`noflash` args switch the RTT source. Device `R7FA6M4AF`, SWD.

**Images have full debug symbols** (`CMAKE_BUILD_TYPE=Debug`) — load `bl2.axf` / `tfm_s.elf` /
`tfm_ns.axf` into J-Link GDB / Ozone / e2studio for source-level debug. `.bin`/`.hex` are stripped.

**RTT control blocks** (per-image, from `nm` on the built .axf): BL2 `0x20002bd0`, Secure `0x2000baf8`,
NS `0x20020854`.

### TrustZone / IDAU security boundaries to program (via Renesas Flash Programmer TrustZone settings)
The RA6M4 IDAU hardware boundaries partition memory; TF-M's SAU refines the NSC. From region_defs.h /
the built layout (dual-image, BL2+S secure, NS non-secure):

| Memory | Secure | Non-Secure | Boundary |
|---|---|---|---|
| Code flash | `0x00000000`–`0x0004FFFF` (BL2 128K + S slot 192K) | `0x00050000`–`0x000FFFFF` (NS slot + secondary slots + scratch) | **`0x00050000`** |
| SRAM | `0x20000000`–`0x2001FFFF` (128K) | `0x20020000`–`0x2003FFFF` (128K) | **`0x20020000`** |
| Data flash | `0x08000000`–`0x08001FFF` (all — ITS/PS/NV) | (none) | all secure |

BL2 runs secure and accesses all slots for MCUboot swap, so putting NS-secondary/scratch in the
non-secure region above `0x50000` is fine.

**⚠⚠ NSC BLOCKER (2026-07-13): current image is NOT programmable on RA6M4 hardware.** The RA6M4
attributes code flash as three CONTIGUOUS regions `[Secure][NSC][Non-secure]`, and the port programs
NEITHER the SAU nor the hardware regions in software (`sau_and_idau_cfg()` is empty; no `SAU->RBAR/RLAR`
anywhere) — attribution relies entirely on what is burned via RFP. But the built image places the SG
veneers at `0x20C00` (start of secure, between the vector table and the rest of secure code), so there is
NO RFP boundary setting that makes `0x20C00` NSC while keeping `0x20C40–0x4FFFF` Secure and `0x50000+`
Non-secure. NS→S PSA calls (SG at `0x20C00`) therefore cannot be attributed. **Fix before programming NSC:**
- **Path A (RA-native, needs the custom linker script — now a PREREQUISITE):** move veneers to the END of
  secure (`TFM_LINKER_VENEERS_LOCATION_END` or a platform-owned linker script) → contiguous layout
  `[Secure 0x0–0x4F3FF][NSC 0x4F400–0x4FFFF][NS 0x50000+]` (NSC size/align per RA6M4 code-flash TZ
  granularity — confirm vs hardware manual).
- **Path B (software):** fill in `sau_and_idau_cfg()` to program the SAU to mark the veneer region NSC at
  `0x20C00`; hardware regions then only do the coarse S/NS split.

S/NS boundaries that ARE correct/programmable now: code flash S `0x0–0x4FFFF` / NS `0x50000–0xFFFFF`;
SRAM S `0x20000000–0x2001FFFF` / NS `0x20020000–0x2003FFFF`; data flash all-secure.

_Older note (still true re: where the numbers come from):_
**NSC / veneer discrepancy:** `region_defs.h`
`CMSE_VENEER_REGION_START` computes `0x4F400` (end of secure), but the ACTUAL built image places the
secure-gateway veneers at **`0x20C00`** (`Image$$ER_VENEER$$Base`, limit `0x20C40`) — right after the
secure vector table. So the region_defs.h NSC macro is NOT what the linker uses. The SAU (TF-M common
v8m config) is what marks the veneer region NSC; the RA IDAU only needs the coarse S/NS split above.
Verify the SAU/veneer attribution on hardware; do NOT program an IDAU NSC region at 0x4F400.

## TODO (open)
- [ ] **Program TrustZone/IDAU boundaries** (RFP): code-flash S/NS @ `0x50000`, SRAM S/NS @ `0x20020000`,
      data flash all-secure. **NSC/veneer window = `0x20C00`–`0x20C40`** (linker `Image$$ER_VENEER$$Base`),
      NOT `region_defs.h` `CMSE_VENEER_REGION_START` (`0x4F400`).
- [ ] **⚠ PREREQUISITE for NSC boundary: move veneers to end of secure** (custom linker script, Path A) OR
      program the SAU in software (Path B). Current veneers @ `0x20C00` (start of secure) cannot be
      attributed NSC by the RA6M4 contiguous `[S][NSC][NS]` hardware model. See the NSC BLOCKER note above.
- [ ] **Use our OWN platform linker script (like STM32), not TF-M's default generated one.** Today the
      port relies on TF-M's common generated `tfm_isolation_s.ld`, so we don't control section placement —
      which is exactly why the veneers landed at `0x20C00` while `region_defs.h` assumed `0x4F400`. STM32
      platforms ship their own `Device/Source/gcc/tfm_common_s.ld` where the `region_defs.h` macros
      (`CMSE_VENEER_REGION_START`, etc.) ARE the section origins, so the C view and the image agree by
      construction. Adopt the same model for RA6M4: provide a platform-owned secure (and BL2/NS) linker
      script driven by our `region_defs.h`, giving deterministic control of the NSC/veneer window, the
      OFS regions, and the flash/RAM layout — instead of chasing TF-M's default placement. This also makes
      the IDAU/SAU NSC boundary derivable directly from `region_defs.h` (no linker-vs-macro divergence).
- [ ] **Clean up the stale NSC macro** — `region_defs.h` `CMSE_VENEER_REGION_START` (=0x4F400, end-of-secure
      model) is disconnected from the actual linker placement (TF-M's common `tfm_isolation_s.ld` places
      `.gnu.sgstubs` at the START of secure code → `0x20C00`, because `TFM_LINKER_VENEERS_LOCATION_END` is
      not defined). It only feeds `target_cfg.c`'s `nsc_cfg`, which has NO consumer (`sau_and_idau_cfg()`
      is empty; the correct value is the linker symbol `Image$$ER_VENEER$$Base`, used by the common
      `tfm_hal_platform_v8m.c`). Fix: point these at the linker symbol or delete the dead `nsc_cfg` /
      `CMSE_VENEER_REGION_*` to prevent the wrong value being used for IDAU/SAU NSC programming.

- [x] **Fix RA6M4 region-1 (32 KB) flash erase geometry** — DONE 2026-07-13 (commit `f9c13269a`).
      Fixed in TF-M's own `Driver_Flash.c` + `flash_layout.h` (32KB sector/block), NOT by grafting FSP's
      flash_map.c (which is single-image and incompatible with TF-M's dual-image MCUboot). Default BL2
      path builds all 3 images clean. Still needs hardware verification of erase/swap.
- [ ] **(Deferred) External RASC MCUboot BL2 path** — to use the RASC `rm_mcuboot_port`/MCUboot directly
      would require reconfiguring the RASC BL2 project to dual-image (`MCUBOOT_IMAGE_NUMBER=2`) in RASC
      and regenerating. Staged: glob-refactored BL2 `tfm_integration/CMakeLists_tfm.cmake` + `mbedtls_user_config.h`.
- [ ] **(BL2) Incorporate TF-M's MCUboot NV (rollback) counter implementation** — not provided by
      `rm_mcuboot_port`; must keep TF-M's NV-counter backend when moving to the RASC MCUboot.
- [ ] **(BL2) Disable mbedTLS `*_ALT` flags** in the BL2 mbedTLS config to use software crypto for now.
      **Later: switch to hardware crypto (SCE9/RSIP)** by re-enabling the ALT path. NOTE: chose option A
      (2026-07-13) — bootutil uses TF-M's software mbedcrypto for now; the FSP mbedTLS + SCE9 path (and
      `mbedtls_user_config.h`) is staged for this later HW-crypto switch. FSP mbedTLS is entangled with
      the FSP MCUboot config (`bsp_linker_info.h`), so the HW switch will need config isolation work.
- [ ] **(BL2) OFS / option-setting regions — VERIFY ON HARDWARE (not "defaults are fine").** The BL2 now
      uses TF-M's `tfm_common_bl2.ld` + TF-M startup (not FSP `fsp.ld`/startup), so **FSP's OFS
      option-setting-memory (OFS0/OFS1 @ 0x0100A1xx) is NOT programmed by our image.** Analysis:
      - System clock is **PLL from the external 24 MHz crystal** (`bsp_clock_cfg.h`: CLOCK_SOURCE=PLL,
        PLL_SOURCE=MAIN_OSC, ÷3 ×25 → 200 MHz), brought up by **runtime** `SystemInit → bsp_clock_init`
        (system.c:295). This does NOT depend on OFS, which is why the board can run without it.
      - BUT the FSP config programs `OFS1 = …|0xF00` → **HOCO enabled @20 MHz at reset** (`BSP_PRV_HOCO_USED=1`).
        HOCOFRQ is **OFS-only (not runtime-writable)**; on an erased chip OFS1 defaults to HOCO disabled.
        Tolerable here (HOCO isn't on the system-clock path) but fragile if anything relies on HOCO@20MHz.
      - OFS0 (watchdog/LVD) + prior state: a chip previously flashed with FSP's OFS retains it (e.g. IWDT
        auto-start could reset us); a truly-erased chip is benign.
      **Robust fix:** include the OFS regions in the BL2 image — add an OFS data section at 0x0100A1xx with
      the RASC-configured OFS0/OFS1 values, or merge FSP's OFS regions into the TF-M BL2 linker script.
      Until then, verify clock/watchdog behaviour on hardware and start from an erased chip.
- [ ] Glob-refactor the BL2 (and NS) `tfm_integration` cmake to select sources from the RASC tree
      (per-module directory globs) instead of hardcoded file lists — kills the drift permanently.
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
- [x] **FIX NS linker regions** — DONE 2026-07-10. `memory_regions.ld` → NS RAM `0x20020000`/0x20000,
      NS flash `0x50400`/0x1F400. Verified: `__Vectors`@0x50400, `g_main_stack`@0x20020000, NS RTT CB
      @0x20020854 (now in NS RAM). NS uses ~20KB of 128KB. Build clean, NS image re-signed.
- [x] **Reconcile the memory map** — DONE. Established flash_layout.h as authoritative (config.cmake
      partition vars are vestigial for ra6m4); aligned config.cmake values + comments to match. See the
      authoritative table above.
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
