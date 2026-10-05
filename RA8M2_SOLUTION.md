# RA8M2 Solution Project — layout, TrustZone boundaries, project requirements

Device: **R7KA8M2JF** on the **EK-RA8M2** (`board.ra8m2ek`) — 1 MB MRAM, 1 MB SRAM, no data
flash, RSIP-E50D, Cortex-M85. FSP 6.7.0-beta0.

Companion docs: `RA6M5_SOLUTION.md` (the port this is derived from), `DESIGN.md` (why — §4 for
the flash backend, §7 for the SAU), `RA6E1_TEMPLATE_CHECKLIST.md` (what a solution must emit).

> **Hardware status: untested.** Every claim below is derived from the generated layout or read
> out of the built images. RA8M2 has never been run on a board — the SAU programming, the FSP
> flash backend and measured boot are statically verified only. Treat the RDPM values as
> needing one careful first provisioning, not as proven.

---

## Two things make RA8M2 different from every other part in this port

**1. MRAM, not flash — and a dual address alias.** `BSP_FEATURE_TZ_NS_OFFSET` is `0x10000000`,
so the same physical MRAM appears twice: secure at `0x02000000`, non-secure at `0x12000000`.
Once RDPM has programmed `CFSAMONA.CFS2`, each alias reaches only its own half. Offsets in the
table below are from `0x02000000`; the non-secure rows sit in the other alias at the same
offset.

**2. `__SAUREGION_PRESENT` is `1`** (it is `0` on RA6M4/RA6E1/RA6M5). With an SAU present but
unprogrammed, Armv8-M attributes every address Secure — the combined SAU/IDAU takes the more
secure of the two — so a secure transaction to the non-secure alias is **refused**. This is why
BL2 here takes its MCUboot flash backend from FSP rather than TF-M: FSP's `flash_area_open()`
programs the SAU from `R_PSCU->CFSAMONA_b.CFS2` and `flash_on_chip_cleanup()` tears it down.
`DEFAULT_MCUBOOT_FLASH_MAP` and `DEFAULT_MCUBOOT_FLASH_BACKEND` are therefore both **OFF** in
`config.cmake`. D073, D076, D079.

---

## Layout

1 MB of MRAM, all of it allocated, in 32 KB blocks
(`RM_MCUBOOT_MRAM_BLOCK_SIZE` = `0x8000` = `FLASH_AREA_IMAGE_SECTOR_SIZE`).

| name | parent | security | offset | size | role |
|---|---|---|---|---|---|
| `RAM_CPU0_S` | RAM | s | 0x0 | 0xE9C00 | secure RAM (935 KB) |
| `RAM_CPU0_C` | RAM | c | 0xE9C00 | 0x400 | NSC RAM (1 KB) |
| `RAM_CPU0_N` | RAM | n | 0xEA000 | 0xEA000 | NS RAM (936 KB) |
| `RAM_BL_CPU0_S` | RAM | s | 0x0 | 0x1200 | BL2 RAM |
| `FLASH_BL_CPU0_S` | MRAM | s | 0x00000 | 0x10000 | BL2 (64 KB) |
| `DF_EMULATION` | MRAM | s | 0x10000 | 0x10000 | ITS + PS + NV counters (64 KB) |
| `__BL_0_S_H` | MRAM | s | 0x20000 | 0x200 | image 0 secondary header |
| `__BL_0_S_I` | MRAM | s | 0x20200 | 0x47E00 | image 0 secondary |
| `__BL_0_S_T` | MRAM | s | 0x68000 | 0x0 | |
| `__BL_0_P_H` | MRAM | s | 0x68000 | 0x200 | image 0 primary header |
| `FLASH_CPU0_S` | MRAM | s | 0x68200 | 0x47A00 | secure code |
| `FLASH_CPU0_C` | MRAM | c | 0xAFC00 | 0x400 | NSC veneers (1 KB) |
| `__BL_0_P_T` | MRAM | s | 0xB0000 | 0x0 | |
| `__BL_1_P_H` | MRAM | n | 0xB0000 | 0x200 | image 1 primary header |
| `FLASH_CPU0_N` | MRAM | n | 0xB0200 | 0x27E00 | NS code |
| `__BL_1_P_T` | MRAM | n | 0xD8000 | 0x0 | |
| `__BL_1_S_H` | MRAM | n | 0xD8000 | 0x200 | image 1 secondary header |
| `__BL_1_S_I` | MRAM | n | 0xD8200 | 0x27E00 | image 1 secondary |
| `__BL_1_S_T` | MRAM | n | 0x100000 | 0x0 | |

