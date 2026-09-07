# RA6M4 TF-M Port — Architecture & Design Decisions

Design/rationale record for the Renesas RA6M4 (and forthcoming RA8D2) TF-M port. Written for a
future maintainer: it captures **why** things are the way they are, so the port can be updated
against newer FSP and newer TF-M without re-deriving the reasoning. Day-to-day status, the full
memory map, and the open TODO list live in [TFM_RA6M4_STATUS.md](TFM_RA6M4_STATUS.md); this file is
the stable "decisions" companion.

> Status: **in progress** (updated 2026-08-10). Sections below capture the decisions made so far;
> expand as the port matures and before upstreaming.
>
> **§8 was rewritten on 2026-08-10** after the July hardware bring-up. If you are reading a copy
> where §8 has no subsections, it predates the brick post-mortem and its OFS guidance is unsafe —
> see [MACHINE_HANDOFF.md](MACHINE_HANDOFF.md).

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
- **Boundaries to program (RFP):** code flash S `0x0–0x4F3FF` / NSC `0x4F400–0x4F7FF` / NS `0x50000+`;
  SRAM S `0x20000000–0x2001FFFF` / NS `0x20020000+`; data flash all-secure.

### 7.1 Boundary provisioning — the boundaries are NEVER set by our software
`BSP_FEATURE_TZ_HAS_DLM = 1` on RA6M4/RA6E1, so this block in FSP's `R_BSP_SecurityInit()` is
**compiled out**:

```c
#if 0 == BSP_FEATURE_TZ_HAS_DLM   /* false on RA6M4/RA6E1 -> not compiled */
    R_PSCU->CFSAMONA = ...  R_PSCU->CFSAMONB = ...
    R_PSCU->SSAMONA  = ...  R_PSCU->SSAMONB  = ...  R_PSCU->DFSAMON = ...
#endif
```

`R_BSP_SAUInit()` still runs, but the **SAU only refines the IDAU** — an address is secure if *either*
says so — and `BSP_FEATURE_TZ_NS_OFFSET = 0x00` means there is no separate non-secure alias for code
flash. So IDAU attribution, burned into the device, is the only thing that makes the NS slot
non-secure. An unprogrammed part faults on the S→NS `BLXNS` with **SecureFault / `INVEP`**
(`SCB->SFSR` @ `0xE000EDE4`, bit 0) — the S→NS jump is the first thing that can possibly notice.

**Register granularities differ, and two are coarse.** A layout is only programmable if the sums land
on them:

| Boundary | Register | Granularity |
|---|---|---|
| Code flash S → NSC | `CFSAMONB.CFS1` | 1 KB |
| Code flash NSC → NS | `CFSAMONA.CFS2` | **32 KB** |
| SRAM S → NSC | `SSAMONB.SS1` | 1 KB |
| SRAM NSC → NS | `SSAMONA.SS2` | **8 KB** |
| Data flash S → NS | `DFSAMON.DFS` | 1 KB |

So *Code Secure + Code NSC* must be a multiple of 32 KB, and *SRAM Secure + SRAM NSC* a multiple of
8 KB. Check this when choosing partition sizes in RASC — a layout that fails it cannot be programmed
at all and must be repartitioned, not worked around.

Programmed with the **Renesas Device Partition Manager** (e2 studio → Run → Renesas Debug Tools),
which takes **KB**. Expect it to erase the part and require SSD lifecycle state — re-flash all images
afterwards. Verify by reading `CFSAMONA`/`CFSAMONB` back.

### 7.2 ⚠ Disable the debugger's automatic TZ-boundary programming
e2 studio debug configurations carry:

```xml
<booleanAttribute key="com.renesas.hardwaredebug.arm.jlink.setTZBoundaries" value="false"/>
```

**Default is enabled, and it must be `false` for this port.** The tooling derives the boundaries from
the symbols of the project being launched, and it does not understand a bootloader *and* a secure
image both living in the secure region. Launched against the bootloader — which has no TrustZone
knowledge at all — it marks **everything secure**, silently undoing a correct partition. The next
S→NS jump then fails with the `INVEP` SecureFault above, on a board that was working minutes earlier.

This bites TF-M exactly as hard as the standalone solution: BL2 is precisely such a
TrustZone-unaware bootloader ahead of the secure image. Set the boundaries once with the Partition
Manager and keep this option off in **every** launch configuration.

## 8. The BL2 image: linker, runtime state, and option memory

