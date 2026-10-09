# Porting this TF-M port to another RA device

**Audience:** someone adding a new RA part to the port.
**Scope:** the TF-M platform directory — `platform/ext/target/renesas/<part>/`. The RASC side is
[RA6E1_TEMPLATE_CHECKLIST.md](RA6E1_TEMPLATE_CHECKLIST.md), cited here rather than repeated.

**The two halves:**

| Half | Where | Covered by |
|---|---|---|
| What the **generated e2 project** must emit | `fsp_cmake/<part>_*/` | [RA6E1_TEMPLATE_CHECKLIST.md](RA6E1_TEMPLATE_CHECKLIST.md) |
| What the **TF-M platform** must supply | `platform/ext/target/renesas/<part>/` | **this document** |

Neither works alone. Do the checklist first — the platform reads the project.

---

## 1. How much is actually new

Measured by comparing the two live ports, normalising the part name away:

| | |
|---|---|
| Files in a platform directory | **60** (`ra8m2`; `ra6m5` has 59) |
| Common to both parts | **59** — the structure is fully regular |
| Only in one | **1** (`<part>_ddsc.c`, RA8M2's DDSC bridge) |
| **≥95% identical — copy and rename** | **31** |
| **<60% similar — must be authored** | **8** |
| In between — copy and adjust | ~20 |

So a port is **eight files of real work**, a dozen of adjustment, and thirty of copying.
`TFM_PLATFORM=renesas/<part>` resolves **by path alone** — there is no registry to add to, and
no upstream file to touch.

**Start by copying the nearest existing part**, not by creating an empty directory:
RA6M5 (Cortex-M33, flash HP, real data flash) or RA8M2 (Cortex-M85, MRAM, no data flash).
Choosing the wrong base costs most of its benefit.

---

## 2. The eight files you must author

Ordered by how part-specific they are, which is also roughly the order of difficulty.

### `flash_layout.h` — 51% similar, 394 lines

**The spine.** Everything downstream derives from it. It must translate the solution's
`BSP_PARTITION_*` symbols into `FLASH_AREA_*_OFFSET/SIZE`, the ITS/PS areas, `FLASH_DEVICE_ID`
and the sector size.

Do **not** invent values. The contract is that the solution owns the layout
([DESIGN.md](DESIGN.md) §1); this file converts, it does not decide.

Two traps with precedent:
- **`FLASH_AREA_IMAGE_SECTOR_SIZE` must match FSP's**, which generates it as
  `RM_MCUBOOT_MRAM_BLOCK_SIZE` in `ra_cfg/mcu-tools/.../mcuboot_config.h`. The port defined
  `0x1000` against FSP's `0x8000` on RA8M2 and produced a layout that only failed on hardware.
- **Slot order is not guaranteed.** On RA8M2 image 0's *secondary* slot sits **below** its
  primary (`0x20000` vs `0x68000`). Read the generated symbols; do not assume ([D100]).

### `cmsis_drivers/Driver_Flash.c` — 40% similar, 553 lines

The CMSIS flash driver over FSP's HAL. **This is where the memory technology shows**: RA6M5 uses
`R_FLASH_HP` with real data flash; RA8M2 uses `R_MRAM` with none, so ITS/PS live in a
`DF_EMULATION` region inside MRAM ([D054]).

Also where erase granularity and `InfoGet` field layout matter — both are FSP internals the port
depends on without a promise, which is why it is listed in
[BRIDGING_FILES.md](BRIDGING_FILES.md).

### `bl2_option_setting.c` — 38% similar, 193 lines ⚠

**The brick hazard. Read [DESIGN.md](DESIGN.md) §8.4 before touching it.**

The option-setting (OFS) words configure the part at reset and some bits are **one-time**. Two
rules, both paid for in hardware:

- **Each OFS group gets its own linker `MEMORY` region** ([D001], [D002]). Coalescing them into
  one region makes the linker gap-fill between words, writing values nobody chose. Two EK-RA6M4
  boards were lost this way.
- **Flash `bl2.elf` or `bl2.hex`, never `bl2.bin`** ([D065]). A flat binary cannot express
  discrete segments.

`check_ofs.py` enforces the region rule at build time. Keep it working for the new part.

### `bl2_boot_hal.c` — 43% similar, 119 lines

BL2's platform hooks. Part-specific content: the **SAU programming** (RA8 only — see §4), the
flash controller handover, and any clock or security setup BL2 needs before MCUboot runs.

### `config_tfm_target.h` — 41% similar, 64 lines

Mostly the PS/ITS asset budget. `PS_NUM_ASSETS` is **per part and capacity-bound**: 5 on RA6M5
(1,536 B PS block) against 155 on RA8M2 (15,872 B). Assert it in `<part>_layout_checks.c`.

### `cpuarch.cmake` — 39% similar, 37 lines

Small but load-bearing: processor, architecture, DSP and FP configuration.

```cmake
set(TFM_SYSTEM_PROCESSOR    cortex-m33)        # or cortex-m85
set(TFM_SYSTEM_ARCHITECTURE armv8-m.main)      # or armv8.1-m.main
set(TFM_SYSTEM_DSP          ON)
set(TFM_SYSTEM_FP           ON)
set(CONFIG_TFM_FP_ARCH      "fpv5-sp-d16")
```

Getting the FP architecture wrong does not fail here; it fails at link with `Error[Lt006]`
naming 195 objects — see [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §4.

### `tfm_peripherals_def.c` — 59% similar, 74 lines

The peripheral and interrupt definitions TF-M needs, including the secure timer used by the
FLIH/SLIH suites.

### `cmake/modules/fsp_flash.cmake` — 47% similar, 30 lines

Which FSP flash driver the part uses. See [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md).

---

## 3. The dozen to copy and adjust

`region_defs.h` (65%), `config.cmake` (74%), `<part>_layout_checks.c` (64%),
`tfm_hal_platform.c` (77%), `<part>_fsp_sections.icf` (60%), `cmake/modules/fsp_bsp.cmake` (71%),
`fsp_sce.cmake` (61%), `tests/tfm_tests_config.cmake` (78%), the two linker scripts, `startup_<part>.c`.

**`region_defs.h` deserves attention despite its similarity.** It carries `BL2_DATA_START`,
`S_DATA_START` and `S_RAM_CODE_SIZE`, and on both parts BL2 and the secure image **share RAM** —
which is why BL2's RTT control block cannot be read after the chainload ([D100]).

**`<part>_layout_checks.c` is where you earn the time back.** It is the `_Static_assert` file that
catches layout mistakes at compile time rather than on silicon. Port every assertion, then add
any the new part needs.

---

## 4. What no file captures

These are decided per part and recorded nowhere the build can check.

| | |
|---|---|
| **RDPM boundary values** | Programmed into the device, not the image. RA8M2 is `703/1/0/935/1/0`. Wrong values are not a build error. **RDPM erases the part** — reflash all three images after changing them. |
| **SAU programming** | Needed only where `__SAUREGION_PRESENT == 1`. That is **1 on RA8, 0 on RA6M4/RA6E1/RA6M5** — the RA6 parts use IDAU alone. An RA8 port without SAU init in `bl2_boot_hal.c` does not boot. |
| **MSAR / clock security** | On RA8, `BSP_CFG_CLOCKS_SECURE (0)` leaves MRAM's MRCPFB non-secure and the first access bus-faults at `0x4013C000`. Worked around with `BSP_TZ_CFG_MSAR=0` pending an e2 generator fix ([D092], [D093]). **Check whether a new RA8 part needs the same.** |
| **Engine capability** | Which RSIP/SCE the part has, and what it can actually do. [D111] is the cautionary example: the RSA-2048 keygen guard is on `BSP_FEATURE_RSIP_*_SUPPORTED`, so a new part inherits whatever that list says about it — and three decision entries got the mechanism wrong before it was read directly. |

---

## 5. Order

```
1. RASC project set                  RA6E1_TEMPLATE_CHECKLIST.md — all three projects,
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

**Steps 4 and 5 belong together.** Writing the layout without the assertions means a wrong
value is found on silicon instead of at compile time, and on this port that has repeatedly meant
a boot failure with no console output.

---

## 6. Verification gates

Do not skip ahead; each catches a different class of mistake.

| Gate | Proves |
|---|---|
| Configure succeeds | `cpuarch.cmake`, `config.cmake`, module wiring |
| All three images link | FP/ABI flags, the module set, section placement |
| No unclaimed-module warnings | every enabled driver is in an image ([ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §5) |
| OFS guard passes | the discrete-region rule — **before flashing** |
| BL2 banner on RTT | BL2 runs. Needs a halt to capture ([D100]) |
| Secure image initialises | SAU, MSAR, clocks, flash driver |
| Full regression suite | the port |
| PSA Arch crypto | the engine. Compare against 62/1/1 (RA8M2) or 63/0/1 (RA6M5) |
| Measured boot read from the record | **not** the attestation suite, which passes with zero components ([D080]) |
| Both toolchains | IAR has produced defects GNU did not, four times ([D083], [D089], [D107], [D108]) |

---

## 7. See also

- [RA6E1_TEMPLATE_CHECKLIST.md](RA6E1_TEMPLATE_CHECKLIST.md) — **the other half**: what the RASC project must emit
- [GETTING_STARTED.md](GETTING_STARTED.md) — build and flash
- [DESIGN.md](DESIGN.md) — §1 config truth, §4 flash geometry, §7 TrustZone, §8.4 OFS
- [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) — the CMake module mechanism
- [CONFIGURATION.md](CONFIGURATION.md) — every knob and its constraints
- [BRIDGING_FILES.md](BRIDGING_FILES.md) — files carrying FSP code that do not move with it
- [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) / [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) — worked examples