In 32 KB units: BL2 2, DF_EMULATION 2, secure slots 9 each, NS slots 5 each — 32 units, no
remainder. `flash_layout.h:190` states the same sum as
`64 K BL2 + 64 K DF_EMULATION + 2 x 288 K secure + 2 x 160 K non-secure = 1024 K`.

**The secure/non-secure split falls at offset `0xB0000`**, the one number the flash driver has
to get right. `cmsis_drivers/Driver_Flash.c` picks the alias from it:

```c
#define MRAM_ADDR(off)                                                   \
    ((uint32_t)(off) +                                                   \
     ((uint32_t)(off) >= MRAM_NS_BOUNDARY ? MRAM_NS_BASE                 \
                                          : (uint32_t)(FLASH_BASE_ADDRESS)))
```

`MRAM_NS_BASE` is `FLASH_BASE_ADDRESS + BSP_FEATURE_TZ_NS_OFFSET` — the family-fixed offset,
deliberately **not** `FLASH_AREA_1_OFFSET`, which would move if the slots were repartitioned
(D074). `MRAM_NS_BOUNDARY` derives from `BSP_PARTITION_FLASH_CPU0_C_START + _SIZE`, so it
follows the generated layout. `ra8m2_layout_checks.c` asserts both aliases agree with FSP's
feature macro, and that every secure area lies below the boundary and both NS areas at or above
it.

Getting this wrong is what produced the first RA8M2 BL2 HardFault: a `memcpy` from `0xb0000`,
missing the `0x02` or `0x12` alias prefix entirely. D073.

**There is no data flash.** ITS, PS and the MCUboot NV counters share `DF_EMULATION`, a 64 KB
MRAM region held deliberately **outside every MCUboot area** so an image update cannot erase
stored assets. NV counters take 2048 B; PS and ITS get about 31,744 B each — roughly 10x the
RA6M5 allocation, which has only 8 KB of real data flash. 64 KB is the smallest size that
splits without a remainder (`flash_layout.h:130`).

---

## TrustZone boundary values for this layout

Programmed once per board with the **Renesas Device Partition Manager**, in KB. Nothing in the
firmware sets them. The RDPM screen takes **six** fields, in this order:

| Field | Value (KB) | Derivation |
|---|---|---|
| Code flash (MRAM) Secure | **703** | secure region ends at `FLASH_CPU0_C_START` = `0xAFC00` = 703 KB |
| Code flash NSC | **1** | `FLASH_CPU0_C_SIZE` = `0x400` |
| Data flash Secure | **0** | `DATA_FLASH_CPU0_S_SIZE` = `0x0` — the part has none |
| SRAM Secure | **935** | `RAM_CPU0_S_SIZE` = `0xE9C00` = 935 KB |
| SRAM NSC | **1** | `RAM_CPU0_C_SIZE` = `0x400` |
| Data flash NSC | **0** | no data flash |

Checks: code flash S + NSC = 704 KB = 22 x 32 ✓ (MRAM block 32 KB).
SRAM S + NSC = 936 KB = 117 x 8 ✓.

Resulting NS regions: 320 KB of MRAM in the non-secure alias from `0x120B0000`, 936 KB of SRAM.

**RDPM erases the part — reflash all three images afterwards.** Every launch configuration must
keep `com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` = **false** (`DESIGN.md` §7.2).

---

## What the e2 projects must provide

Three projects — `ra8m2_gcc_mcuboot`, `ra8m2_gcc_CPU0_secure`, `ra8m2_gcc_CPU0_nonsecure`, and
the `ra8m2_iar_*` equivalents. The `RA6E1_TEMPLATE_CHECKLIST.md` contract applies. RA8M2
specifics:

| Project | Requirement |
|---|---|
| `*_CPU0_secure` | `r_mram`, instance named **`g_mram0`** (not `g_flash0` — this is MRAM) |
| `*_mcuboot` | `r_mram` as `g_mram0`, plus `rm_mcuboot_port` |
| `*_mcuboot` | **Measured Boot enabled** — supplies the boot record BL2 writes |
| all | `BSP_CFG_EARLY_INIT` = 1 |
| all | the partitioning above, with `__BL_*_T` sizes **0** |

