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

## 8. OFS (option-setting memory) — BL2 only, per-word segments (the safe way)
OFS **is** emitted into the BL2 image — but placed so it can never brick the part. The root-cause saga
(removed entirely, then re-added correctly) is in §8.4; this is the resulting design.

- **What was lethal:** *not* having OFS in the image, and *not* the OFS values — it was the **linker
  section→segment layout**. The old `ra6m4_bl2.ld` placed the OFS words at absolute addresses in the
  default region, so GNU ld coalesced them into **one PT_LOAD segment** spanning `0x0100A100–0x0100A284`
  with the gaps **zero-filled**. A debugger flashes by program header, so it programmed `0x00000000` into
  the gap words — including **PBPS (`0x0100A1E0`)**, the one-time Permanent Block Protect → permanent lock
  → two bricked boards (§8.4).
- **The fix — exactly as FSP's generated `fsp_gen.ld` does it:** each option word gets its **own,
  exactly-sized `MEMORY` region** in `ra6m4_bl2.ld` (`OPTION_SETTING_OFS0 (r): ORIGIN=0x0100A100,
  LENGTH=0x04`, …) and each `.option_setting_*` section is placed `> its own region`. Distinct regions ⇒
  ld emits a **separate, tiny PT_LOAD segment per word** (4 or 12 bytes) ⇒ **no span, no gap-fill**. A
  debugger writes only the configured words; PBPS is never in a segment. Verified: `readelf -l` shows
  three discrete 4-byte segments (`A100`/`A200`/`A280`), identical to a safe FSP image.
- **Emission:** `bl2_option_setting.c` emits `.option_setting_*` only for words configured in RASC
  (`BSP_CFG_OPTION_SETTING_*`), compiled into the `bl2` executable (not a lib, or the linker wouldn't pull
  it in). Unconfigured words emit nothing → their region stays empty → no segment. This mirrors FSP, whose
  `fsp_gen.ld` only contains entries for configured OFS.
- **BL2 only:** the secure/NS images are MCUboot-signed (imgtool needs a contiguous payload) and must not
  carry OFS; two images programming OFS would also collide.
- **Guard:** [`bringup/check_ofs.py`](bringup/check_ofs.py) is a **brick guard on the segment layout** — it
  fails if any PT_LOAD segment across `0x0100A100–0x0100A2CF` exceeds 12 bytes (i.e. spans/zero-fills gaps).
  Discrete per-word segments pass; the old 0x184 span fails. Run before every flash / in CI.
- **`ra6m4_bl2.ld` stays forked** for the `.ram_noinit` FCLK fix (§8.1) **and** this per-region OFS block.
  ⚠ **Never** collapse the OFS words into one region or place them at absolute addresses in a shared region
  — that reintroduces the gap-filled span. Keep in sync with `fsp_gen.ld`'s per-region pattern on FSP bumps.

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

## 8.2 ⚠ OFS security attribution — `BSP_CFG_CLOCKS_SECURE`

`bsp_mcu_ofs_cfg.h` computes:
```c
OFS1_SEL = 0xFFFFF8F8 | ((BSP_CFG_CLOCKS_SECURE == 0) ? 0xF00 : 0)
```

| `BSP_CFG_CLOCKS_SECURE` | OFS1_SEL | LE bytes |
|---|---|---|
| `1` (correct here) | `0xFFFFF8F8` | `f8f8ffff` |
| `0` (RASC default) | `0xFFFFFFF8` | `f8ffffff` |

OFS1_SEL is a **security-attribution** register: the differing bits (8-10) select whether the
corresponding OFS1 fields are secure or non-secure. BL2 and the secure image own the clocks on this
port, so **`BSP_CFG_CLOCKS_SECURE` must be 1** — set in the vendored `fsp/` snapshot, and **external
RASC projects must set Clocks = Secure in the RASC BSP config**. Fixed in TF-M `7b99ce397`; both
values now match a known-good RA6M4 image byte-for-byte.

> **Scope note (do not repeat an earlier mistake):** this is a misconfiguration, **not** a lockout
> mechanism. OFS1_SEL does not disable debug or lock flash, and option memory is erasable. During
> bring-up this diff was wrongly reported as the cause of a board that would no longer erase; that
> symptom is a DLM/TrustZone permission state — see 8.3. Keep the two separate.

**Process rule that does generalise:** never program OFS values that haven't been diffed against a
known-good image for that device (`arm-none-eabi-objdump -s` on a working ELF). The config macros can
be identical while the emitted words differ. And when reporting such a diff, state whether each value
was **observed in a binary** or **derived from macros** — mixing them silently is how a wrong root
cause gets locked in.

