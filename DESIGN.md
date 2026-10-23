# Renesas RA TF-M Port — Architecture & Design

Design and rationale record for the Renesas RA TF-M port. Written for a future maintainer: it
captures why things are the way they are, so the port can be updated against newer FSP and
newer TF-M without re-deriving the reasoning.

Live parts: RA6M5 and RA8M2. RA6M4 and RA6E1 are in-tree but dormant — both EK-RA6M4 boards
were bricked by the OFS coalescing defect (DECISIONS D002). Sections below are part-neutral
unless they name a part; per-part specifics live in `RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md`
(and `RA6E1_SOLUTION.md` for the dormant part),
and the RA6M4-era documents are under `archive/ra6m4/`.

> This file is the stable companion to `DECISIONS.md`, which is the append-only log of why.
> Where the two disagree, DECISIONS.md is authoritative and carries the date.

## 0. Goals (these drive every decision below)
1. Upstream the RA6M5 and RA8M2 ports to the official TF-M repo.
2. Preserve the user's RASC/e2 configuration — the FSP modules they enabled and the memory
   layout they chose stay as configured; the TF-M build consumes them (§1).
3. Let the user add or remove FSP modules in the secure and non-secure projects and have the
   new files picked up by the TF-M build. The gap — e2 does not emit CMake modules — is bridged
   by documentation rather than by code.
4. Use as much FSP code as possible, so future FSP fixes arrive by updating the pack in
   e2/RASC and regenerating, not by patching this port.

## 1. Core principle — RASC is the source of config truth; consume, don't fork
- The user generates the base project(s) from RASC (Smart Configurator). BSP, clocks, pins,
  drivers, MPU, OFS, etc. are configured there and generated as code.
- The TF-M BL2 / secure / non-secure builds consume that generated code — they do not
  hand-fork it. Mechanism: `FSP_BL2_APP_DIR` / `FSP_S_APP_DIR` / `FSP_NS_APP_DIR` point the build at
  the RASC projects (with an embedded `fsp/` snapshot as fallback default).