**Partition emission order matters.** The generator once produced a 512-byte secure primary slot
because it emitted `__BL_0_S_T` before `__BL_0_P_H`; the fix was ordering, not geometry (D078).
After any repartition, read `Debug/bsp_linker_info.h` back and check that `__BL_0_P_H_START`
equals `__BL_0_S_T_START`.

### Known project-side gaps

| Project | Gap | Fix |
|---|---|---|
| `ra8m2_iar_mcuboot` | **Measured Boot disabled** — the only bootloader project where it is | one checkbox in e2 |
| `ra8m2_iar_CPU0_secure` | `RAM_CPU0_C` is 128 B against GCC's 1 KB | regenerate in RASC; provisioning hazard |

---

## Status

**Builds, all four GCC trees and the IAR trees.** Measured with `arm-none-eabi-size`
(MinSizeRel, `text` only):

| Image | text | Region | Headroom |
|---|---|---|---|
| bl2 | 27,100 B | `0x10000` (64 KB) | 58% free |
| tfm_s | 278,594 B | `0x47A00` (293,376 B) | signed image 293,952 of 294,912 — **960 B spare** |
| tfm_ns | 105,944 B | `0x27E00` (163,328 B) | 35% free |

The secure slot is nearly full. `README.md` §"Freeing space in the secure image" lists what can
be turned off; at 960 B of headroom the PSA Arch logging options cannot be enabled globally here.

**Measured boot is on** (`MCUBOOT_MEASURED_BOOT` + `MCUBOOT_DATA_SHARING` in `config.cmake`) and
statically verified. It had never been enabled anywhere until 2026-10-02, and the attestation
suite cannot detect its absence: with `component_cnt == 0` under the default
`ATTEST_TOKEN_PROFILE_PSA_IOT_1`, `attest_add_all_sw_components()` emits `IAT_NO_SW_COMPONENTS`
and returns success. So a passing attestation run proves nothing either way — read the boot
record at the start of secure RAM instead. D080, D081.

**BL2 takes FSP's MCUboot flash backend** (D079). Five couplings were needed:
`fsp_mcuboot_port.cmake` registers `flash_map.c` by name (not via `fsp_module_glob`, which is
`GLOB_RECURSE` and would pull in `custom_crypto_stacks/`, `os/` and `rm_mcuboot_port.c`);
`__FLASH_MAP_BACKEND_H__` is predefined to suppress TF-M's duplicate header;
`mcuboot_hook_shim.h` supplies the `BOOT_HOOK_FLASH_AREA_CALL` that TF-M's MCUboot lacks; and
`stddef.h`, `fault_injection_hardening.h` and `mcuboot_hook_shim.h` are force-included via
`"SHELL:-include ..."`, because a plain `-include` gets de-duplicated by CMake.
`mcuboot_config.h` is deliberately kept as **TF-M's**, to avoid losing
`MCUBOOT_HW_ROLLBACK_PROT`, which FSP's copy does not define.

**The flash controller is handed over, not shared.** `boot_platform_init()` opens `g_mram0_ctrl`,
and FSP's `flash_area_open()` then opens the same controller and returns −1 on
`FSP_ERR_ALREADY_OPEN` — a bootloader panic. `ra8m2_flash_release_for_mcuboot()` calls
`R_MRAM_Close()` and is the first thing `boot_platform_post_init()` does.

---

## Open items

- **Run it on a board.** Nothing here has been executed. Do the first boot with BL2 logging on,
  and read the boot record back before trusting measured boot.
- **The two project-side gaps above**, both needing RASC rather than a code change.
- **D077 back-ports go the other way.** This part has the generated OFS addresses and 22
  enabled-but-unplaced `#error` guards; RA6M5 and RA6E1 have neither. The open work is bringing
  them up to this part, not changing this one.
- **`config.cmake:90-98` prose is stale** — its `MCUBOOT_ALIGN_VAL 32` justification rests on
  four numbers that have all since changed, and it points at `RA8M2_SOLUTION.md`, which did not
  exist until now (D077).
