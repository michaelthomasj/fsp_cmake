# RA6M5 Solution Project — layout, TrustZone boundaries, project requirements

Device: **R7FA6M5BH3CFC** on the **CK-RA6M5 V2** (`board.ra6m5ckv2`) — 2 MB code flash, 512 KB SRAM,
8 KB data flash, SCE9, Cortex-M33.

Companion docs: `RA6E1_SOLUTION.md` (the port this is derived from), `DESIGN.md` (why),
`RA6E1_TEMPLATE_CHECKLIST.md` (what a solution must emit — it applies here unchanged).

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

**The scratch block is SECURE and deliberately empty.** MCUboot is overwrite-only here, so
nothing uses it; `FLASH_AREA_SCRATCH_SIZE` is 0 in `flash_layout.h`. It exists so a later
move to swap-using-scratch does not have to re-partition and re-provision the part. It is
secure because during a swap the scratch holds fragments of the **secure** image — an
NS-writable scratch would expose and could corrupt it.

**Data flash is entirely secure.** ITS, PS and the MCUboot NV counters all live there:
NV counters 2048 B, PS 3072 B, ITS 3072 B. `flash_layout.h` splits the partition
proportionally and `#error`s below 4 KB; `PS_MAX_ASSET_SIZE` 512 / `PS_NUM_ASSETS` 5 in
`config_tfm_target.h` are derived from the resulting 1536-byte FS block. Do not give the
NS side a half like the stock template does.

---

## TrustZone boundary values for this layout

Programmed once per board with the **Renesas Device Partition Manager**, in KB. Nothing in
the firmware sets them. See `DESIGN.md` §7.1 for the granularity rules.

| Boundary | Value (KB) | Check |
|---|---|---|
| Code flash Secure | **1150** | S + NSC = 1152 = 36 × 32 ✓ |
| Code flash NSC | **2** | |
| Data flash Secure | **8** | whole device |
| SRAM Secure | **255** | S + NSC = 256 = 32 × 8 ✓ |
| SRAM NSC | **1** | |

Resulting NS regions: 896 KB of code flash from 0x120000, 256 KB of SRAM from 0x20040000.

RDPM erases the part — reflash all three images afterwards. Every launch configuration must
keep `com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` = **false** (`DESIGN.md` §7.2).

**Dual-bank mode must be off.** The OFS `DUALSEL` word must select linear mode. In dual-bank
mode each bank is 1 MB and the upper half is not at 0x100000, which breaks this layout.
`BSP_FEATURE_FLASH_HP_CF_DUAL_BANK_START` is 0x00200000 on this part.

---

## What the e2 projects must provide

Three projects, as on RA6E1 — `ra6m5_mcuboot`, `ra6m5_secure`, `ra6m5_nonsecure`. The
`RA6E1_TEMPLATE_CHECKLIST.md` contract applies unchanged. RA6M5-specific points, all of
them learned from the first `ra6m5_gcc_*` generation:

All of these were missing in the first `ra6m5_gcc_*` generation. All but the last are now in
place:

| Project | Requirement |
|---|---|
| `ra6m5_gcc_secure` | `r_flash_hp`, instance named **`g_flash0`** |
| `ra6m5_gcc_secure` | `r_sce` (TRNG backs the PSA external RNG) |
| `ra6m5_gcc_secure` | `BSP_CFG_STACK_MAIN_BYTES` = 0x1000 |
| `ra6m5_gcc_mcuboot` | flash instance named **`g_flash0`**, not `g_flashRA_NOT_DEFINED` |
| all | the partitioning above, with `__BL_*_T` sizes **0** |
| `ra6m5_gcc_secure`, `ra6m5_gcc_mcuboot` | **`BSP_CFG_EARLY_INIT` = 1** — still 0; BSP tab → Early BSP Initialization |

The flash instance name is not cosmetic: `cmsis_drivers/Driver_Flash.c` refers to
`g_flash0_ctrl` / `g_flash0_cfg` by name, and those come from the generated
`ra_gen/hal_data.c`.

**`BSP_CFG_EARLY_INIT` is load-bearing.** TF-M's `Reset_Handler` runs `SystemInit()` before
the C runtime zeroes `.bss`. With early init off, FSP leaves `SystemCoreClock` in `.bss`, so it
is wiped right after `SystemInit()` computed it, `R_FLASH_HP_Open()` derives FCLK = 0 and fails
with `FSP_ERR_FCLK` — BL2 first, since MCUboot opens the flash before anything else. The port
keeps `.ram_noinit` out of `.bss`, but early init is what puts the clock state there. This was
missed on the first RA6M5 hardware run (2026-09-21); `ra6m5_layout_checks.c` and
`bl2_option_setting.c` now `#error` on it, so it fails the build instead of the board.

`S_MSP_STACK_SIZE` in `region_defs.h` is `BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` and is
asserted at build time, so the project and the port have to agree. 0x1000 matches RA6E1.

---

## Status

**2026-09-21 — all three images build for RA6M5 on GNUARM**, from the `ra6m5_gcc_*` projects
now carried in this repo: modules added, partitions set to the layout above, regenerated and
built in e2.

First hardware run (2026-09-21, CK-RA6M5 V2): `FSP_ERR_FCLK` from `R_FLASH_HP_Open` —
`BSP_CFG_EARLY_INIT` was 0 in both secure and bootloader projects. See below.

**2026-09-23 — all three PSA Arch suites pass from both toolchains** (profile_large, isolation
3, IPC), on FSP 6.7.0-beta0 — crypto 63/0/1, attestation 1/0/0, storage 11/0/6, identical on
GCC and IAR, zero failures ([[D046]]). Launches for all six are in `ra6m5_gcc_nonsecure/`.