### 8.3 Recovering a "connects but won't erase" board — RDPM GUI Initialize

If the board **connects and reads but refuses erase/program**, the flash is not dead — the device is
in a restricted TrustZone **DLM state** (e.g. NSECSD), where the debugger is limited to non-secure
regions and erasing the secure area (`0x0-0x4F3FF`, where BL2 lives) is refused. RFP over SWD cannot
undo this.

**What works (verified on this bench):** the **Renesas Device Partition Manager GUI → "Initialize
device", connection = J-Link**. Menu: *Run → Renesas Debug Tools → Renesas Device Partition Manager*
in e2 studio or RASC. This drives **J-Link's native RA DLM support over the normal SWD debug
connection** — **no boot-mode jumper**, no RFP. It erases all flash and resets the memory partitions
and DLM state to factory. After it, the reset vector at `0x0` and OFS at `0x0100A100/A200/A280` all
read `0xFFFFFFFF`; DLM state is back to SSD; re-flash normally.

**What does NOT work here (and why the earlier recovery script was wrong):** the RDPM **command-line**
tool (`RenesasDevicePartitionManagerCmd.exe`) reaches the device only through **boot firmware**
(`-bootInterface SCI|SWD`). On the EK-RA6M4 with its on-board J-Link, boot mode is not reachable that
way even with the `J16` (MD) jumper fitted — it fails with *"Unable to retrieve device's boot code"*.
**This was observed on a known-good board too**, so that failure is not evidence of a brick. The CLI
is only useful in a production fixture that actually wires up SCI/USB boot mode. Use the GUI on the
bench. [`bringup/recover_ra6m4.sh`](bringup/recover_ra6m4.sh) now only does read-only J-Link
status + prints the GUI steps.

