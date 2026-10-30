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

The scratch block is secure and empty by design. MCUboot is overwrite-only here, so
nothing uses it; `FLASH_AREA_SCRATCH_SIZE` is 0 in `flash_layout.h`. It exists so a later
move to swap-using-scratch does not have to re-partition and re-provision the part. It is
secure because during a swap the scratch holds fragments of the secure image — an
NS-writable scratch would expose and could corrupt it.

Data flash is entirely secure. ITS, PS and the MCUboot NV counters all live there:
NV counters 2048 B, PS 3072 B, ITS 3072 B. `flash_layout.h` splits the partition
proportionally and `#error`s below 4 KB; `PS_MAX_ASSET_SIZE` 512 / `PS_NUM_ASSETS` 5 in
`config_tfm_target.h` are derived from the resulting 1536-byte FS block. Do not give the
NS side a half like the stock template does.

---

## TrustZone boundary values for this layout

Programmed once per board with the Renesas Device Partition Manager, in KB. Nothing in
the firmware sets them. See [DESIGN.md](DESIGN.md) §7.1 for the granularity rules.

| Boundary | Value (KB) | Check |
|---|---|---|
| Code flash Secure | 1150 | S + NSC = 1152 = 36 × 32 ✓ |
| Code flash NSC | 2 | |
| Data flash Secure | 8 | whole device |
| SRAM Secure | 255 | S + NSC = 256 = 32 × 8 ✓ |
| SRAM NSC | 1 | |

Resulting NS regions: 896 KB of code flash from 0x120000, 256 KB of SRAM from 0x20040000.

**RDPM erases the part** — reflash all three images afterwards.

Every launch configuration must keep `setTZBoundaries` `false` for every probe it names, not
only the selected one ([DESIGN.md](DESIGN.md) §7.2).

> The four stock e2 `*_nonsecure Debug_SSD.launch` files carried the `jlink` key as `true` and
> have been deleted. They were e2 output rather than the `*_TFM_*` launches used here, and no
> procedure needed them.
>
> Every shipped launch now carries `false` for every probe it names, not only the selected one,
> so switching probe cannot arm the setting ([D147]).
>
> The two copies under `e2_baseline/` keep `true` deliberately: that directory exists to show
> e2's unmodified output. **Do not launch from it.**
>
> Check before flashing anything unfamiliar:
> `grep -rn "setTZBoundaries" <launch>`

**Dual-bank mode must be off.** The OFS `DUALSEL` word must select linear mode. In dual-bank
mode each bank is 1 MB and the upper half is not at 0x100000, which breaks this layout.
`BSP_FEATURE_FLASH_HP_CF_DUAL_BANK_START` is 0x00200000 on this part.

---

## What the e2 projects must provide

Three projects per toolchain — `ra6m5_gcc_mcuboot`, `ra6m5_gcc_secure`,
`ra6m5_gcc_nonsecure`, and the `ra6m5_iar_*` equivalents. The
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) contract applies. RA6M5-specific
points follow.
All of these were missing in the first `ra6m5_gcc_*` generation. All but the last are now in
place:

| Project | Requirement |
|---|---|
| `ra6m5_gcc_secure` | `r_flash_hp`, instance named `g_flash0` |
| `ra6m5_gcc_secure` | `r_sce` (TRNG backs the PSA external RNG) |
| `ra6m5_gcc_secure` | `BSP_CFG_STACK_MAIN_BYTES` = 0x1000 |
| `ra6m5_gcc_mcuboot` | flash instance named `g_flash0`, not `g_flashRA_NOT_DEFINED` |
| all | the partitioning above, with `__BL_*_T` sizes 0 |
| `ra6m5_gcc_secure`, `ra6m5_gcc_mcuboot` | `BSP_CFG_EARLY_INIT` = 1 — done; both projects emit `((1))`, and a `#error` has enforced it since [D034]. BSP tab → Early BSP Initialization |

The flash instance name is not cosmetic: `cmsis_drivers/Driver_Flash.c` refers to
`g_flash0_ctrl` / `g_flash0_cfg` by name, and those come from the generated
`ra_gen/hal_data.c`.

`BSP_CFG_EARLY_INIT` is load-bearing. TF-M's `Reset_Handler` runs `SystemInit()` before
the C runtime zeroes `.bss`. With early init off, FSP leaves `SystemCoreClock` in `.bss`, so it
is wiped right after `SystemInit()` computed it, `R_FLASH_HP_Open()` derives FCLK = 0 and fails
with `FSP_ERR_FCLK` — BL2 first, since MCUboot opens the flash before anything else. The port
keeps `.ram_noinit` out of `.bss`, but early init is what puts the clock state there. This was
missed on the first RA6M5 hardware run; `ra6m5_layout_checks.c` and
`bl2_option_setting.c` now `#error` on it, so it fails the build instead of the board.

