# RA8M2 Solution Project — layout, TrustZone boundaries, project requirements

Device: **R7KA8M2JF** on the **EK-RA8M2** (`board.ra8m2ek`) — 1 MB MRAM, 1 MB SRAM, no data
flash, RSIP-E50D, Cortex-M85. FSP 6.7.0-beta0.

Companion docs: `RA6M5_SOLUTION.md` (the port this is derived from), `DESIGN.md` (why — §4 for
the flash backend, §7 for the SAU), `RA6E1_TEMPLATE_CHECKLIST.md` (what a solution must emit).

> **Hardware status: the full regression passes** (2026-10-06, `ra8m2_TFM_flih_gcc`, banner
> `TF-M v2.2.0+94dbaa08f`). Every secure and non-secure suite, zero failures, including the
> FLIH IRQ tests - the first complete run on this part. That exercised the SAU programming, the
> MRAM dual-alias driver, DF_EMULATION as ITS/PS backing, the RSIP-E50D, measured boot, and the
> RDPM values below. **Still unrun: the IAR trees**, and the three IAR project gaps under
> "Known project-side gaps" remain. DECISIONS D095.

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
| `ra8m2_iar_CPU0_secure` | **no `r_agt` module.** The GCC project has it; this one does not, so the IAR PSA Arch tree (`m2pa`) cannot configure | add Timer (r_agt) with a real Interrupt Priority - not Disabled, which is what makes the interrupt secure on RA. D061 |

### MRAM's MRCPFB must stay Secure (`BSP_TZ_CFG_MSAR`)

**This one stops the boot.** FSP derives the MRAM security attribution from the clocks setting:

```c
/* ra_cfg/fsp_cfg/bsp/bsp_mcu_family_cfg.h */
#ifndef BSP_TZ_CFG_MSAR
#define BSP_TZ_CFG_MSAR (        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 1) : 0U) | /* MREFREQ */        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 3) : 0U) | /* MRCFREQ */        ((BSP_CFG_CLOCKS_SECURE == 0) ? (1U << 4) : 0U) /* MRCPFB */)
#endif
```

With `BSP_CFG_CLOCKS_SECURE (0)` - which is what `ra_gen/bsp_clock_cfg.h` generates - bit 4 is
set, `R_BSP_SecurityInit()` writes it to `R_MRMS->MSAR`, and **MRCPFB becomes non-secure**. The
secure image then faults the first time it programs MRAM: `tfm_plat_otp` writes into
DF_EMULATION, `mram_program_control()` calls `bsp_prv_clear_pfb()`, and
`R_MRMS->MRCPFB = 0x00` from Secure state takes a precise bus error.

```
FATAL ERROR: HardFault        BFSR 0x82 (PRECISERR|BFARVALID)
BFAR 0x4013C000               R_MRMS base - MRCPFB is at offset 0
PC   bsp_prv_clear_pfb        called from mram_program_control
```

**Setting Clocks to Secure in e2 does NOT fix this.** `ra6e1_secure` carries
`<raClockConfiguration security="s">` in `.secure_xml` and still generates
`BSP_CFG_CLOCKS_SECURE (0)` - its `.secure_xml` and `ra_gen/bsp_clock_cfg.h` share a timestamp,
so it was generated that way. The attribute and the macro are not the same knob.

**Believed to be an e2 studio generator defect, and it bites on RA8 parts only** - `MSAR`
exists only where there is MRAM, and RA6's other route through `OFS1_SEL` is closed because
BL2 is built as the flat FSP role (D094). `BSP_TZ_CFG_MSAR` is `#ifndef`-guarded, so
the port supplies `BSP_TZ_CFG_MSAR=0` through `FSP_COMPILE_DEFS` in `ra8m2/CMakeLists.txt` -
all three MRAM registers Secure, which is what this port wants since BL2 and the secure image
own MRAM and the non-secure app never changes MRAM timing.

