# RA6M4 TF-M Port — Architecture & Design Decisions

Design/rationale record for the Renesas RA6M4 (and forthcoming RA8D2) TF-M port. Written for a
future maintainer: it captures **why** things are the way they are, so the port can be updated
against newer FSP and newer TF-M without re-deriving the reasoning. Day-to-day status, the full
memory map, and the open TODO list live in [TFM_RA6M4_STATUS.md](TFM_RA6M4_STATUS.md); this file is
the stable "decisions" companion.

> Status: **scaffold** (2026-07-13). Sections below capture the decisions made so far; expand as the
> port matures and before upstreaming.

## 0. Goals (these drive every decision below)
1. Upstream the RA6M4 port to the official TF-M repo.
2. Adapt the same design for the **RA8D2** and upstream that too.
3. Keep it **updatable**: users regenerate FSP drivers from newer RASC/FSP releases, and TF-M can be
   bumped to newer versions, with minimal rework.

## 1. Core principle — RASC is the source of config truth; consume, don't fork
- The user generates the base project(s) from **RASC** (Smart Configurator). BSP, clocks, pins,
  drivers, MPU, **OFS**, etc. are configured there and generated as code.
- The TF-M **BL2 / secure / non-secure** builds **consume** that generated code — they do not
  hand-fork it. Mechanism: `FSP_BL2_APP_DIR` / `FSP_S_APP_DIR` / `FSP_NS_APP_DIR` point the build at
  the RASC projects (with an embedded `fsp/` snapshot as fallback default).