- Prefer TF-M's own config hooks/macros over copying/forking TF-M files, and directory globs of
  the RASC tree (as RASC's own `GeneratedSrc.cmake` does) over hand-maintained file lists. This is
  what keeps "update FSP" and "update TF-M" cheap.
- Corollary: whenever a value/section could come from RASC config, source it from there
  (e.g. OFS values from `BSP_CFG_OPTION_SETTING_*`), even if the emitting shim is small.


### 1.1 Documented deviations from the principle

Documented exceptions. Anything not listed here that diverges from RASC is a defect, not a choice.

Image version — TF-M owns it, not FSP. **Do not set `MCUBOOT_IMAGE_VERSION`.**

FSP takes the signed image version from an environment variable. Its
`rm_mcuboot_port_sign.py` (lines 23–36) reads `MCUBOOT_IMAGE_VERSION`, injects
`--version <value>` into the imgtool argv, and errors out if `-v`/`--version` is already present in
the e2 Signing Options > Custom field:

```python
if os.getenv("MCUBOOT_IMAGE_VERSION") is not None:
    if "-v" in sys.argv or "--version" in sys.argv:
        sys.exit("ERROR: Remove -v and --version from Signing Options ...")
    sys.argv.insert(sys.argv.index("sign") + 1, "--version")
    sys.argv.insert(sys.argv.index("sign") + 2, os.getenv("MCUBOOT_IMAGE_VERSION"))
```

This port does not use that script and does not read that variable. Versions come from TF-M's
cache variables, passed to imgtool by `cmake/spe-CMakeLists.cmake`:

| | Variable | Default |
|---|---|---|
| secure | `MCUBOOT_IMAGE_VERSION_S` | `${TFM_VERSION}` — 2.2.0 today |
| non-secure | `MCUBOOT_IMAGE_VERSION_NS` | `0.0.0` |

Both are defined in `bl2/ext/mcuboot/mcuboot_default_config.cmake:72-73` and are overridable per
platform in `config.cmake`, or on the command line.

Why the deviation is accepted. FSP's mechanism is one version for one image, because a
standalone FSP bootloader signs a single application. TF-M signs two images that must be
versioned independently — the secure image tracks the TF-M release, the non-secure image tracks the
application — and the attestation token reports them as separate software components. That is
visible in the boot record: `SPE 2.2.0` alongside `NSPE 0.0.0` ([D081]). One environment variable
cannot express that.

The trap: setting `MCUBOOT_IMAGE_VERSION` in your environment has no effect on a TF-M build
here. **It is ignored silently** — no warning, no error — so the image carries the default
version and the attestation token reports it. If a version is wrong, change
`MCUBOOT_IMAGE_VERSION_S` / `_NS`, not the environment. If you also build the standalone FSP
bootloader project from the same shell, the two take their version from different places and
will not agree unless you set both.


2. `BSP_TZ_CFG_MSAR=0` on RA8M2 - a workaround, not a decision. RA8 parts only.

FSP derives the MRAM Security Attribution register from `BSP_CFG_CLOCKS_SECURE`, which the e2
generator emits as `(0)`, marking `MRCPFB` non-secure. The secure image then bus-faults the
first time it programs MRAM. Setting Clocks to Secure in the e2 Security tab does not
change the generated value - `ra6e1_secure` carries that attribute and still emits `(0)` -
so this is believed to be a generator defect.

The port therefore defines `BSP_TZ_CFG_MSAR=0` in `ra8m2/CMakeLists.txt`. **Remove it when e2
is fixed**; the test is whether `ra_gen/bsp_clock_cfg.h` emits `BSP_CFG_CLOCKS_SECURE (1)`
after a regenerate. D092, D093.

The trap: nothing in the build warns if the generated value later becomes correct - the port's
define keeps winning, silently, and the deviation outlives its reason.
## 2. Repositories
- `fsp_cmake` — RASC-generated FSP projects (bl2 / s / ns / …) + modular CMake + this doc + status doc
  + bring-up scripts. FSP 6.7.0-beta0 ([D045], [D047]); `GETTING_STARTED.md` §2 is the
  authority for tool versions.
- `trusted-firmware-m` — the port under `platform/ext/target/renesas/<part>/`. Base `TF-Mv2.2.0`.

## 3. Memory map — authoritative source
- `flash_layout.h` + `region_defs.h` are authoritative for the build (MCUboot and TF-M read
  them). No `FLASH_*_PARTITION_*` cache variable is set by either live part - only mps3 platforms
  consume them, and the RA6M4-era note that they were "kept for documentation" no longer applies.
- Per-part layouts are deliberately not repeated here (see §7 for why). The 1 MB single-bank
  map this section used to print was RA6M4's and matches neither live part: RA6M5 uses the whole
  2 MB with BL2 at 96 KB, and RA8M2 is MRAM based at `0x02000000`. The authoritative figures live
  in `RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md`, generated from each solution's
  `bsp_linker_info.h`.

## 4. Flash driver geometry
Per-part, and the one place where getting a constant wrong fails only on hardware.

| | RA6M5 | RA8M2 |
|---|---|---|
| Memory | HP code flash | MRAM |
| Block size under the slots | 32 KB (region 1, `0x10000+`; region 0 is 8 KB) | no physical erase block - MRAM's write unit is 32 B and its erase is simulated. 32 KB is FSP's `RM_MCUBOOT_MRAM_BLOCK_SIZE` layout choice, which the port mirrors |
| `FLASH_AREA_IMAGE_SECTOR_SIZE` | `0x8000` | `0x8000` |

The hazard is restating a block size that FSP already generates. `FLASH_AREA_IMAGE_SECTOR_SIZE`
was once `0x1000` in the RA8M2 `flash_layout.h` while FSP's generated `mcuboot_config.h` had it
as `RM_MCUBOOT_MRAM_BLOCK_SIZE` (`0x8000`); slots came out 9.875 sectors long, every build step
accepted it, and it failed on hardware as `BOOT_EFLASH` (D054).

Settled, 2026-10-05 (D091). This section recorded a long argument about whether BL2 should
take its MCUboot flash backend from FSP. The answer is no, and the reasoning is in
`FLASH_MAP_OWNERSHIP.md`:

- MCUboot's porting contract is that the port supplies `flash_map_backend.h` - the struct
  and the `flash_area_*` functions. Zephyr and Mynewt delegate it to the surrounding system,
  so FSP shipping one is idiomatic.
- TF-M occupies that slot, and there is room for exactly one. Its struct carries an extra
  `ARM_DRIVER_FLASH *fa_driver` and its backend dispatches through it.
- `DEFAULT_MCUBOOT_FLASH_MAP=OFF` lets a platform supply the map data, not the backend.
  corstone1000 and rse are the only upstream users and both keep TF-M's struct.
- ST solves the same problem by wrapping STM32Cube HAL behind a CMSIS driver and leaving
  the flag ON. This port does the same with `Driver_FLASH0`/`Driver_FLASH1` over
  `R_FLASH_HP`/`R_MRAM`.

So both live parts use TF-M's map and backend, `DEFAULT_MCUBOOT_FLASH_MAP` is ON, and
`DEFAULT_MCUBOOT_FLASH_BACKEND` no longer exists. RA8M2's SAU programming, which FSP's
`flash_area_open()` had provided, now lives in `bl2_boot_hal.c` with the bounds imported from
FSP's `flash_map.c`.

The layout is unaffected either way - `FLASH_AREA_*_OFFSET/SIZE` derive from
`BSP_PARTITION_*`, so the Solution owns the image layout regardless of backend. Conflating the
two is what made this take three attempts.

## 5. MCUboot / BL2
- Bootutil: TF-M downloads upstream MCUboot (`MCUBOOT_VERSION 6071ceb`). Only the dormant
  ra6m4 overrides this with the Renesas fork (`renesas/mcuboot 2.1.0+renesas.3`). It is not the copy RASC ships, and the
  difference is load-bearing: RASC's `boot_hooks.h` is 287 lines against TF-M's 181, adding
  `BOOT_HOOK_FLASH_AREA_CALL`, `BOOT_HOOK_FIND_SLOT_CALL` and `BOOT_HOOK_GO_CALL_FIH`. Any FSP
  source that calls those hooks would need a shim when built against TF-M's copy. No FSP
  MCUboot source is built any more - `rm_mcuboot_port` is in `FSP_MODULES_NEVER_BUILT` on
  both parts and `mcuboot_hook_shim.h` was deleted with it (DECISIONS D079 for the original
  coupling, D091 for its removal). TF-M's copy also provides build glue
  (`bootutil/CMakeLists.txt`, `scripts/imgtool.py`) that RASC strips; pointing `MCUBOOT_PATH` at
  the RASC tree means supplying that glue yourself.
- Signing: TF-M's default flow, which invokes `${MCUBOOT_PATH}/scripts/imgtool.py` — i.e. RASC's
  imgtool when `MCUBOOT_PATH` is the RASC tree. The RASC `rm_mcuboot_port_sign.py` wrapper is NOT used
  (it's for standalone RASC MCUboot projects).
- NV rollback counters: TF-M's `bl2/src/security_cnt.c` (not provided by `rm_mcuboot_port`).

## 6. Crypto
- Hardware crypto is in place on both parts. `CRYPTO_HW_ACCELERATOR` is ON
  (`ra6m5/config.cmake:127`, `ra8m2/config.cmake:150`), with `CRYPTO_HW_ACCELERATOR_TYPE`
  `renesas/sce9` on RA6M5 and `renesas/rsip_e50d` on RA8M2. BL2 hashes on the engine too.
- Crypto is built from FSP's Mbed TLS overlay, not TF-M's own - `fsp_mbedtls.cmake` FORCEs
  `MBEDCRYPTO_PATH` at the FSP tree ([D042]). The ciphers are reached through FSP's `*_ALT`
  macros ([D036], [D039], [D050]). The "entangled with the FSP MCUboot config" obstacle this
  section used to describe was resolved; FSP's Mbed TLS is grafted.
- CCM stays in software ([D043]). The TRNG stays the entropy source either way, through
  `MBEDTLS_PSA_CRYPTO_EXTERNAL_RNG` (`<part>/mbedtls_extra_config.h`), served by
  `sce_trng.c`. FSP's `MBEDTLS_ENTROPY_HARDWARE_ALT` is left off by design —
  `sce9/mbedtls_accelerator_config.h:78-80` says why: the entropy is already hardware by the
  external-RNG route, and enabling both would stack two paths to the same engine.
- `-DCRYPTO_HW_ACCELERATOR=OFF` returns to TF-M's own mbedcrypto if a comparison is needed.

## 7. TrustZone: SAU/IDAU, veneers, NSC
This is the per-part difference with the widest reach. Both live parts attribute memory through the
IDAU from values burned at provisioning, and the port programs neither the boundaries nor (on
RA6M5) the SAU in software. But RA8M2 has a second address alias and an SAU, and RA6M5 does not:

| | RA6M5 | RA8M2 |
|---|---|---|
| `__SAUREGION_PRESENT` | `0` | `1` |
| `BSP_FEATURE_TZ_NS_OFFSET` | `0x00000000` | `0x10000000` |
| Flash aliases | one | secure `0x02000000`, non-secure `0x12000000` |

The consequence is not cosmetic, but state it precisely. Armv8-M attributes every address Secure
when the SAU is disabled and `SAU_CTRL.ALLNS` is 0 - the reset state. With `ALLNS` set to 1 the
IDAU alone decides, which is the only reason RA6M5 works with zero SAU regions: FSP's
`R_BSP_SecurityInit` writes `SAU->CTRL = SAU_CTRL_ALLNS_Msk` (`bsp_security.c:277`). Replace FSP's
startup and that stops being true. On RA8M2, which has SAU regions, the SAU must mark the
non-secure alias NS so the transaction is issued non-secure, and nothing may touch that alias
until it does. That is why BL2 on RA8M2 programmes the SAU
itself, in `bl2_boot_hal.c` - `bl2_sau_init()` is the first thing `boot_platform_post_init()`
does, with the bounds imported from FSP's `flash_map.c`. It used to arrive as a side effect of
FSP's `flash_area_open()`, which is what [D073]/[D079] describe; [D091] moved both parts onto
TF-M's backend and the SAU programming came with it (§4). Once RDPM has programmed
`CFSAMONA.CFS2`, each alias reaches only its own half.

Attribution itself is entirely what is burned via RFP/RDPM — see §7.1.
- Veneers/NSC: pinned at a fixed address, taken from the generated layout, using TF-M's
  own generated linker via the `region_defs.h` macros `TFM_LINKER_VENEERS_LOCATION_END` and
  `TFM_LINKER_VENEERS_START = CMSE_VENEER_REGION_START` (both `#ifndef`-overridable). No custom
  secure linker — the nordic/laird upstream pattern. Fixed rather than end-of-code so the NSC
  window is stable across firmware updates, which matters because RA TZ boundaries are set once
  at provisioning.
- Boundaries to program: deliberately not listed here. They are per-part, they are RDPM
  input, and a stale copy in a third document is how a board gets provisioned wrong. The owning
  documents are `RA6M5_SOLUTION.md` §"TrustZone boundary values" and `RA8M2_SOLUTION.md`
  (`RA6E1_SOLUTION.md` for the dormant part); all
  derive the values from the generated layout and show the 32 KB / 8 KB block checks. RDPM
  **erases the part** — reflash all three images afterwards.

### 7.1 Boundary provisioning — the boundaries are NEVER set by our software
`BSP_FEATURE_TZ_HAS_DLM = 1` on every RA part this port targets (verified: ra6m4,
ra6e1, ra6m5, ra8m2), so this block in FSP's `R_BSP_SecurityInit()` is
compiled out:

```c
#if 0 == BSP_FEATURE_TZ_HAS_DLM   /* false on all four parts -> not compiled */
    R_PSCU->CFSAMONA = ...  R_PSCU->CFSAMONB = ...
    R_PSCU->SSAMONA  = ...  R_PSCU->SSAMONB  = ...  R_PSCU->DFSAMON = ...
#endif
```

`R_BSP_SAUInit()` still runs, but the SAU only refines the IDAU — an address is secure if either
says so — and, on RA6M5, `BSP_FEATURE_TZ_NS_OFFSET = 0x00` means there is no separate non-secure
alias for code flash. (RA8M2 differs: `TZ_NS_OFFSET` is `0x10000000`, giving the NS alias at
`0x12000000`, and the SAU must be programmed as well - `R_BSP_SAUInit` in the secure image,
`bl2_sau_init()` in BL2. See the §7 table.) So IDAU attribution, burned into the device, is the only thing that makes the NS slot
non-secure. An unprogrammed part faults on the S→NS `BLXNS` with SecureFault / `INVEP`
(`SCB->SFSR` @ `0xE000EDE4`, bit 0) — the S→NS jump is the first thing that can possibly notice.

Register granularities differ, and two are coarse. A layout is only programmable if the sums land
on them:

| Boundary | Register | Granularity |
|---|---|---|
| Code flash S → NSC | `CFSAMONB.CFS1` | 1 KB |
| Code flash NSC → NS | `CFSAMONA.CFS2` | 32 KB |
| SRAM S → NSC | `SSAMONB.SS1` | 1 KB |
| SRAM NSC → NS | `SSAMONA.SS2` | 8 KB |
| Data flash S → NS | `DFSAMON.DFS` | 1 KB |

So Code Secure + Code NSC must be a multiple of 32 KB, and SRAM Secure + SRAM NSC a multiple of
8 KB. Check this when choosing partition sizes in RASC — a layout that fails it cannot be programmed
at all and must be repartitioned, not worked around.

Programmed with the Renesas Device Partition Manager (e2 studio → Run → Renesas Debug Tools),
which takes KB. Expect it to erase the part and require SSD lifecycle state — re-flash all images
afterwards. Verify by reading `CFSAMONA`/`CFSAMONB` back.

### 7.2 ⚠ Disable the debugger's automatic TZ-boundary programming
e2 studio debug configurations carry:

```xml
<booleanAttribute key="com.renesas.hardwaredebug.arm.jlink.setTZBoundaries" value="false"/>
```

**Default is enabled, and it must be `false` for this port.** The tooling derives the boundaries from
the symbols of the project being launched, and it does not understand a bootloader and a secure
image both living in the secure region. Launched against the bootloader — which has no TrustZone
knowledge at all — it marks everything secure, silently undoing a correct partition. The next
S→NS jump then fails with the `INVEP` SecureFault above, on a board that was working minutes earlier.

This affects TF-M as much as the standalone solution: BL2 is such a
TrustZone-unaware bootloader ahead of the secure image. Set the boundaries once with the Partition
Manager and keep this option off in every launch configuration.

## 8. The BL2 image: linker, runtime state, and option memory

BL2 is the one image where TF-M's startup model and FSP's expectations collide. All four
sub-decisions below came out of hardware bring-up in July 2026.

### 8.1 `.ram_noinit` and the FCLK / `SystemCoreClock` hazard
TF-M's `Reset_Handler` calls `SystemInit()` (→ `bsp_clock_init()`) before `__PROGRAM_START()`
runs the C-runtime init. FSP does not expect that ordering: anything `SystemInit` computes that
lands in `.bss` is zeroed immediately afterwards. `SystemCoreClock` was the casualty —
`R_FLASH_HP_Open` derives FCLK from it, read 0, and failed with `FSP_ERR_FCLK`.

FSP's own mechanism for this is `BSP_CFG_EARLY_INIT`, which places such state in `.ram_noinit`.
Decisions:
- Set `BSP_CFG_EARLY_INIT = 1` in the vendored FSP snapshot (and in any external RASC/e2
  project used via `FSP_*_APP_DIR` — this does not flow automatically).

Which images need it: not all three. The hazard exists only where TF-M's startup runs,
because it is TF-M's `Reset_Handler` that inverts FSP's ordering:

| Image | Startup | Needs `BSP_CFG_EARLY_INIT = 1`? |
|---|---|---|
| Secure | TF-M's (`startup_ra6xx.c`) | Yes |
| BL2 | TF-M's (`startup_ra6xx.c`) | Yes — see below |
| Non-secure | FSP's own `startup.c` | No. FSP's Reset_Handler does the C-runtime init in the order FSP expects, so nothing is zeroed after `SystemInit` computed it. |

Set on RA6E1 (2026-08-26): secure only. **BL2 is still exposed.** It uses TF-M's startup and it is
the image that failed in July: MCUboot → `ARM_Flash_Initialize` → `R_FLASH_HP_Open` reads
`SystemCoreClock` as 0 and returns `FSP_ERR_FCLK`. Nothing restores it on the BL2 path —
`SystemCoreClockUpdate()` lives in `tfm_hal_platform_init()`, which is an SPM hook the secure
image calls and BL2 never does. (A comment in the RA6E1 `tfm_hal_platform.c` claims `Driver_Flash.c`
also does it defensively; it does not.)

Closed by option 1, and enforced at build time ([D034]): `BSP_CFG_EARLY_INIT = 1` is required
in the bootloader project as well as the secure one, and `bl2_option_setting.c` plus
`<part>_layout_checks.c` `#error` when it is 0. Option 2 below was rejected -
`bl2_boot_hal.c` contains no `SystemCoreClockUpdate()`. Both are kept for the reasoning:
1. `BSP_CFG_EARLY_INIT = 1` in the bootloader project too — but that project is shared with the
   standalone e2 bootloader build, so it changes something outside the TF-M port.
2. Override the `__WEAK boot_platform_post_init()` in the port and call `SystemCoreClockUpdate()`
   there. `bl2_main.c` runs it after `boot_platform_init()` and before `boot_go_for_image_id()`
   touches flash, so it is early enough, it is one-time system state at the right layer, and it
   leaves the e2 project untouched. This is the preferred fix — it makes BL2 correct whatever
   the RASC config says.

Option 2 is not the thing rejected below: the rejection is about `ARM_Flash_Initialize`,
a driver entry point re-entered per device, not about a one-shot boot hook.
- Declare `.ram_noinit` explicitly in `<part>_bl2.ld`: before `.bss` (so the prefixed
  `.bss.ram_noinit` variant isn't swallowed by `*(.bss*)`) and `NOLOAD` (so it emits no flash
  image and is neither copied nor zeroed), placed outside `ADDR(.bss)..SIZEOF(.bss)` so the
  zero table never covers it. As an orphan section its placement was not guaranteed - it
  survived on ld's default ordering - and it wasted flash.
- Keep the one-time `SystemCoreClockUpdate()` in `tfm_hal_platform_init()`. Not redundant: the
  secure image uses TF-M's generated linker, which has no `.ram_noinit` rule, so its
  `.ram_noinit` is still an orphan whose placement isn't guaranteed across TF-M versions.
  Rejected: calling it from `ARM_Flash_Initialize` — wrong layer (a driver entry point, re-entered
  per device and on `FSP_ERR_ALREADY_OPEN`) for one-time system state.

Verify: `.ram_noinit` NOBITS, ending exactly where `__bss_start__` begins, with `g_clock_freq` and
`SystemCoreClock` inside it.

### 8.2 The forked linker scripts
Each part forks three: `<part>_bl2.ld` (GNU), `<part>_bl2.icf` and `<part>_fsp_sections.icf`
(IAR) — six files across RA6M5 and RA8M2. `<part>_bl2.ld` is a copy of TF-M's
`tfm_common_bl2.ld` plus §8.1 and §8.4; it is forked because GNU ld `INSERT` cannot augment a
`-T` main script from a second `-T` fragment. Keep them in sync with TF-M on version bumps. The
secure side uses TF-M's own generated linker with the `region_defs.h` hooks (plus the
`<part>_fsp_sections.icf` fragment under IAR) - not FSP's; only the non-secure side stays on
FSP's generated script, unforked ([D006], and the §7 statement "no custom secure linker").

### 8.3 BL2 lives at the base of flash
`BL2_CODE_START` derives from the `FLASH_BL` partition start
(`BSP_PARTITION_FLASH_BL_CPU0_S_START`), not `S_ROM_ALIAS_BASE`.

`S_ROM_ALIAS_BASE` is the secure image base — `0xA0000` on RA6M5 (where `0x20000` is the
secure *secondary* slot), `0x02068000` on RA8M2 — so deriving BL2 from it put the ra6m4
bootloader in the secure slot: nothing at the reset vector, and the flash step for
`tfm_s_signed.bin` landed on top of the misplaced bootloader. The device never ran BL2 at all,
which is why a run of earlier fixes appeared to change nothing.

Verify: `__Vectors` sits at the part's flash base in `bl2.axf` — `0x0` on RA6M5,
`0x02000000` on RA8M2.

### 8.4 OFS (option-setting memory) — BL2 only, DISCRETE regions

> Geometry in this section is RA6's (`0x0100A1xx`, thirteen groups). The principle — one
> `MEMORY` region per group, never a coalesced `PT_LOAD` — is part-neutral. The numbers are
> not: RA8M2's option memory is at `0x02C9F040`+ in five disjoint windows with six placed
> groups. The per-part table is at the end of this section; the
> authority for each part is its own `region_defs.h` and `<part>_bl2.ld`.

OFS is emitted into the BL2 image only. Reasons: (a) the secure/NS
images are MCUboot-signed and imgtool needs a contiguous payload — OFS is non-contiguous with
code flash; (b) two images programming OFS would collide. FSP's `bsp_linker.c` gates OFS on
`#ifndef BSP_BOOTLOADED_APPLICATION` (bootloader only) for the same reason.

Implementation: `bl2_option_setting.c` emits `.option_setting_*` with values from the RASC
config (`BSP_CFG_OPTION_SETTING_*`), compiled straight into the `bl2` executable, not a static
lib, since nothing references the OFS symbols and the linker would never pull the object out of an
archive (`KEEP` only helps once linked).

**⚠ The critical decision — one MEMORY region per option group.** The option-setting map is
sparse. On RA6E1/RA6M4: thirteen register groups holding 92 bytes of real data (8 × `0x4`
+ 5 × `0xC`) across a 460-byte span, `0x0100A100`–`0x0100A2CC`, leaving 368 bytes between them.
RA6M5 has the same thirteen groups at the same starts but wider block-protect words —
BPS/PBPS and their `_SEC`/`_SEL` mirrors are `0x10`, not `0xC`, because 2 MB of code flash has
more protectable blocks — so 112 bytes of data across a 464-byte span to `0x0100A2D0`, leaving
352. **A coalesced segment writes every option register in its span, not only the reserved
bytes between them** ([D133]). The bytes between the groups are reserved and the hardware
manual requires that reserved areas are never written; the groups themselves are defined
registers, and two of them are one-time.

- Correct (what FSP's generated `fsp_gen.ld` does, and what the port now does): declare one
  discrete `MEMORY` region per group — thirteen in `ra6m5_bl2.ld`, six in `ra8m2_bl2.ld` —
  each sized to its group, and assign every section with `> OPTION_SETTING_xxx`. ld
  then emits one PT_LOAD per group and physically cannot fill between them.
- Fatal (what the port did until 2026-07-21): bare addressed sections with no `> REGION`
  — `.option_setting_ofs0 0x0100A100 : { ... }`. ld coalesces them all into one PT_LOAD
  spanning every group the image emits, and zero-fills the gaps. A debugger loading
  the ELF writes that whole span across config memory that should have been left alone → **the
  part is bricked**. This destroyed two EK-RA6M4 boards, and no recovery is known.

  The measured numbers, from the bricked image itself (`bringup/bricking_evidence/bl2_BRICKED.elf`,
  [D094]): that BL2 emitted three OFS words - `0x0100A100`, `0x0100A200`, `0x0100A280` - and ld
  produced one `PT_LOAD` of 388 bytes (`0x184`) spanning `0x0100A100`-`0x0100A283`, of which
  376 bytes were zero fill. The 460-byte figure above is the width of the whole sparse map, not
  what any one image spans; do not quote it as the size of the fatal segment. The guard window
  (`0x0100A100`-`0x0100A2CF`) is wider still, because it has to catch any group an image might emit.

  Crossing that span against the part's option map, the fill wrote `0x00` into eight defined
  registers - DUALSEL `0x0100A110`, OFS1 `0x0100A180`, BANKSEL `0x0100A190`, BPS `0x0100A1C0`,
  PBPS `0x0100A1E0`, BANKSEL_SEC `0x0100A210`, BPS_SEC `0x0100A240`, PBPS_SEC `0x0100A260` -
  and into the reserved bytes between them ([D133]). BANKSEL_SEL and BPS_SEL sit above the
  segment and were untouched.

  Which of the eight killed the boards is not established. [D065] named PBPS, and the dump
  confirms PBPS was zeroed, so it is a live candidate rather than a withdrawn one - but seven
  other registers took the same write. [D094] separately disproved FSPR permanence (the
  register is absent on RA6M4) and OFS1_SEL content (byte-identical on a working board).
  Post-brick readback gave `DLMMON = 0x2` = SSD, an open state, not a DLM lock. Do not read
  FAWMON.

**The zero fill is invisible in the srec.** It lives in the program header, not in any section, and
`objcopy -O srec` emits from sections. This is why the srec-diff approach (the premise of the
"always emit .srec" build change) cannot catch a regression here. The only valid check is:

```
arm-none-eabi-readelf -l bin/bl2.axf
```
Expect small separate LOAD segments — on RA6M5, `FileSiz` `0x4` for the word groups and
`0x10` for BPS/PBPS, in `0x0100Axxx`; on RA8M2, `0x4` only, in the five windows below — and
never one segment spanning the whole map. Confirm the values match a known-good image
before flashing.

The build enforces this rather than a reminder to run it. `check_ofs.py` in the TF-M
platform directory runs after every `bl2` and `tfm_s` link and fails the build if any `PT_LOAD`
overlapping the part's option windows exceeds the per-part word limit. It is a hard error with
no opt-out switch — the failure it guards is silent, instant and unrecoverable, so a warning
that scrolls past would be worth nothing. `tfm_s` is checked too and must report CLEAN.

The windows and the limit are per part. **A guard pointed at the wrong window reads as
verification and is worse than none** ([D056]): run against an RA8M2 BL2 carrying six OFS
segments, the RA6-hardcoded version printed "CLEAN (no OFS segments) … safe to flash".
The back-port of the per-part guards to RA6M5 and RA6E1 is still open ([D077]).

| | Windows | Limit | Where |
|---|---|---|---|
| RA6M5, RA6E1, RA6M4 | one: `0x0100A100`–`0x0100A2CF` | `--max-word 0xC` | `ra6m5_add_ofs_check()`, passing `--ra6-default` |
| RA8M2 | five: `0x02C9F040`–`0x02C9F280`, `0x12C9F4C0`–`0x12C9F680`, `0x02E07600`–`0x02E07698`, `0x02E17700`–`0x02E17924`, `0x12E17780`–`0x12E17800` | `--max-word 4` | `ra8m2_add_ofs_check()`, passing five `--region` windows |

Both are functions in the part's `CMakeLists.txt`, cited by name because a comment edit above
them moves their line numbers ([[D129]]).

RA8M2's limit is `4` because `bl2_option_setting.c` places only 4-byte words there —
deliberately tighter than the `0x80` a BPS word would need, to be raised only if BPS/PBPS
are ever placed.
BL2 also passes `--require-segments`, so an empty result fails rather than passing.

> Known tension, not yet resolved. RA6M5's widest defined groups are `0x10`
> (`BPS`/`PBPS` and mirrors, the `OPTION_SETTING_*` block in `region_defs.h`) while its guard limit is `--max-word 0xC`,
> inherited from RA6E1/RA6M4 where those words are `0xC`. It does not fire today because
> RA6M5's `bl2_option_setting.c` places none of them. **Enabling a BPS or PBPS group on RA6M5
> will fail the guard on a correctly linked image** — raise the limit to `0x10` at that point,
> and not before.

The guard is verified against the real artifact rather than assumed to work:
`bringup/bricking_evidence/bl2_BRICKED.elf` is the image that destroyed the boards, and the guard
rejects it with `0x0100A100+388B` — 388 = `0x184`, the span itself. That file is the regression
fixture for this check; do not delete it.

Wired on RA6M5 and RA8M2 (and the two dormant RA6 ports), from a single shared copy at
`platform/ext/target/renesas/common/check_ofs.py`. It is shared because the logic is
part-neutral — it reads program headers against windows passed on the command line — not
because the maps agree; they do not, as the table above shows. RA6M4 and RA6E1 happen to be
byte-identical to each other, and the three per-port copies that existed had already drifted:
the RA6E1 one claimed RA6E1 boards were bricked. One guard, one place, windows per part.

Related, and narrower than it used to read: `bsp_mcu_ofs_cfg.h` computes
`OFS1_SEL = 0xFFFFF8F8 | ((BSP_CFG_CLOCKS_SECURE == 0) ? 0xF00 : 0)` only in its TrustZone-secure
branch. BL2 is built as the flat FSP role, so it takes the `#else` branch and `OFS1_SEL`
carries no `CLOCKS_SECURE` term at all — `FSP_TZ_DEFS_BL2` is empty on both parts. The e2
generator also emits `BSP_CFG_CLOCKS_SECURE (0)` whatever the RASC setting ([D093]), so setting
it in RASC changes nothing here.

[D094] withdrew the `OFS1_SEL` attribution outright: the bricked image carried `0xFFFFF8F8`, the
known-good value, byte-identical to a working board. The real RA8 consequence is the MRAM
Security Attribution register, handled by `BSP_TZ_CFG_MSAR=0` (§1.1).

Because OFS sits at `0x0100Axxx`, a plain `objcopy -O binary` pads
`bl2.bin` to ~16.8 MB, zero-filling the reserved bytes among them — the brick, from an ELF
that passes every check. **Flash `bl2.hex` or `bl2.srec`, never `bl2.bin`.**

Since 2026-09-29 all four ports re-emit the flat binary and verify the result with
`check_ofs.py --check-flat-bin`, so a `.bin` from a current build is safe - 33,388 B on RA6M5
and 27,888 B on RA8M2. The re-emission is address-driven, not name-driven:
`check_ofs.py --emit-safe-bin` walks the program headers, because [D068] found that
`--remove-section=.option_setting*` matches nothing under IAR ILINK, which renames those
sections `P1`/`P7`/`P11` - the pattern silently succeeds and emits the full 16.8 MB brick.
Never reproduce the strip by hand with `objcopy --remove-section`. The rule stands regardless:
**a `.bin` from an older build dir, another toolchain path, or a hand-run `objcopy` can
brick the part**, and it looks identical in a file listing. Size is the only
indication — over ~1 MB means it spans the option memory.

## 9. Console / logging — SEGGER RTT (switchable)
- `<PART>_STDOUT_RTT` (e.g. `RA6M5_STDOUT_RTT`, `RA8M2_STDOUT_RTT`; default ON): routes TF-M/MCUboot stdout to SEGGER RTT over J-Link (no UART wiring,
  no S/NS peripheral contention). `rtt/rtt_stdout.c` implements TF-M's `stdio_*` backend; the common
  `uart_stdout.c` is disabled. OFF → FSP SCI UART via the untouched `Driver_USART.c`. Each image (BL2/S/NS)
  has its own RTT control block.

## 10. Non-secure app
- The live parts build the port's split NSPE (`ns_app`, [D005]) or the `tf-m-tests` suites,
  against `<part>_gcc_nonsecure` / `<part>_gcc_CPU0_nonsecure` as `FSP_NS_APP_DIR`. There is no
  FreeRTOS in either `ns_app`.
- The FreeRTOS `_ns_rtos` arrangement this section used to describe, with its hand-fixed
  `memory_regions.ld`, was RA6M4-era. Per-part NS partition addresses live in the solution
  documents, not here (§7).

## 11. Toolchains
- GNU Arm (arm-none-eabi 13.2) and IAR (10.10.2) are both supported, on both live parts.
  IAR builds BL2, secure and non-secure, and passes the full regression suite at isolation 1, 2
  and 3 on RA6M5 and RA8M2, FLIH IRQ tests included ([D118], [D119], [D123], [D124]). The IAR
  `.icf` BL2 linker with the OFS sections and the veneer macros for TF-M's IAR isolation linker
  are all in place.
- armclang: TODO. No `toolchain_ARMCLANG.cmake` support has been attempted. Keep
  linker/OFS/veneer decisions expressible for a third toolchain (§7/§8).

## 12. Bring-up
- `fsp_cmake/bringup/` — RA6M4/RA6E1-era J-Link flash and RTT scripts, plus the preserved
  bricking evidence. The live parts are flashed through the e2 launch configurations instead,
  and GCC images must be `MinSizeRel` (`CONFIGURATION.md` §1), not Debug. TrustZone boundaries
  are programmed with RDPM (§7.1), not RFP. Historic note follows: images were Debug builds (full symbols for
  GDB/Ozone). Flash from an erased chip; program the TZ boundaries (§7) via RFP; OFS (§8) is in `bl2.hex`.

---
_Maintainer note: when bumping TF-M, re-check §5 (bootutil glue), §7 (veneer macros still honored by the
generated linker), and §8 (`<part>_bl2.ld` vs the new `tfm_common_bl2.ld`). When bumping FSP, the RASC
config (§1) flows through; re-verify OFS (§8) and clock/flash-geometry assumptions (§4)._