**On observed OFS1_SEL values (don't re-theorise from these):** three states were seen — erased/factory
`0xFFFFFFFF` (confirmed on a J-Link-erased board), a programmed board reading `0x00000000`, and what
our ELF *writes* (`0xFFFFF8F8`, §8.2). These differ because option-memory bits program `1→0` and are
only reset to `1` by erase; the on-silicon value depends on program/erase history, not just our image.
None of this is a lockout mechanism — see the §8.2 scope note.

**Recoverability guard:** `INITIALIZE` is refused in CM state and is **permanently** disabled by
permanent block protection (PBPS). This port emits only `ofs0` / `ofs1_sec` / `ofs1_sel` — **never**
`bps`/`pbps`/`osis` — which is what keeps recovery possible at all. Do not add those sections without a
very good reason.

### 8.4 The brick — CONFIRMED root cause: OFS words merged into one gap-filled segment

Two EK-RA6M4 boards were permanently bricked. The confirmed cause is the **linker section->segment
layout of the BL2 image**, proven byte-for-byte against a bricked board's config memory.

**Mechanism.** The old `ra6m4_bl2.ld` placed the OFS words (`.option_setting_ofs0/_sec/_sel`) at absolute
addresses in the default output region. GNU `ld` coalesced them into **one PT_LOAD segment** spanning
`0x0100A100-0x0100A284` (`0x184` bytes), with the gaps between the words **zero-filled** in the segment's
file image (`p_filesz == p_memsz == 0x184`). Debuggers (Ozone / J-Link) flash an ELF by **program header**,
so they wrote the whole `0x184` span - zeros included - into option memory. The zero at `0x0100A1E0` is
**PBPS**, the one-time-programmable **Permanent Block Protect Setting** (`0 = protected`, permanent) - so
all covered blocks became permanently erase/write-protected -> RDPM `Initialize` returns `0xDA` -> unrecoverable.

**Byte-exact proof** - the TF-M BL2 segment's contents == the bricked board's config dump:

| addr | value |
|---|---|
| `A100` OFS0 | `ffffffff` |
| `A130` SECMPU / `A1C0` BPS / **`A1E0` PBPS** | **`00000000`** (zero-filled gap) |
| `A200` OFS1_SEC | `fffdffff` |
| `A280` OFS1_SEL | `f8f8ffff` |

**Why the `.srec` never showed it (and misled us for days).** `objcopy -O srec/ihex` is **section-based**:
one record per loadable *section*. The image has only three OFS *sections* (4 bytes each); the gaps belong
to no section, so the SREC has three discrete records and **no gap bytes**. The danger exists only in the
**program-header/segment** view (`readelf -l`, `objcopy -O binary`), which spans the gaps with zeros - and
that is what a debugger flashes. Our long "bricked `.srec` == der `.srec`" comparison was reading the
*section* view (identical) and was blind to the *segment* layout (bricked = one span, der = discrete).

**Why FSP images (and the RA6E1 proxy) are safe.** FSP's generated `fsp_gen.ld` gives each option word its
**own MEMORY region** -> `ld` emits a separate tiny PT_LOAD per word -> no span, no gap-fill. A sacrificial
**RA6E1** (identical config-area map) ran the *whole* process - RDPM boundaries + Ozone flash, even
TZ-provisioned with the RA6M4 boundaries - and stayed healthy (`PBPS = FFFFFFFF`), because its FSP
bootloader has discrete segments. That exoneration (tool, device family, provisioning) is what isolated
the cause to the **image's segment layout**.

**The fix (§8).** `ra6m4_bl2.ld` now uses the FSP per-word-region pattern -> three discrete 4-byte segments
(verified via `readelf -l`). The build-wired guard (§8.5) fails on any spanning segment.

**Detour that was wrong (kept as a warning).** An interim diagnosis blamed `FSPR` / `FAWMON @ 0x407FE0DC`.
That register/feature **does not exist on RA6M4** (`BSP_FEATURE_FLASH_SUPPORTS_ACCESS_WINDOW = 0`) - it is
an RA6M3-class thing. The real lock is **PBPS** (block protection, in the config area); the lifecycle state
is **`DLMMON @ 0x400E002C`** (bricked boards read `SSD` - not a DLM lock). Do not read FAWMON on this die.

**Lessons.** (1) A debugger flashes by **segment**, not the `.srec`/section view - audit `readelf -l`.
(2) Place option words in **per-word regions** so `ld` cannot span+zero-fill them. (3) Do not assert a
hardware cause from a register unconfirmed for the exact die. Evidence: [`bringup/bricking_evidence/`](bringup/bricking_evidence/).

### 8.5 Automatic OFS brick guard — `check_ofs.py`
The guard runs **automatically on every BL2 build**: a `bl2_ofs_guard` target in `ALL` (wired in the port
`CMakeLists.txt`) runs `platform/ext/target/renesas/ra6m4/check_ofs.py` on the linked `bl2` and **fails the
build** if any PT_LOAD segment across `0x0100A100-0x0100A2CF` exceeds 12 bytes - i.e. a gap-filled span
(§8.4). Discrete per-word segments pass. It reads **program headers** (`readelf -l`), not the SREC, because
the SREC is blind to the segment layout (§8.4). A mirror copy in [`bringup/check_ofs.py`](bringup/check_ofs.py)
is for manual runs (`python check_ofs.py <image.elf ...>`; exit 1 = spanning segment). Verified: PASS on the
per-region build, FAIL on the preserved `bl2_BRICKED.elf`.

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
  GDB/Ozone). Flash from an erased chip; program the TZ boundaries (§7) via RFP. **No image carries OFS**
  (§8); option memory is programmed separately by RFP only.

## 13. Open issues / architectural risks — MUST resolve before upstreaming

These are unresolved concerns about **dual ownership of startup and security config between FSP's BSP and
TF-M**. None is the confirmed brick cause (§8.4), but each is a correctness/security risk for the port.

### 13.1 SAU/IDAU config is an empty stub — FSP silently owns it
`target_cfg.c::sau_and_idau_cfg()` is **empty** on RA6M4:
```c
void sau_and_idau_cfg(void) { /* "handled by TF-M's common ARMv8-M isolation framework" */ }
```
But the common framework's *only* SAU action is to **call this stub** (`tfm_hal_isolation_v8m.c:275`), so
from the TF-M side **nothing configures the SAU**. On ST (the reference), `sau_and_idau_cfg()` fully
programs SAU regions from `memory_regions` and **locks** it (`SYSCFG_CSLCKR_LOCKSAU`). On RA6M4 the SAU is
instead configured by **FSP's `R_BSP_SecurityInit()`** (from `SystemInit`, bsp_security.c:280-336), driven
by FSP's `BSP_PARTITION_*` config — a **different source of truth** than TF-M's `region_defs.h`. The stub's
comment is circular and the "RA6M4 has no IDAU" comment is misleading (RA attributes via the RFP-programmed
CFS boundaries). **Fix:** either implement `sau_and_idau_cfg()` from `region_defs.h` like ST, or make the
stub honestly document that FSP owns it *and* reconcile `BSP_PARTITION_*` against `region_defs.h`.