- Prefer **TF-M's own config hooks/macros** over copying/forking TF-M files, and **directory globs of
  the RASC tree** (as RASC's own `GeneratedSrc.cmake` does) over hand-maintained file lists. This is
  what keeps "update FSP" and "update TF-M" cheap.
- **Corollary:** whenever a value/section could come from RASC config, source it from there
  (e.g. OFS values from `BSP_CFG_OPTION_SETTING_*`), even if the emitting shim is small.

> **Recreating the RASC projects:** the concrete per-project RASC settings (device, clock tree, modules
> to add, stack/heap, memory regions, and the required post-generation edits) are captured in
> [RASC_PROJECT_SETUP.md](RASC_PROJECT_SETUP.md). This file explains the *why*; that one is the
> *how-to-rebuild-the-inputs* reference.

## 2. Repositories
- `fsp_cmake` — RASC-generated FSP projects (bl2 / s / ns / …) + modular CMake + this doc + status doc
  + bring-up scripts. FSP 6.1.0 / RASC `sc_v2025-07`.
- `trusted-firmware-m` — the port under `platform/ext/target/renesas/ra6m4/`. Base `TF-Mv2.2.0`.

## 3. Memory map — authoritative source
- **`flash_layout.h` + `region_defs.h` are authoritative** for the ra6m4 build (MCUboot and TF-M read
  them). The `FLASH_*_PARTITION_*` cache vars in `config.cmake` are **vestigial** for ra6m4 (only mps3
  platforms consume them) and are kept only for documentation — they must match `flash_layout.h`.
- Layout (1 MB flash, dual-image MCUboot): BL2 `0x0` 128K · S primary `0x20000` 192K · NS primary
  `0x50000` 128K · S secondary `0x70000` 192K · NS secondary `0xA0000` 128K · scratch `0xC0000` 256K.
  RAM 256K: S `0x20000000` 128K · NS `0x20020000` 128K.

## 4. Flash driver geometry (the RA6M4 hardware bug we fixed)
- RA6M4 HP code flash: region 0 (`0x0–0xFFFF`) = 8 KB blocks; **region 1 (`0x10000+`) = 32 KB blocks**.
  All MCUboot-managed slots live in region 1.
- **Decision:** fix the geometry in TF-M's own `Driver_Flash.c` + `flash_layout.h`
  (`FLASH_AREA_IMAGE_SECTOR_SIZE = 0x8000`, `FLASH_HP_BLOCK_SIZE` = REGION1), keeping TF-M's dual-image
  flash_map/area-IDs. **Rejected:** grafting FSP's `rm_mcuboot_port/flash_map.c` — the RASC BL2 project
  is **single-image** (`MCUBOOT_IMAGE_NUMBER 1`, FSP area IDs) and incompatible with TF-M's dual-image
  bootutil; it cascaded into config/`flash_device_base`/linker-symbol conflicts and would not boot.

## 5. MCUboot / BL2
- **Bootutil:** TF-M's downloaded Renesas MCUboot fork. It is byte-identical to the copy RASC ships, and
  the download provides TF-M's build glue (`bootutil/CMakeLists.txt`, `scripts/imgtool.py`) that RASC
  strips. (If pointing `MCUBOOT_PATH` at the RASC copy, that build glue must be supplied.)
- **Signing:** TF-M's default flow, which invokes `${MCUBOOT_PATH}/scripts/imgtool.py` — i.e. RASC's
  imgtool when `MCUBOOT_PATH` is the RASC tree. The RASC `rm_mcuboot_port_sign.py` wrapper is NOT used
  (it's for standalone RASC MCUboot projects).
- **NV rollback counters:** TF-M's `bl2/src/security_cnt.c` (not provided by `rm_mcuboot_port`).

## 6. Crypto
- **Now:** software crypto — TF-M's own mbedcrypto for BL2 image verification (`CRYPTO_HW_ACCELERATOR
  OFF`). FSP's mbedTLS is entangled with the FSP MCUboot config (`bsp_linker_info.h`) and was NOT grafted.
- **Later (TODO):** hardware crypto via SCE9/RSIP. Staged: `mbedtls_user_config.h` (disables the SCE9
  `*_ALT` macros for SW; KEEP `MBEDTLS_ENTROPY_HARDWARE_ALT` — the TRNG stays the entropy source even in
  SW mode). Switching to HW = re-enable the ALT path + isolate the FSP-mbedTLS/FSP-MCUboot-config coupling.

## 7. TrustZone: SAU/IDAU, veneers, NSC
- RA6M4 attributes memory as **contiguous** `[Secure][NSC][Non-secure]` regions, programmed via RFP
  (provisioning). The port programs neither SAU nor the regions in software — attribution is entirely
  what's burned via RFP.
- **Veneers/NSC:** pinned at a **fixed** slot-boundary address `0x4F400` using TF-M's own generated
  linker via `region_defs.h` macros `TFM_LINKER_VENEERS_LOCATION_END` + `TFM_LINKER_VENEERS_START =
  CMSE_VENEER_REGION_START` (both `#ifndef`-overridable). **No custom secure linker** — the
  nordic/laird upstream pattern. Fixed (not end-of-code) so the NSC is stable across firmware updates,
  which matters because RA TZ boundaries are set once at provisioning.
### 7.1 RA6M4 TZ boundary hardware model + alignment rules (from the HW manual)
Code flash is partitioned by two programmed values, **CFS1** and **CFS2**:

| Region | Start | Size |
|---|---|---|
| Code flash secure | `0x00000000` | `CFS1 × 1 KB` |
| Code flash non-secure callable | `CFS1 × 1 KB` | `CFS2 × 32 KB − CFS1 × 1 KB` |
| Code flash non-secure | `CFS2 × 32 KB` | flash size − `CFS2 × 32 KB` |

**Alignment rules that follow (important — do not over-constrain):**
- The secure size / **NSC start is 1 KB-granular** (`CFS1 × 1 KB`) — any whole KB is legal.
- The **Secure→Non-secure boundary is 32 KB-granular** (`CFS2 × 32 KB`).
- ⇒ **Design rule: `Code Secure + Code NSC` must be a multiple of 32 KB**, i.e. the **NS partition start
  must be 32 KB-aligned**. The veneer/NSC start only needs 1 KB alignment.
- This constrains the *memory map* (§3): pick `FLASH_AREA_1_OFFSET` (NS primary) on a 32 KB boundary.
  Carry this rule to the RA8D2 port.

**Our values** — veneers pinned at `0x4F400` (§7), NS partition at `0x50000`:
`CFS1 = 317` (secure `0x0–0x4F3FF`), `CFS2 = 10` (`10 × 32 KB = 0x50000`), NSC size `= 320 − 317 = 3 KB`.
Verified accepted by RFP.

- **Boundaries to program (RFP fields):**

| RFP field | Value |
|---|---|
| Code Secure (KB) | `317` |
| Code NSC (KB) | `3` |
| Data Secure (KB) | `8` (all data flash — ITS/PS/NV) |
| SRAM Secure (KB) | `128` (`0x20000000–0x2001FFFF`; NS from `0x20020000`) |
| SRAM NSC (KB) | `0` (veneers live in code flash) |
| SiP Flash Secure (KB) | `0` (unused on EK-RA6M4) |

## 8. OFS (option-setting memory) — BL2 only
- OFS (`0x0100A100–0x0100A2CF`: OFS0/OFS1/`_SEC`/`_SEL`/BANKSEL/BPS…) is emitted **into the BL2 image
  only**. Reasons: (a) the secure/NS images are MCUboot-signed and imgtool needs a **contiguous**
  payload — OFS is non-contiguous with code flash; (b) two images programming OFS would collide. FSP's
  `bsp_linker.c` already gates OFS on `#ifndef BSP_BOOTLOADED_APPLICATION` (bootloader only).
- **Implementation:** `bl2_option_setting.c` emits `.option_setting_*` with values from the RASC config
  (`BSP_CFG_OPTION_SETTING_*`), compiled straight into the `bl2` executable (not a static lib, or the
  linker wouldn't pull it in). `ra6m4_bl2.ld` places the sections at their fixed addresses.
- **`ra6m4_bl2.ld` is the ONE forked linker** (a copy of `tfm_common_bl2.ld` + OFS). Forked because GNU
  ld `INSERT` cannot augment a `-T` main script from a second `-T` fragment. Keep it in sync with TF-M
  on version bumps. The secure/NS side stays on TF-M's generated linker (§7), unforked.

## 8.1 FSP ↔ TF-M startup-order contract (.ram_noinit / BSP_CFG_EARLY_INIT)
**This bit the first hardware bring-up — read before porting to another RA part.**

TF-M's `Reset_Handler` (startup_ra6m4.c) does:
```
SystemInit();          /* FSP: bsp_clock_init() + SystemCoreClockUpdate() */
__PROGRAM_START();     /* C-runtime init: copy .data, ZERO .bss, then main() */
```
i.e. **FSP's BSP is initialised *before* the C-runtime init**. Any FSP state that lands in `.bss` is
therefore zeroed immediately after FSP computed it. FSP's own contract for this is:
- `BSP_SECTION_NOINIT` → `.ram_noinit` (GCC; `.bss.ram_noinit` where `BSP_UNINIT_SECTION_PREFIX` is `.bss`)
- `BSP_SECTION_EARLY_INIT` → `BSP_PLACE_IN_SECTION(BSP_SECTION_NOINIT)` **only if `BSP_CFG_EARLY_INIT == 1`**

Affected variables: `SystemCoreClock`, `g_clock_freq[]`, `g_protect_counters[]`,
`g_bsp_group_irq_sources[]`.

**Symptom when it goes wrong:** BL2 dies in `boot_platform_init` → `ARM_Flash_Initialize` →
`R_FLASH_HP_Open` with **`FSP_ERR_FCLK`**. `R_FSP_SystemClockHzGet()` is `SystemCoreClock >> divider`;
with `SystemCoreClock == 0` FCLK reads 0, below the 4 MHz minimum. The clock *hardware* is fine
(PLL 200 MHz, FCLK /4 = 50 MHz) — only the cached value was lost.

**How the port fixes it (the FSP-native way):**
1. **`BSP_CFG_EARLY_INIT = 1`** — FSP's own switch for "BSP is initialised early", which is precisely our
   case. It makes `BSP_SECTION_EARLY_INIT` place `SystemCoreClock` et al. in `.ram_noinit`, and calls
   `bsp_init_uninitialized_vars()` early in `SystemInit`. **Set in the vendored `fsp/` snapshot; external
   RASC projects (`FSP_*_APP_DIR`) must set it too** — the port cannot enforce a RASC setting.
2. **Linker (§8):** `ra6m4_bl2.ld` declares `.ram_noinit` explicitly — **before `.bss`** (so a
   `.bss.ram_noinit` variant isn't swallowed by `*(.bss*)`) and **NOLOAD** (no flash image, never
   copied or zeroed), outside `ADDR(.bss)..SIZEOF(.bss)`. Previously it was an *orphan* section ld
   marked `LOAD/CONTENTS` — it survived only by luck.

Verified after enabling both: BL2 `SystemCoreClock` = `0x200004c8`, inside `.ram_noinit`
(`0x200004a0`–`0x2000050f`, `__bss_start__` = `0x20000510`) — safe by construction.

**Do NOT put clock repair in a driver.** An earlier fix called `SystemCoreClockUpdate()` from
`ARM_Flash_Initialize()`; that was the wrong layer (a driver entry point, invoked per flash device and
re-entered on `FSP_ERR_ALREADY_OPEN`) for one-time system state, and it is redundant once 1+2 are in
place. Removed.

**Secure/NS images:** they use TF-M's *generated* linker (§7, unforked), which has no `.ram_noinit`
rule, so `.ram_noinit` remains an **orphan** there (`SystemCoreClock` = `0x2000a038`, before
`__bss_start__` = `0x2000a080` — outside the zeroed region, but by ld's orphan placement rather than by
design, and the orphan is `LOAD/DATA` rather than NOLOAD). For that reason the one-time
`SystemCoreClockUpdate()` in `tfm_hal_platform_init()` is **kept deliberately** as a guard against
placement changing across TF-M versions. If the secure linker is ever forked, give it the same explicit
`.ram_noinit` section and the guard can go.

## 9. Console / logging — SEGGER RTT (switchable)
- `RA6M4_STDOUT_RTT` (default ON): routes TF-M/MCUboot stdout to SEGGER RTT over J-Link (no UART wiring,
  no S/NS peripheral contention). `rtt/rtt_stdout.c` implements TF-M's `stdio_*` backend; the common
  `uart_stdout.c` is disabled. OFF → FSP SCI UART via the untouched `Driver_USART.c`. Each image (BL2/S/NS)
  has its own RTT control block.

## 10. Non-secure app
- FreeRTOS NS app from the RASC `_ns_rtos` project (`FSP_NS_APP_DIR`). Its `memory_regions.ld` was fixed
  to the TF-M NS partition (RAM `0x20020000`, flash `0x50400`) — RASC had generated a standalone layout
  (secure-RAM `0x20002000`) that would have SecureFaulted the S→NS jump.

## 11. Toolchains
- **GNU Arm** (13.2) is the working toolchain today.
- **IAR (and armclang): TODO, required soon.** All linker/OFS/veneer decisions must be expressible for
  IAR (`.icf`) too: an IAR BL2 linker with the OFS sections, and confirmation/porting of the veneer
  macros for TF-M's IAR isolation linker. Design compiler-agnostically from the start (§7/§8).

## 11.1 ⚠ Build gotcha — signed images are NOT produced by a plain `cmake --build`
Bit us on the first bring-up: **a 10-day-old `tfm_s_signed.bin` was being flashed** while `tfm_s.axf`
was current, so none of the fixes were actually on the device.

- The signed images come from `add_custom_command(OUTPUT tfm_s_signed.bin DEPENDS tfm_s_bin ...)`.
  The dependency is on the **target** `tfm_s_bin`, not on the file `tfm_s.bin`, and the custom targets
  are **not reached by the default `all`** target.
- Consequence: `tfm_s.axf`/`tfm_s.bin` relink, but the signing does not re-run — ninja reports
  "no work to do" while `bin/tfm_s_signed.bin` stays stale. Deleting only the copy in `bin/` does not
  help either, because the **intermediate** `<build>/bl2/ext/mcuboot/tfm_s_signed.bin` still satisfies it.

**Always regenerate before flashing:**
```
rm -f <build>/bl2/ext/mcuboot/tfm_*_signed.bin      # if in doubt
cmake --build <build> --target signed_images
```
and sanity-check the timestamps/sizes of `bin/tfm_s_signed.bin` (0x30000) and `bin/tfm_ns_signed.bin`
(0x20000). Worth fixing properly later by making the signing depend on the binary and adding it to `all`.

## 12. Bring-up
- `fsp_cmake/bringup/` — J-Link flash + RTT scripts. Images are Debug builds (full symbols for
  GDB/Ozone). Flash from an erased chip; program the TZ boundaries (§7) via RFP; OFS (§8) is in `bl2.hex`.

---
_Maintainer note: when bumping TF-M, re-check §5 (bootutil glue), §7 (veneer macros still honored by the
generated linker), and §8 (`ra6m4_bl2.ld` vs the new `tfm_common_bl2.ld`). When bumping FSP, the RASC
config (§1) flows through; re-verify OFS (§8) and clock/flash-geometry assumptions (§4)._
