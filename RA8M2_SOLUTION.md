# RA8M2 Solution Project — layout, TrustZone boundaries, project requirements

Device: R7KA8M2JF on the EK-RA8M2 (`board.ra8m2ek`) — 1 MB MRAM, 1,872 KB SRAM (plus 64 KB ITCM /
64 KB DTCM per core-0 partition), no data flash, RSIP-E50D, Cortex-M85. FSP 6.7.0-beta0.

Companion docs: [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) for the part this one is derived from,
[DESIGN.md](DESIGN.md) §4 for the flash backend and §7 for the SAU, and
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) for what a solution must emit.

> Supported under both toolchains. What has and has not run, including the SLIH suite, which has
> never run on this part: [TEST_RESULTS.md](TEST_RESULTS.md).

---

## Two things make RA8M2 different from every other part in this port

1. MRAM, not flash — and a dual address alias. `BSP_FEATURE_TZ_NS_OFFSET` is `0x10000000`,
so the same physical MRAM appears twice: secure at `0x02000000`, non-secure at `0x12000000`.
Once RDPM has programmed `CFSAMONA.CFS2`, each alias reaches only its own half. Offsets in the
table below are from `0x02000000`; the non-secure rows sit in the other alias at the same
offset.

2. `__SAUREGION_PRESENT` is `1` (0 on RA6M5). Once `CFSAMONA.CFS2` is programmed, the MRAM
   non-secure alias accepts only non-secure transactions, so the SAU must mark that alias NS
   before BL2 touches it.

BL2 does this in `bl2_sau_init()` (`bl2_boot_hal.c`), guarded on `__SAUREGION_PRESENT == 1`, with
the bounds from FSP's `flash_map.c`. Flash backend: [DESIGN.md](DESIGN.md) §5.

---

## Layout

1 MB of MRAM, all of it allocated, in 32 KB blocks
(`RM_MCUBOOT_MRAM_BLOCK_SIZE` = `0x8000` = `FLASH_AREA_IMAGE_SECTOR_SIZE`).

| name | parent | security | offset | size | role |
|---|---|---|---|---|---|
| `RAM_CPU0_S` | RAM | s | 0x0 | 0xE9C00 | secure RAM (935 KB) |
| `RAM_CPU0_C` | RAM | c | 0xE9C00 | 0x400 | NSC RAM (1 KB) |
| `RAM_CPU0_N` | `RAM_NS` | n | 0xEA000 | 0xEA000 | NS RAM (936 KB) |
| `RAM_BL_CPU0_S` | `RAM` | s | 0x0 | 0x1200 | BL2 RAM |
| `FLASH_BL_CPU0_S` | `FLASH` | s | 0x00000 | 0x10000 | BL2 (64 KB) |
| `DF_EMULATION` | `FLASH` | s | 0x10000 | 0x10000 | ITS + PS + NV counters (64 KB) |
| `__BL_0_S_H` | `FLASH` | s | 0x20000 | 0x200 | image 0 secondary header |
| `__BL_0_S_I` | `FLASH` | s | 0x20200 | 0x47E00 | image 0 secondary |
| `__BL_0_S_T` | `FLASH` | s | 0x68000 | 0x0 | |
| `__BL_0_P_H` | `FLASH` | s | 0x68000 | 0x200 | image 0 primary header |
| `FLASH_CPU0_S` | `FLASH` | s | 0x68200 | 0x47A00 | secure code |
| `FLASH_CPU0_C` | `FLASH` | c | 0xAFC00 | 0x400 | NSC veneers (1 KB) |
| `__BL_0_P_T` | `FLASH` | s | 0xB0000 | 0x0 | |
| `__BL_1_P_H` | `FLASH_NS` | n | 0xB0000 | 0x200 | image 1 primary header |
| `FLASH_CPU0_N` | `FLASH_NS` | n | 0xB0200 | 0x27E00 | NS code |
| `__BL_1_P_T` | `FLASH_NS` | n | 0xD8000 | 0x0 | |
| `__BL_1_S_H` | `FLASH_NS` | n | 0xD8000 | 0x200 | image 1 secondary header |
| `__BL_1_S_I` | `FLASH_NS` | n | 0xD8200 | 0x27E00 | image 1 secondary |
| `__BL_1_S_T` | `FLASH_NS` | n | 0x100000 | 0x0 | |