**2026-09-22 — SCE9 acceleration validated on hardware: PSA Arch crypto 63 passed, 0 failed,
1 skipped** (profile_large, isolation 3, IPC). The skip is deterministic ECDSA, which FSP does not
support ([[D040]]). TF-M's crypto is built from FSP's Mbed TLS ([[D042]]) with FSP's SCE9 ALT set
minus CCM ([[D043]]); BL2 hashes images on the SCE9 too.

Accelerated: cipher, AES, GCM, CMAC, SHA-256, ECP/ECDSA, RSA. In software: CCM, because FSP's
SCE9 CCM caps associated data at 110 B and Protected Storage exceeds it — CCM still reaches the
engine per block through the cipher and AES ALTs.

Re-confirmed the same day on **FSP 6.7.0-beta0** with no port-local patches at all ([[D045]]).
Two defects found here — both of the shape "an abandoned operation leaves the SCE mid-session and
wedges every later user" — are fixed in the pack itself: `mbedtls_aes_free()` ([[D041]]) and
`mbedtls_cipher_free()` for CMAC ([[D043]]). A third fix, to `mbedtls_aes_crypt_ctr()`, was
reverted: that function is not an FSP API and is unreachable through PSA ([[D044]]).

Build it with:

```sh
cmake -S . -B build_ra6m5 -GNinja -DCMAKE_BUILD_TYPE=Debug       -DTFM_PLATFORM=renesas/ra6m5       -DFSP_S_APP_DIR=<fsp_cmake>/ra6m5_gcc_secure       -DFSP_BL2_APP_DIR=<fsp_cmake>/ra6m5_gcc_mcuboot       -DFSP_NS_APP_DIR=<fsp_cmake>/ra6m5_gcc_nonsecure
```

`tfm_s.bin` is byte-identical whether the projects are read from this repo or from
`e2_studio/workspace66`. `bl2` differs by 16 bytes of embedded source paths only.

Measured with `arm-none-eabi-size` (Debug, isolation 1, `text` only):

| Image | Used | Slot code region | Headroom |
|---|---|---|---|
| bl2 | 54.2 KB | 0x18000 (96 KB) | 43% free |
| tfm_s | 174.8 KB | 0x7F600 (509.5 KB) | 334.7 KB free |
| tfm_ns | 6.1 KB | 0x6FE00 (447.5 KB) | — |

Verified on the built images:

- secure image spans `0xA0000`–`0xCBD50`; veneers at `0x11F800`, inside the signed payload and
  clear of the MCUboot trailer
- signed images pad to exactly 512 KB and 448 KB — the full slots
- BL2 emits **discrete** OFS LOAD segments (`0x0100A100` / `0x0100A200` / `0x0100A280`) — the
  brick guard from `DESIGN.md` §8.4 holds on this device
- the SCE9 TRNG links into `tfm_s` (28 `HW_SCE_*` symbols, 8.9 KB after `--gc-sections`)
- `ra6m5_layout_checks.c` and the orphan-section check pass

An earlier pass over a staged copy of the projects caught four project-side gaps before the
real build: see [[D031]].

---

## Device differences from RA6E1 that the port had to absorb

- **Block-protect OFS words are wider.** `BPS`, `PBPS` and their `_SEC` / `_SEL` mirrors are
  0x10, not 0xC, because 2 MB of flash has more protectable blocks. The starts are the same.
  Wrong lengths here are in brick territory — the values come from the generated
  `Debug/memory_regions.ld`.
- **OSPI.** The RA6M5 has `OSPI0_CS0` / `OSPI0_CS1` regions the RA6E1 has not. Nothing in the
  port uses them; they appear in the generated partition list.
- Everything else transfers: same 8 KB / 32 KB flash block geometry, same 128-byte write
  size, same 64-byte data-flash block, same 112-entry vector table, same 13 OFS groups,
  same SCE9 source tree (181 files, byte-identical layout).

---

## Open items

- **TODO — `psa_arch_spe.bat` fix is stranded on the RA8 branch.** `39e0597` quotes the
  compiler path so the default `GCC_BIN` (`C:/Program Files (x86)/...`) stops breaking the
  script: unquoted, the `)` in `(x86)` closed the enclosing `if not exist (` block early, so
  cmake never ran, the script printed `/Arm was unexpected at this time` **and exited 0**. It
  affects the RA6M5 PSA Arch build too, but it was committed after PR #4 and so is not on
  `main`. If RA6 work is picked up before `ra8m2_gen_6_7_TFM` merges back,
  cherry-pick it: `git cherry-pick 39e0597`.

- **Toolchain.** `ra6m5_iar` is named for IAR but its solution selects `gcc-arm-embedded`.
  RASC can generate an IAR CMake project (`ToolchainIarCMakeGenerator`,
  `template/cmake/iar.cmake` in the SC 2026-07 plugin set) — set the solution toolchain to
  IAR before doing the IAR leg, so the flags come from RASC rather than being carried over
  from RA6E1 by hand.
- **FSP version drift.** `ra6m5_gcc` is now on 6.7.0-beta0, matching the RA6E1 solutions. The
  plan targets 6.6, so either the plan or the projects should move.
- **CCM associated-data limit.** FSP's SCE9 CCM caps associated data at 110 B, and reports the
  overflow as a plain `PSA_ERROR_INVALID_ARGUMENT`. A software fallback above the threshold, or a
  documented limit, would make SCE9 CCM usable from PSA ([[D043]]). The two session-leak fixes are
  already in the pack.
- **Open question — acceleration delta.** How does the acceleration actually differ between
  this approach (FSP's Mbed TLS + FSP's `*_ALT` set) and the previous one (ARM's Mbed TLS
  accelerated with the same ALT sources)? Which operations changed hands, and where does the
  PSA core route differently. To be answered with measurements, not inspection.