### 13.2 Startup ordering — FSP runs first and wins; TF-M believes it is in control
Boot order per image (secure/BL2):
```
Reset_Handler (startup_ra6m4.c) -> SystemInit() -> R_BSP_SecurityInit()  [FSP: SAU, PSCU/CPSCU periph
   security, clocks, cache]  -> __PROGRAM_START (C runtime) -> main() -> ... -> sau_and_idau_cfg() [STUB]
   -> tfm_hal_isolation (MPU)
```
So **FSP configures the security state before TF-M's `main` even runs**, and TF-M then executes its HAL
*assuming it owns that setup*. Concrete risks from this split:
- **Config-source drift:** FSP SAU/peripheral-security from RASC (`BSP_PARTITION_*`, `BSP_TZ_CFG_PSARB/C/D/E`)
  vs TF-M MPU/isolation from `region_defs.h`. Two files that must agree by hand and can silently diverge on
  any RASC regen or memory-map change.
- **Peripheral security double-config:** FSP sets `PSARB/C/D/E`/`MSSAR` from RASC; TF-M has its own
  peripheral security model (`target_cfg.c`, `tfm_peripherals_def.c`). If they disagree on a peripheral's
  S/NS attribution, behaviour is whichever ran last / whatever isn't re-set.
- **Lock/re-entrancy:** if FSP locks a security register (as ST deliberately does for SAU), later TF-M
  writes fault or are silently dropped.
- **No verification:** some TF-M platforms (an521) run `fih_verify_sau_and_idau_cfg()` as a security
  self-check. RA6M4 cannot — it never set the SAU — so a SAU regression goes undetected.
- **NS transition:** the jump to NS relies on SAU/IDAU NS attribution matching where TF-M placed the NS
  image; that attribution came from FSP's config, not TF-M's.
This is the same class of bug as §8.1 (FSP computing `SystemCoreClock` before the C-runtime zeroed it):
**FSP's BSP assumes it is the sole owner of a standalone FSP TrustZone app; under TF-M it is not.** Decide a
single owner of each security facet and make the other side explicitly defer, with the config reconciled.

### 13.3 One `startup_ra6m4.c` vs ST's three (bl2 / s / ns)
ST ships **three** startup files (`startup_stm32l5xx_{bl2,s,ns}.c`) — each with its own vector table and a
`Reset_Handler` body tailored to the image (the secure one does more setup; NS does not reconfigure
clocks/security). RA6M4 uses **one** `startup_ra6m4.c` compiled three times. The per-image differences are
handled **implicitly by macros** rather than by separate files:
- `startup_ra6m4.c` itself only branches on `__ARM_FEATURE_CMSE == 3` (secure vs non-secure: stack seal,
  `MSPLIM`), not on BL2/S/NS directly.
- The real per-image behaviour lives in **FSP's `SystemInit`** (system.c), which branches heavily on
  `BSP_TZ_NONSECURE_BUILD` / `BSP_TZ_SECURE_BUILD` / `BSP_TZ_CFG_SKIP_INIT` / `BSP_CFG_BOOT_IMAGE` — e.g. the
  NS build **skips** clock/security init because the secure world already did it.
- The 496-entry `__VECTOR_TABLE` is common; per-image handler bodies resolve at link time (weak → each
  image's own implementations), and secure-only vectors (SecureFault) are harmless-but-present in NS.

**This works only if each image is compiled with the correct TZ macros** (`BL2`; `BSP_TZ_SECURE_BUILD` for S;
`BSP_TZ_NONSECURE_BUILD` for NS). It is functionally equivalent to ST's three files but **harder to audit** —
a wrong/missing macro silently gives an image the wrong init path (e.g. an NS build that re-runs secure clock
init, or a secure build that skips it). **Action:** verify the exact TZ macro set passed to each of the three
builds (BL2/S/NS), and document them (RASC_PROJECT_SETUP.md), or split into per-image startups like ST for
auditability before upstreaming.

---
_Maintainer note: when bumping TF-M, re-check §5 (bootutil glue), §7 (veneer macros still honored by the
generated linker), §8 (`ra6m4_bl2.ld` vs the new `tfm_common_bl2.ld`), and §13 (SAU/startup ownership vs the
reference platforms). When bumping FSP, the RASC config (§1) flows through; re-verify clock/flash-geometry
assumptions (§4) and the §13.2 config-source reconciliation._