> Two naming systems, and you need both. The name column is
> `bsp_linker_info.h`'s — what the port's CMake and headers consume. The parent column is
> read straight off `<memory parent="...">` in `ra8m2_gcc/solution.xml`, which is the file you
> edit to repartition.
>
> The non-secure regions hang off separate parents (`FLASH_NS`, `RAM_NS`), and some names differ
> outright: BL2 is `FLASH_BL_CPU0_S` in the header and `FLASH_CPU0_B` in the solution; NS code is
> `FLASH_CPU0_N` and `FLASH_NS_CPU0_N`. Map the name before editing.

In 32 KB units: BL2 2, DF_EMULATION 2, secure slots 9 each, NS slots 5 each — 32 units, no
remainder.

The secure/non-secure split is at offset `0xB0000`. `Driver_Flash.c` adds the non-secure alias
(`FLASH_BASE_ADDRESS + BSP_FEATURE_TZ_NS_OFFSET`) to every offset at or above `MRAM_NS_BOUNDARY`,
which derives from `BSP_PARTITION_FLASH_CPU0_C_START + _SIZE` and so follows a repartition;
`ra8m2_layout_checks.c` asserts the split.

There is no data flash. ITS, PS and the MCUboot NV counters share `DF_EMULATION`, a 64 KB
MRAM region held deliberately outside every MCUboot area so an image update cannot erase
stored assets. NV counters take 2048 B; PS and ITS get about 31,744 B each — roughly 10x the
RA6M5 allocation. 64 KB is the smallest size that splits without a remainder.

---

## TrustZone boundary values for this layout

Program these once per board with the Renesas Device Partition Manager, in KB
([GETTING_STARTED.md](GETTING_STARTED.md) §6). The RDPM screen takes six fields

| Field | Value (KB) | Derivation |
|---|---|---|
| Code flash (MRAM) Secure | 703 | secure region ends at `FLASH_CPU0_C_START` = `0xAFC00` = 703 KB |
| Code flash NSC | 1 | `FLASH_CPU0_C_SIZE` = `0x400` |
| Data flash Secure | 0 | `DATA_FLASH_CPU0_S_SIZE` = `0x0` — the part has none |
| SRAM Secure | 935 | `RAM_CPU0_S_SIZE` = `0xE9C00` = 935 KB |
| SRAM NSC | 1 | `RAM_CPU0_C_SIZE` = `0x400` |
| Data flash NSC | 0 | no data flash |

Checks: code flash S + NSC = 704 KB = 22 x 32 ✓ (MRAM block 32 KB).
SRAM S + NSC = 936 KB = 117 x 8 ✓.

Resulting NS regions: 320 KB of MRAM in the non-secure alias from `0x120B0000`, 936 KB of SRAM.

---

## What the e2 projects must provide

Three projects — `ra8m2_gcc_mcuboot`, `ra8m2_gcc_CPU0_secure`, `ra8m2_gcc_CPU0_nonsecure`, and
the `ra8m2_iar_*` equivalents. The
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) contract applies. RA8M2 specifics:

| Project | Requirement |
|---|---|
| `*_CPU0_secure` | `r_mram`, instance named `g_mram0` (not `g_flash0` — this is MRAM) |
| `*_mcuboot` | `r_mram` as `g_mram0`, plus `rm_mcuboot_port` |
| `*_mcuboot` | Measured Boot enabled — supplies the boot record BL2 writes |
| `*_CPU0_secure`, `*_mcuboot` | `BSP_CFG_EARLY_INIT` = 1 (not the NS projects — both have 0 and pass every suite; the port asserts it only for secure and BL2) |
| all | the partitioning above, with `__BL_*_T` sizes 0 |

After any repartition, read `Debug/bsp_linker_info.h` back and check that `__BL_0_P_H_START`
equals `__BL_0_S_T_START`; the generator has emitted them out of order before.

