# Porting this TF-M port to another RA device

For adding a new RA part. This document covers the TF-M platform directory,
`platform/ext/target/renesas/<part>/`; what the generated e2 projects must supply is in
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md). Satisfy that first: the platform reads
the projects.

---

## 1. How much is new

A platform directory has about 58 files; RA6M5 and RA8M2 share all but `<part>_ddsc.c` (RA8M2's
DDSC bridge). By line similarity with part names normalised, about 30 can be copied and renamed,
about 20 need adjusting (§3), and 8 must be authored (§2). `TFM_PLATFORM=renesas/<part>` resolves
by path; there is no registry and no upstream file to touch.

Start from the nearer existing part: RA6M5 (Cortex-M33, flash HP, data flash) or RA8M2
(Cortex-M85, MRAM, no data flash).

---

## 2. The eight files you must author

### `flash_layout.h` — 51% similar, 394 lines

The spine. Everything downstream derives from it. It must translate the solution's
`BSP_PARTITION_*` symbols into `FLASH_AREA_*_OFFSET/SIZE`, the ITS/PS areas, `FLASH_DEVICE_ID`
and the sector size.

Convert, do not decide: the solution owns the layout ([DESIGN.md](DESIGN.md) §1).

Two traps with precedent:
- **`FLASH_AREA_IMAGE_SECTOR_SIZE` must match FSP's**, which generates it as
  `RM_MCUBOOT_MRAM_BLOCK_SIZE` on MRAM parts and as
  `BSP_FEATURE_FLASH_HP_CF_REGION1_BLOCK_SIZE` on flash-HP parts such as RA6M5, both in
  `ra_cfg/mcu-tools/.../mcuboot_config.h`. A mismatch fails only on hardware.
- **Slot order is not guaranteed.** On RA8M2 image 0's secondary slot sits below its
  primary (`0x20000` vs `0x68000`). Read the generated symbols; do not assume ([D100]).

### `cmsis_drivers/Driver_Flash.c` — 40% similar, 553 lines

The CMSIS flash driver over FSP's HAL. This is where the memory technology shows: RA6M5 uses
`R_FLASH_HP` with real data flash; RA8M2 uses `R_MRAM` with none, so ITS/PS live in
`DF_EMULATION`. Erase granularity and `InfoGet` layout are FSP internals; see
[FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md).

### `bl2_option_setting.c` — 38% similar, 193 lines ⚠

**The brick hazard. Read [DESIGN.md](DESIGN.md) §8.4 before touching it.**

Each option group needs its own linker `MEMORY` region, and `check_ofs.py` enforces it at build
time; keep the guard working for the new part, with that part's windows. Mechanism:
[DESIGN.md](DESIGN.md) §8.4. Flashing rule: [GETTING_STARTED.md](GETTING_STARTED.md) §6.

### `bl2_boot_hal.c` — 43% similar, 119 lines

BL2's platform hooks. Part-specific content: the SAU programming (RA8 only — see §4) and
the crypto-engine start before MCUboot hashes anything.

### `config_tfm_target.h` — roughly 40% similar

Mostly the PS/ITS asset budget. `PS_NUM_ASSETS` is capacity-bound per part: 5 on both today,
against a computed cap of 5 on RA6M5 (1,536 B PS block) and 155 on RA8M2. Assert it in
`<part>_layout_checks.c`.

### `cpuarch.cmake` — 39% similar, 37 lines

Small but load-bearing: processor, architecture, DSP and FP configuration.

```cmake
set(TFM_SYSTEM_PROCESSOR    cortex-m33)        # or cortex-m85
set(TFM_SYSTEM_ARCHITECTURE armv8-m.main)      # or armv8.1-m.main
set(TFM_SYSTEM_DSP          ON)
set(TFM_SYSTEM_FP           ON)
set(CONFIG_TFM_FP_ARCH      "fpv5-sp-d16")    # "fpv5-d16" on RA8M2 (M85, double precision)
set(CONFIG_TFM_FP_ARCH_ASM  "FPv5_SP")        # "FPv5_D16" on RA8M2
```