BL2 is the one image where TF-M's startup model and FSP's expectations collide. All four
sub-decisions below came out of hardware bring-up in July 2026 and cost real boards; treat them
as load-bearing.

### 8.1 `.ram_noinit` and the FCLK / `SystemCoreClock` hazard
TF-M's `Reset_Handler` calls `SystemInit()` (→ `bsp_clock_init()`) **before** `__PROGRAM_START()`
runs the C-runtime init. FSP does not expect that ordering: anything `SystemInit` computes that
lands in `.bss` is zeroed immediately afterwards. `SystemCoreClock` was the casualty —
`R_FLASH_HP_Open` derives FCLK from it, read 0, and failed with `FSP_ERR_FCLK`.

FSP's own mechanism for this is `BSP_CFG_EARLY_INIT`, which places such state in `.ram_noinit`.
Decisions:
- Set **`BSP_CFG_EARLY_INIT = 1`** in the vendored FSP snapshot (and in any external RASC/e2
  project used via `FSP_*_APP_DIR` — this does not flow automatically).

**Which images need it — it is not all three.** The hazard exists only where *TF-M's* startup runs,
because it is TF-M's `Reset_Handler` that inverts FSP's ordering:

| Image | Startup | Needs `BSP_CFG_EARLY_INIT = 1`? |
|---|---|---|
| Secure | TF-M's (`startup_ra6xx.c`) | **Yes** |
| BL2 | TF-M's (`startup_ra6xx.c`) | **Yes** — see below |
| Non-secure | **FSP's own** `startup.c` | **No.** FSP's Reset_Handler does the C-runtime init in the order FSP expects, so nothing is zeroed after `SystemInit` computed it. |

Set on RA6E1 (2026-08-26): secure only. **BL2 is still exposed.** It uses TF-M's startup and it is
the image that actually failed in July: MCUboot → `ARM_Flash_Initialize` → `R_FLASH_HP_Open` reads
`SystemCoreClock` as 0 and returns `FSP_ERR_FCLK`. Nothing restores it on the BL2 path —
`SystemCoreClockUpdate()` lives in `tfm_hal_platform_init()`, which is an SPM hook the **secure**
image calls and BL2 never does. (A comment in the RA6E1 `tfm_hal_platform.c` claims `Driver_Flash.c`
also does it defensively; it does not.)

Two ways to close it, pick one:
1. `BSP_CFG_EARLY_INIT = 1` in the bootloader project too — but that project is shared with the
   standalone e2 bootloader build, so it changes something outside the TF-M port.
2. Override the `__WEAK boot_platform_post_init()` in the port and call `SystemCoreClockUpdate()`
   there. `bl2_main.c` runs it after `boot_platform_init()` and before `boot_go_for_image_id()`
   touches flash, so it is early enough, it is one-time system state at the right layer, and it
   leaves the e2 project untouched. **This is the preferred fix** — it makes BL2 correct whatever
   the RASC config says.

Note that option 2 is *not* the thing rejected below: the rejection is about `ARM_Flash_Initialize`,
a driver entry point re-entered per device, not about a one-shot boot hook.
- Declare `.ram_noinit` **explicitly** in `ra6m4_bl2.ld`: **before `.bss`** (so the prefixed
  `.bss.ram_noinit` variant isn't swallowed by `*(.bss*)`) and **`NOLOAD`** (so it emits no flash
  image and is neither copied nor zeroed), placed **outside** `ADDR(.bss)..SIZEOF(.bss)` so the
  zero table never covers it. As an orphan section it survived only by luck of ld's placement and
  wasted flash.
- Keep the one-time `SystemCoreClockUpdate()` in `tfm_hal_platform_init()`. Not redundant: the
  **secure** image uses TF-M's *generated* linker, which has no `.ram_noinit` rule, so its
  `.ram_noinit` is still an orphan whose placement isn't guaranteed across TF-M versions.
  Rejected: calling it from `ARM_Flash_Initialize` — wrong layer (a driver entry point, re-entered
  per device and on `FSP_ERR_ALREADY_OPEN`) for one-time system state.

Verify: `.ram_noinit` NOBITS, ending exactly where `__bss_start__` begins, with `g_clock_freq` and
`SystemCoreClock` inside it.

### 8.2 `ra6m4_bl2.ld` is the ONE forked linker
A copy of TF-M's `tfm_common_bl2.ld` plus §8.1 and §8.4. Forked because GNU ld `INSERT` cannot
augment a `-T` main script from a second `-T` fragment. Keep it in sync with TF-M on version
bumps. The secure/NS side stays on TF-M's generated linker (§7), unforked.