**This is a temporary workaround and a documented deviation** from "RASC is the source of
config truth" (`DESIGN.md` §1.1). **Remove it** once e2 emits `BSP_CFG_CLOCKS_SECURE (1)` from
the Clocks/Security setting; check `ra_gen/bsp_clock_cfg.h` after a regenerate to tell.

Seen on the first RA8M2 boot, 2026-10-05. **RA6M5 cannot hit this** - it has no MRAM, so no
`MSAR`. The same e2 setting there affects only `LPMSAR` and the clock registers.

---

## Status

**Builds, all four GCC trees and the IAR trees.** Measured with `arm-none-eabi-size`
(MinSizeRel, `text` only):

| Image | text | Region | Headroom |
|---|---|---|---|
| bl2 | 27,100 B | `0x10000` (64 KB) | 58% free |
| tfm_s | 278,594 B | `0x47A00` (293,376 B) | signed payload ends at 294,226 of a 294,912 slot — **670 B spare** |
| tfm_ns | 105,944 B | `0x27E00` (163,328 B) | 35% free |

**PSA Arch suites, GCC, on silicon.** Complete; the IAR trees have never run.

| Suite | RA8M2 (RSIP-E50D) | RA6M5 (SCE9) |
|---|---|---|
| crypto | **62 pass / 1 fail / 1 skip** of 64 | 63 / 0 / 1 |
| attestation | 1 / 0 / 0 | 1 / 0 / 0 |
| storage (ITS + PS) | 11 / 0 / 6 | 11 / 0 / 6 |

The two parts differ by **one test out of 64**: 216, the plaintext RSA-2048 keygen gap under
"Open items". Both skip 252 (deterministic ECDSA, which FSP does not support); the six storage
skips are the optional `psa_ps_create` / `psa_ps_set_extended` APIs TF-M does not implement.
D099.

**The MCUboot upgrade path runs** (`ra8m2_TFM_update_gcc`, 2026-10-08). Both images install
from their secondary slots, and a second reset reports `Swap type: none` - the secondary is
erased, so no re-install. First execution of this path on any part here. D100.

**Slot order is reversed for image 0.** The secure secondary (`0x02020000`) sits **below** the
secure primary (`0x02068000`); image 1 is the usual way round (`0x120B0000` primary,
`0x120D8000` secondary). So `rsp.br_image_off = 0x68000` is the *primary*. Flash rows and any
reading of a `boot_rsp` must account for this. D100.

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

- **RSA-2048 key generation in PLAINTEXT format is unavailable.** PSA Arch crypto test 216
  check 4 returns `PSA_ERROR_NOT_SUPPORTED` (-134). Every other RSA-2048 operation passes.
  E50D generates RSA-2048 keys in **wrapped** format only (`rm_psa_crypto_usage_notes.md`), and
  `rsip_e50d_fsp_cfg.h` sets `PSA_CRYPTO_CFG_RSA_FORMAT` to plaintext, so PSA asks for the one
  format this engine does not offer. RA6M5 passes because `BSP_FEATURE_RSIP_SCE9_SUPPORTED` is
  in the guard in `rsa_alt_process.c`. Changing the format affects RSA import, export and
  storage too, not just generation. D097, D098.
- **Run the IAR trees.** The GCC side is done: full regression, PSA Arch attestation (1/1), and
  measured boot verified from the boot record at `0x22000000` - magic `0x2016`, NSPE 0.0.0 and
  SPE 2.2.0, both SHA-256 measurements equal to the signed images' TLVs (D095, D096). The IAR
  trees build but have never run, and the three project-side gaps below block one of them.
- **The two project-side gaps above**, both needing RASC rather than a code change.
- **D077 back-ports go the other way.** This part has the generated OFS addresses and 22
  enabled-but-unplaced `#error` guards; RA6M5 and RA6E1 have neither. The open work is bringing
  them up to this part, not changing this one.
- **`config.cmake:90-98` prose is stale** — its `MCUBOOT_ALIGN_VAL 32` justification rests on
  four numbers that have all since changed, and it points at `RA8M2_SOLUTION.md`, which did not
  exist until now (D077).