`S_MSP_STACK_SIZE` in `region_defs.h` is `BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` and is
asserted at build time, so the project and the port have to agree. 0x1000 matches RA6E1.

---

## Status

Supported under both toolchains. [TEST_RESULTS.md](TEST_RESULTS.md) is the single record of
what has run on this part and what has not, including the runs whose non-secure half was
reported rather than captured. What the SCE9 accelerates, what is built from software and why,
and what is unavailable are in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2. The
secure-slot space budget is in [CONFIGURATION.md](CONFIGURATION.md) §6.

### Two settings that failed on hardware before they were guarded

Both are now build-time errors rather than board failures, and
[E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) §5 lists every such setting.

- **Early BSP Initialization must be enabled** in the secure and bootloader projects. With it
  off, `SystemCoreClock` is zero after `SystemInit()` and `R_FLASH_HP_Open()` returns
  `FSP_ERR_FCLK`. That was the first hardware failure on this part.
- **AGT0 needs a real interrupt priority in the secure project.** Disabled emits no vector
  entry at all, so the FLIH and SLIH suites cannot raise an interrupt.

### Measured on the built images

Sizes are `text` only, from `arm-none-eabi-size`, at Debug and isolation 1. Do not read them
from `ld --print-memory-usage`, which reports the secure region as full because the veneers are
pinned at its top.

| Image | Used | Slot code region | Headroom |
|---|---|---|---|
| bl2 | 54.2 KB | `0x18000` (96 KB) | 43% free |
| tfm_s | 174.8 KB | `0x7F600` (509.5 KB) | 334.7 KB free |
| tfm_ns | 6.1 KB | `0x6FE00` (447.5 KB) | — |

- The secure image spans `0xA0000` to `0xCBD50`, with the veneers at `0x11F800`: inside the
  signed payload and clear of the MCUboot trailer.
- Signed images pad to exactly 512 KB and 448 KB, the full slots.
- BL2 emits discrete option-memory load segments at `0x0100A100`, `0x0100A200` and
  `0x0100A280`, so the brick guard in [DESIGN.md](DESIGN.md) §8.4 holds on this device.
- The SCE9 TRNG links into `tfm_s`: 28 `HW_SCE_*` symbols, 8.9 KB after `--gc-sections`.
- `ra6m5_layout_checks.c` and the orphan-section check both pass.

### Two FSP pack defects this part exposed

Both are of the shape "an abandoned operation leaves the engine mid-session and wedges every
later user", and both are fixed in the pack the port ships on: `mbedtls_aes_free()` and
`mbedtls_cipher_free()` for CMAC. A third proposed fix, to `mbedtls_aes_crypt_ctr()`, was
reverted because that function is not an FSP API and is unreachable through PSA — the defect
in it is real and is recorded in [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2 as something
no suite here can reach.

---

## Device differences from RA6E1 that the port had to absorb

- Block-protect OFS words are wider. `BPS`, `PBPS` and their `_SEC` / `_SEL` mirrors are
  0x10, not 0xC, because 2 MB of flash has more protectable blocks. The starts are the same.
  **A wrong length here is a brick risk** — the values come from the generated
  `Debug/memory_regions.ld`.
- OSPI. The RA6M5 has `OSPI0_CS0` / `OSPI0_CS1` regions the RA6E1 has not. Nothing in the
  port uses them; they appear in the generated partition list.
- Everything else transfers: same 8 KB / 32 KB flash block geometry, same 128-byte write
  size, same 64-byte data-flash block, same 112-entry vector table, same 13 OFS groups,
  same SCE9 source tree (byte-identical layout).

---

## Open items

- **Toolchain: closed** ([[D046]]). The `ra6m5_iar` solution selects IAR and the IAR leg is
  finished; PSA Arch passes on both toolchains. For a new part, set the solution toolchain to
  IAR before doing the IAR leg, so the flags come from RASC rather than being carried over by
  hand.
- **FSP version drift: closed.** RA6M5 and RA8M2 are both on 6.7.0-beta0. RA6E1 stays on
  6.6.0-rc1 and is reference only.
- CCM associated-data limit. FSP's SCE9 CCM caps associated data at 110 B, and reports the
  overflow as a plain `PSA_ERROR_INVALID_ARGUMENT`. A software fallback above the threshold, or a
  documented limit, would make SCE9 CCM usable from PSA ([[D043]]). The two session-leak fixes are
  already in the pack.
- Open question — acceleration delta. The acceleration this approach gives (FSP's Mbed TLS
  plus FSP's `*_ALT` set) has not been compared with the previous one (ARM's Mbed TLS
  accelerated with the same ALT sources): which operations changed hands, and where the PSA
  core routes differently. To be answered with measurements, not inspection.