### 8.3 BL2 lives at the base of flash
`BL2_CODE_START` derives from `FLASH_BASE_ADDRESS`, **not** `S_ROM_ALIAS_BASE`. The latter is the
*secure image* base (`0x20000` when BL2 is on), so it linked the bootloader into the secure slot:
nothing at the reset vector, and the flash step for `tfm_s_signed.bin` landed on top of the
misplaced bootloader. The device never ran BL2 at all — which is why a run of earlier fixes
appeared to change nothing. Verify: `__Vectors` at `0x0` in `bl2.axf`.

### 8.4 OFS (option-setting memory) — BL2 only, DISCRETE regions
OFS (`0x0100A100`–`0x0100A2CC`) is emitted into the **BL2 image only**. Reasons: (a) the secure/NS
images are MCUboot-signed and imgtool needs a **contiguous** payload — OFS is non-contiguous with
code flash; (b) two images programming OFS would collide. FSP's `bsp_linker.c` gates OFS on
`#ifndef BSP_BOOTLOADED_APPLICATION` (bootloader only) for the same reason.

**Implementation:** `bl2_option_setting.c` emits `.option_setting_*` with values from the RASC
config (`BSP_CFG_OPTION_SETTING_*`), compiled straight into the `bl2` executable — *not* a static
lib, since nothing references the OFS symbols and the linker would never pull the object out of an
archive (`KEEP` only helps once linked).

**⚠ The critical decision — one MEMORY region per option group.** The option-setting map is
**sparse**: thirteen register groups holding 92 bytes of real data spread across a 460-byte span.
The 368 bytes between them are other FCU configuration, including the **FSPR permanence word**, and
are not ours to write.

- **Correct** (what FSP's generated `fsp_gen.ld` does, and what we now do): declare thirteen
  discrete `MEMORY` regions, each sized to exactly its group, and assign every section with
  `> OPTION_SETTING_xxx`. ld then emits **one PT_LOAD per group** and physically cannot fill
  between them.
- **Fatal** (what we did until 2026-07-21): bare addressed sections with no `> REGION`
  — `.option_setting_ofs0 0x0100A100 : { ... }`. ld coalesces all thirteen into **one PT_LOAD**
  spanning the full 460 bytes and **zero-fills the gaps**. A debugger loading the ELF writes that
  whole span, clearing FSPR → **the part is permanently bricked**. This destroyed two EK-RA6M4
  boards.

**The zero fill is invisible in the srec.** It lives in the program header, not in any section, and
`objcopy -O srec` emits from sections. This is why the srec-diff approach (the premise of the
"always emit .srec" build change) cannot catch a regression here. The only valid check is:

```
arm-none-eabi-readelf -l bin/bl2.axf
```
Expect small separate LOAD segments (`FileSiz` 0x4 or 0xc) in the `0x0100Axxx` range and **never**
one segment spanning `0x1CC`. Confirm the values match a known-good image before flashing.

**Related:** `BSP_CFG_CLOCKS_SECURE = 1`. `bsp_mcu_ofs_cfg.h` computes
`OFS1_SEL = 0xFFFFF8F8 | ((BSP_CFG_CLOCKS_SECURE == 0) ? 0xF00 : 0)`. With `0`, the clock-related
OFS1 fields are marked **non-secure**; on a TZ part with boundaries programmed that attribution
mismatch can lock out the debug interface. BL2 and the secure image own the clocks, so clocks must
be secure. External RASC projects must set this in the RASC BSP configuration too.

**Note on `bl2.bin`:** because OFS sits at `0x0100Axxx`, `objcopy -O binary` pads `bl2.bin` to
~16.8 MB. **Flash `bl2.hex` or `bl2.srec`, never `bl2.bin`.**

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

## 12. Bring-up
- `fsp_cmake/bringup/` — J-Link flash + RTT scripts. Images are Debug builds (full symbols for
  GDB/Ozone). Flash from an erased chip; program the TZ boundaries (§7) via RFP; OFS (§8) is in `bl2.hex`.

---
_Maintainer note: when bumping TF-M, re-check §5 (bootutil glue), §7 (veneer macros still honored by the
generated linker), and §8 (`ra6m4_bl2.ld` vs the new `tfm_common_bl2.ld`). When bumping FSP, the RASC
config (§1) flows through; re-verify OFS (§8) and clock/flash-geometry assumptions (§4)._