### MRAM's MRCPFB must stay Secure (`BSP_TZ_CFG_MSAR`)

**This one stops the boot.** FSP derives the MRAM security attribution from the clocks setting:

```c
/* ra_cfg/fsp_cfg/bsp/bsp_mcu_family_cfg.h */
#ifndef BSP_TZ_CFG_MSAR
#define BSP_TZ_CFG_MSAR (        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 1) : 0U) | /* MREFREQ */        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 3) : 0U) | /* MRCFREQ */        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 4) : 0U) /* MRCPFB */)
#endif
```

With `BSP_CFG_CLOCKS_SECURE (0)` - which is what `ra_gen/bsp_clock_cfg.h` generates - bit 4 is
set, `R_BSP_SecurityInit()` writes it to `R_MRMS->MSAR`, and MRCPFB becomes non-secure. The
secure image then faults the first time it programs MRAM: `tfm_plat_otp` writes into
DF_EMULATION, `mram_program_control()` calls `bsp_prv_clear_pfb()`, and
`R_MRMS->MRCPFB = 0x00` from Secure state takes a precise bus error.

```
FATAL ERROR: HardFault        BFSR 0x82 (PRECISERR|BFARVALID)
BFAR 0x4013C000               R_MRMS base - MRCPFB is at offset 0
PC   bsp_prv_clear_pfb        called from mram_program_control
```

**Setting Clocks to Secure in e2 does not fix this**: the generated `BSP_CFG_CLOCKS_SECURE` stays
`(0)` whatever the Security tab says.

Believed to be an e2 generator defect; it affects only parts with MRAM. `BSP_TZ_CFG_MSAR` is
`#ifndef`-guarded, so the port supplies `BSP_TZ_CFG_MSAR=0` through `FSP_COMPILE_DEFS` in
`ra8m2/CMakeLists.txt`, making all three MRAM registers secure.

This is a temporary workaround and a documented deviation from "RASC is the source of config
truth" ([DESIGN.md](DESIGN.md) §1.1). **Remove it** once e2 emits `BSP_CFG_CLOCKS_SECURE (1)` from
the Clocks/Security setting; check `ra_gen/bsp_clock_cfg.h` after a regenerate to tell.

RA6M5 has no MRAM and cannot hit this; clock-register security on both parts:
[DESIGN.md](DESIGN.md) §13.3.

---

## Status

Supported under both toolchains. [TEST_RESULTS.md](TEST_RESULTS.md) is the single record of
what has run on this part and what has not, including the one PSA Arch crypto failure and the
skips. Sizes at MinSizeRel (`text` for bl2 and tfm_ns; flash LOAD bytes in the region for tfm_s):

| Image | text | Region | Headroom |
|---|---|---|---|
| bl2 | 27,100 B | `0x10000` (64 KB) | 58% free |
| tfm_s | 216,936 B | `0x47A00` (293,376 B) | 76,440 B |
| tfm_ns | 105,944 B | `0x27E00` (163,328 B) | 35% free |

The signed image always fills the slot; the code budget is the region spare above. Why, and the
cost of each diagnostic: [CONFIGURATION.md](CONFIGURATION.md) §6.

### Four facts about this part that bite

**Slot order is reversed for image 0.** The secure secondary at `0x02020000` sits below the
secure primary at `0x02068000`. Image 1 is the usual way round, `0x120B0000` primary and
`0x120D8000` secondary. So `rsp.br_image_off = 0x68000` is the primary, and anything that
computes a flash row or reads a `boot_rsp` has to account for it.

**The MCUboot upgrade path runs here and only here.** Both images install from their secondary
slots, and a second reset reports `Swap type: none` because the secondary has been erased. It
has never run on RA6M5.

**Measured boot is on, and a passing attestation suite does not prove it works.** With
`component_cnt == 0` under the default token profile, `attest_add_all_sw_components()` emits
`IAT_NO_SW_COMPONENTS` and returns success, so the suite passes either way. Read the boot
record at the start of secure RAM instead.

---

## Open items

- RSA-2048 key generation in plaintext format is unavailable on RSIP-E50D (PSA Arch crypto test
  216); request a wrapped key instead. Details: [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2.
