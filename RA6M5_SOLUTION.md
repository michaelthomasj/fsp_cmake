# RA6M5 Solution Project — layout, TrustZone boundaries, project requirements

Device: R7FA6M5BH3CFC on the CK-RA6M5 V2 (`board.ra6m5ckv2`) — 2 MB code flash, 512 KB SRAM,
8 KB data flash, SCE9, Cortex-M33.

Companion docs: [DESIGN.md](DESIGN.md) for why the port is built this way, and
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) for what a solution must emit, which
carries this part's rows.

---

## Layout

2 MB, all of it allocated. Every boundary falls on a 32 KB erase block, which is the
region-1 block size (`BSP_FEATURE_FLASH_HP_CF_REGION1_BLOCK_SIZE`).

| name | parent | security | offset | size | role |
|---|---|---|---|---|---|
| `RAM_CM33_S` | RAM | s | 0x0 | 0x3FC00 | secure RAM (255 KB) |
| `RAM_CM33_C` | RAM | c | 0x3FC00 | 0x400 | NSC RAM |
| `RAM_CM33_N` | RAM | n | 0x40000 | 0x40000 | NS RAM (256 KB) |
| `FLASH_CM33_B` | FLASH | s | 0x0 | 0x18000 | BL2 (96 KB) |
| *scratch* | FLASH | s | 0x18000 | 0x8000 | reserved, see below |
| `__BL_0_S_H` | FLASH | s | 0x20000 | 0x200 | image 0 secondary header |
| `__BL_0_S_I` | FLASH | s | 0x20200 | 0x7FE00 | image 0 secondary |
| `__BL_0_S_T` | FLASH | s | 0xA0000 | 0x0 | |
| `__BL_0_P_H` | FLASH | s | 0xA0000 | 0x200 | image 0 primary header |
| `FLASH_CM33_S` | FLASH | s | 0xA0200 | 0x7F600 | secure code |
| `FLASH_CM33_C` | FLASH | c | 0x11F800 | 0x800 | NSC veneers |
| `__BL_0_P_T` | FLASH | n | 0x120000 | 0x0 | |
| `__BL_1_P_H` | FLASH | n | 0x120000 | 0x200 | image 1 primary header |
| `FLASH_CM33_N` | FLASH | n | 0x120200 | 0x6FE00 | NS code |
| `__BL_1_P_T` | FLASH | n | 0x190000 | 0x0 | |
| `__BL_1_S_H` | FLASH | n | 0x190000 | 0x200 | image 1 secondary header |
| `__BL_1_S_I` | FLASH | n | 0x190200 | 0x6FE00 | image 1 secondary |
| `__BL_1_S_T` | FLASH | n | 0x200000 | 0x0 | |
| `DATA_FLASH_CM33_S` | DATA_FLASH | s | 0x0 | 0x2000 | ITS + PS + NV counters |
| `DATA_FLASH_CM33_N` | DATA_FLASH | n | 0x2000 | 0x0 | |

In 32 KB units: BL2 3, scratch 1, secure slots 16 each, NS slots 14 each — 64 units, no
remainder.

The scratch block is secure and unused (overwrite-only, `FLASH_AREA_SCRATCH_SIZE` 0). It is
reserved so a later move to swap-using-scratch needs no repartition or re-provisioning, and it is
secure because a swap would place secure-image fragments in it.

Data flash is entirely secure. ITS, PS and the MCUboot NV counters all live there:
NV counters 2048 B, PS 3072 B, ITS 3072 B. `flash_layout.h` splits the partition
proportionally and `#error`s below 4 KB; `PS_MAX_ASSET_SIZE` 512 / `PS_NUM_ASSETS` 5 in
`config_tfm_target.h` are derived from the resulting 1536-byte FS block. Do not give the
NS side a half like the stock template does.

---

## TrustZone boundary values for this layout

Program these once per board with the Renesas Device Partition Manager, in KB
([GETTING_STARTED.md](GETTING_STARTED.md) §6). Granularity rules: [DESIGN.md](DESIGN.md) §7.1.

| Boundary | Value (KB) | Check |
|---|---|---|
| Code flash Secure | 1150 | S + NSC = 1152 = 36 × 32 ✓ |
| Code flash NSC | 2 | |
| Data flash Secure | 8 | whole device |
| SRAM Secure | 255 | S + NSC = 256 = 32 × 8 ✓ |
| SRAM NSC | 1 | |
| Data flash NSC | 0 | the whole device is Secure |

Resulting NS regions: 896 KB of code flash from 0x120000, 256 KB of SRAM from 0x20040000.

**Dual-bank mode must be off.** The OFS `DUALSEL` word must select linear mode. In dual-bank
mode each bank is 1 MB and the upper half is not at 0x100000, which breaks this layout.
`BSP_FEATURE_FLASH_HP_CF_DUAL_BANK_START` is 0x00200000 on this part.

---

## What the e2 projects must provide

Three projects per toolchain: `ra6m5_gcc_mcuboot`, `ra6m5_gcc_secure`, `ra6m5_gcc_nonsecure`, and
the `ra6m5_iar_*` equivalents. [E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) applies;
RA6M5 specifics:

| Project | Requirement |
|---|---|
| `ra6m5_gcc_secure` | `r_flash_hp`, instance named `g_flash0` |
| `ra6m5_gcc_secure` | `r_sce` (TRNG backs the PSA external RNG) |
| `ra6m5_gcc_secure` | `BSP_CFG_STACK_MAIN_BYTES` = 0x1000 |
| `ra6m5_gcc_mcuboot` | flash instance named `g_flash0`, not `g_flashRA_NOT_DEFINED` |
| all | the partitioning above, with `__BL_*_T` sizes 0 |
| `ra6m5_gcc_secure`, `ra6m5_gcc_mcuboot` | Early BSP Initialization enabled (`BSP_CFG_EARLY_INIT` = 1; enforced by `#error`) |

The flash instance name is not cosmetic: `cmsis_drivers/Driver_Flash.c` refers to
`g_flash0_ctrl` / `g_flash0_cfg` by name, and those come from the generated
`ra_gen/hal_data.c`.

`S_MSP_STACK_SIZE` in `region_defs.h` is `BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` and is
asserted at build time, so the project and the port must agree.

---

## Status

Supported under both toolchains. Test status: [TEST_RESULTS.md](TEST_RESULTS.md). Accelerated,
software and unavailable crypto: [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2.
Space budget: [CONFIGURATION.md](CONFIGURATION.md) §6.

### Measured on the built images

Debug, isolation 1, flash LOAD bytes. The secure-image budget and how to measure it:
[CONFIGURATION.md](CONFIGURATION.md) §6.

| Image | Used | Region | Spare |
|---|---|---|---|
| bl2 | 57,960 B | `0x18000` (98,304 B) | 40,344 B |
| tfm_s | 323,536 B | 521,728 B | 198,192 B |
| tfm_ns | 6,208 B | 458,240 B | — |

- The veneers are at `0x11F800`, inside the signed payload and clear of the MCUboot trailer;
  signed images pad to the full slots (512 KB, 448 KB).

---

## Device notes

- Block-protect option words (`BPS`, `PBPS` and mirrors) are `0x10` wide on this part. Their
  lengths come from the generated `Debug/memory_regions.ld`; a wrong length is a brick risk.

---

## Open items

- SCE9 CCM caps associated data at 110 B, so CCM is built in software
  ([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2).