Getting the FP architecture wrong does not fail here; it fails at link with `Error[Lt006]`
naming 195 objects — see [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §4.

### `tfm_peripherals_def.c` — 59% similar, 74 lines

The peripheral and interrupt definitions TF-M needs, including the secure timer used by the
FLIH/SLIH suites.

### `cmake/modules/fsp_flash.cmake` — 47% similar, 30 lines

Which FSP flash driver the part uses. See [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md).

---

## 3. Files to copy and adjust

`region_defs.h` (65%), `config.cmake` (74%), `<part>_layout_checks.c` (64%), `tfm_hal_platform.c`
(77%), `<part>_fsp_sections.icf` (60%), `cmake/modules/fsp_bsp.cmake` (71%), `fsp_sce.cmake`
(61%), `tests/tfm_tests_config.cmake` (78%), the two linker scripts, `startup_<part>.c`.

`region_defs.h` deserves attention despite its similarity. It carries `BL2_DATA_START`,
`S_DATA_START` and `S_RAM_CODE_SIZE`; BL2 and the secure image share RAM.

Port every `_Static_assert` in `<part>_layout_checks.c`, then add any the new part needs.

---

## 4. What no file captures

These are decided per part and recorded nowhere the build can check.

| | |
|---|---|
| TrustZone boundary values | Programmed into the device, not the image; wrong values are not a build error. Derive them as the SOLUTION documents do; programming them erases the part ([GETTING_STARTED.md](GETTING_STARTED.md) §6) |
| SAU programming | Needed where `__SAUREGION_PRESENT == 1` (RA8, not RA6). An RA8 port without SAU init in `bl2_boot_hal.c` does not boot |
| MSAR / clock security | On RA8, check whether the new part needs the `BSP_TZ_CFG_MSAR=0` workaround ([RA8M2_SOLUTION.md](RA8M2_SOLUTION.md)) |
| Engine capability | Which RSIP/SCE the part has. Feature guards such as RSA keygen key off `BSP_FEATURE_RSIP_*_SUPPORTED`, so a new part inherits what that list says about it |

---

## 5. Order

```
1. RASC project set                  E2_PROJECT_REQUIREMENTS.md — all three projects,
                                     generated AND BUILT (GETTING_STARTED.md §4)
2. Copy the nearest platform dir     ra6m5 (M33/flash) or ra8m2 (M85/MRAM)
3. cpuarch.cmake + config.cmake      smallest change that makes configure succeed
4. flash_layout.h + region_defs.h    the spine — from BSP_PARTITION_*, never invented
5. <part>_layout_checks.c            port the assertions BEFORE trusting step 4
6. Driver_Flash.c                    the memory technology
7. fsp_*.cmake modules               ADDING_FSP_MODULES.md
8. bl2_boot_hal.c + SAU              RA8 only
9. bl2_option_setting.c + check_ofs  ⚠ the brick hazard — last, and carefully
10. RDPM, then flash                 RDPM erases the part; reflash all three after
```

Do steps 4 and 5 together: without the assertions, a wrong layout value shows up on silicon,
usually as a silent boot failure.

---

## 6. Verification gates

Do not skip ahead; each catches a different class of mistake.

| Gate | Proves |
|---|---|
| Configure succeeds | `cpuarch.cmake`, `config.cmake`, module wiring |
| All three images link | FP/ABI flags, the module set, section placement |
| No unclaimed-module warnings | every enabled driver is in an image ([ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §5) |
| OFS guard passes | the discrete-region rule — **before flashing** |
| BL2 banner on RTT | BL2 runs. Needs a halt to capture |
| Secure image initialises | SAU, MSAR, clocks, flash driver |
| Full regression suite | the port |
| Regression at isolation 2 and 3, not only 1 | the MMIO MPU path does not run at isolation 1 |
| `MPU->TYPE` region count | a successful boot proves only "enough regions" |
| The isolation HAL's compile line | `TFM_ISOLATION_LEVEL` reaches it only if it is compiled into `tfm_spm` |
| L1 + IPC as well as L1 + SFN | exposes faults the shipping configuration does not |
| `-Wundef` on the SPE | an `#if` on an undefined macro silently reads 0 |
| PSA Arch crypto | the engine; compare with [TEST_RESULTS.md](TEST_RESULTS.md) |
| Measured boot read from the boot record | the attestation suite passes with zero components |
| Both toolchains | IAR has produced defects GNU did not |
| `.secure_azone` / `.secure_rzone` diff across the toolchain pair | peripheral security is not in `configuration.xml`, and RASC can drop a peripheral |

---

## 7. See also

[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md),
[GETTING_STARTED.md](GETTING_STARTED.md), [DESIGN.md](DESIGN.md),
[ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md), [CONFIGURATION.md](CONFIGURATION.md),
[FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md); worked examples:
[RA6M5_SOLUTION.md](RA6M5_SOLUTION.md), [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md).
