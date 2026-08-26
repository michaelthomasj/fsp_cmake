# RA6E1 Solution Project — standalone bring-up (pre-TF-M)

Status of the RASC **solution** project set, being brought up **independently of TF-M** first.
Device **R7FA6E10F2CFP**. FSP **6.6.0-beta2**, MCUboot **2.4.0+renesas.0**, RASC `sc_v2026-04.2`.

| Project | Role |
|---|---|
| `ra6e1` | the solution — owns the shared flash layout |
| `ra6e1_mcuboot` | bootloader |
| `ra6e1_secure` | secure app |
| `ra6e1_nonsecure` | non-secure app |

## Why a solution project at all
MCUboot needs flash-layout information that a standalone project cannot produce: the partition
symbols (`__BL_0/1_P/S_*`) are emitted into each project's generated `bsp_linker_info.h` and
`memory_regions.ld` **by the solution**. Without it, the bootloader, secure and non-secure projects
have no shared, consistent view of the slots. This is the gap that blocks driving the TF-M port
purely from individually-generated RASC projects.

The solution's bootloader is configured **dual-image** (`MCUBOOT_IMAGE_NUMBER 2`), which removes the
incompatibility that forced abandoning the `rm_mcuboot_port` graft in July 2026 (the old RASC BL2
project was single-image; see DESIGN.md §5).

## Layout

**Repartitioned for TF-M sizing; values below re-read from
`ra6e1_secure/Debug/bsp_linker_info.h` on 2026-08-26.** The original 96K-secure layout is gone —
if you are looking at a copy where the secure slot is `0x17D00`, it predates this.

| Region | Start | Size |
|---|---|---|
| MCUboot | `0x00000` | `0x18000` — 96K |
| Image 0 **secondary** (S) | `0x18000` | `0x40000` — 256K |
| Image 0 **primary** (S) | `0x58000` | `0x40100` — code at `0x58200`, `0x3FA00` (255.25K) |
| Image 1 **primary** (NS) | `0x98100` | `0x30000` — code at `0x98300`, `0x2FD00` (191.25K) |
| Image 1 **secondary** (NS) | `0xC8100` | `0x30000` |

NSC flash `0x97C00` (`0x300`) at the end of secure, ahead of the image-0 trailer at `0x98000`.
RAM: S `0x20000000`+`0x1FC00`, NSC `0x2001FC00`+`0x400`, NS `0x20020000`+`0x20000`.
Data flash: S 4K (`0x08000000`), NS 4K. Total flash use ends at `0xF8100` of 1 MB.
Upgrade mode **overwrite-only** (hence no scratch), signature **ECDSA P-256**, validate-primary on.

The **option-setting map is byte-identical to RA6M4** — all thirteen groups at the same addresses and
lengths. The `OPTION_SETTING_*` block in the TF-M port's `region_defs.h` transfers verbatim, and the
discrete-region rule (DESIGN.md §8.4) applies unchanged.

## TrustZone boundary values for this layout
Programmed with the Renesas Device Partition Manager, which takes **KB**:

> ⚠ **These changed with the repartition.** Code Secure was **287**; it is now **607**. Programming
> the old value puts most of the secure image in the non-secure region.

| Field | Value (KB) | Bytes |
|---|---|---|
| Code Secure | **607** | `0x97C00` |
| Code NSC | **1** | `0x400` |
| Data Secure | **4** | `0x1000` |
| SRAM Secure | **127** | `0x1FC00` |
| SRAM NSC | **1** | `0x400` |
| SiP Flash Secure | **0** | none on RA6E1 |

Sums land on the coarse granularities: code 607+1 = 608 KB = `0x98000` (32 KB × 19); SRAM 127+1 =
128 KB = `0x20000` (8 KB × 16). See DESIGN.md §7.1 for why that matters.

Note the tool takes `0x400` for Code NSC although `.secure_azone` declares `FLASH_CM33_C` as `0x300`
— `CFS2` must land on a 32 KB boundary, so the hardware NSC is `0x97C00`–`0x97FFF`. The extra `0x100`
is the unused gap before `__BL_0_P_T`; harmless.

## Status
- [x] Bootloader validates both images correctly
- [x] Secure application runs
- [x] **S→NS jump works** — was failing with a security error until the TrustZone boundaries were
      programmed. Root cause: nothing in the firmware ever sets them (DESIGN.md §7.1)
- [ ] Non-secure application exercised beyond the jump
- [x] **Re-partition for TF-M sizing** — done; secure slot is now 255.25K (see Layout)
- [x] **TF-M port builds against this project set** — 2026-08-26, all three images signed

### Before flashing the TF-M images to a partitioned board

Both blockers previously listed here are **resolved** (2026-08-26, commit `9198e036b`):

1. ~~`BSP_CFG_CLOCKS_SECURE` unset~~ — moot. BL2 is now a **flat** build, matching how this
   solution defines the bootloader, so `bsp_mcu_ofs_cfg.h` takes its `#else` branch and emits
   `OFS1_SEL = 0xFFFFF8F8` without consulting the setting. Built BL2 now carries `f8f8ffff`, the
   RA6M4 known-good value, byte-identical to this solution's own bootloader.
2. ~~BL2 has no `SystemCoreClockUpdate()`~~ — `BSP_CFG_EARLY_INIT` is now enabled in
   `ra6e1_mcuboot`, so the clock is up before `R_FLASH_HP_Open()`.

Still true, and worth knowing before you interpret a silent board:

- The NS image has **no RTT output**. `SEGGER_RTT.c` is linked but the FSP app never calls it, so
  `--gc-sections` drops the control block. There is no NS-side signal yet — a successful S→NS jump
  looks identical to a hang.
- **No TF-M image has been run on hardware.** Everything above is verified from the artifacts.

Turning this list into template defaults: **`RA6E1_TEMPLATE_CHECKLIST.md`**.

## Open issues

### ⚠ Debugger auto-programs the TZ boundaries and gets them wrong
`com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` — **default enabled, must be `false`.** The
tooling derives boundaries from the launched project's symbols and cannot handle a bootloader *and*
a secure image sharing the secure region; launched against the bootloader (which has no TrustZone
knowledge) it marks everything secure and silently undoes a correct partition. Currently `false` in
`ra6e1_solution_nonsecure/ra6e1_nonsecure Debug_SSD.launch`. Keep it off in **every** launch config —
TF-M's BL2 is exactly the same shape. Full note: DESIGN.md §7.2.

### ✅ RESOLVED — NSC placement is correct
**Verified 2026-08-26 on the first TF-M secure image.** `Image$$ER_VENEER$$Base` = `0x97C00`,
exactly `BSP_PARTITION_FLASH_CPU0_C_START`, with the trailer at `0x98000` above it. So the order
below holds, the veneers sit inside the signed payload, and `TFM_LINKER_VENEERS_START` derived from
`region_defs.h` lands where the solution says. The suspicion below did not reproduce after the
repartition; keep the check in the list for future layout changes.

Original note follows. RASC was suspected of computing "end of secure image" for NSC/veneer
placement without accounting for `__BL_0_P_T`. Required order:

```
[ FLASH_CM33_S ][ FLASH_CM33_C ][ __BL_0_P_T ][ FLASH_CM33_N ]
   secure code     NSC veneers      trailer       NS image
```

If it measures to slot end instead, the NSC lands on or past the trailer → veneers outside the signed
payload (NS→S calls SecureFault at the SG), or MCUboot clobbers them writing the trailer. Correct in
the current 96K layout, so it may only surface once sizes change.

Check: `FLASH_CM33_C` ends exactly at image end; `FLASH_NSC_START` == `BSP_PARTITION_FLASH_CPU0_C_START`;
veneers inside `FLASH_CM33_C` in the map; NS→S call works on hardware.

Note the trailer **cannot** be marked secure — RA has one secure region and it precedes the NSC
(DESIGN.md §7.1). So the secure image's trailer is NS-writable; bounded to DoS by
`MCUBOOT_VALIDATE_PRIMARY_SLOT`, so don't disable it.

### TODO — bundle a default project set inside the TF-M port
An e2 build is now a prerequisite for building TF-M (the layout lives in
`<project>/Debug/bsp_linker_info.h`). So the port should ship a copy of this project set —
solution + bootloader + secure + non-secure — in a folder under
`platform/ext/target/renesas/ra6e1/`, so it builds out of the box, with `FSP_BL2_APP_DIR` /
`FSP_S_APP_DIR` / `FSP_NS_APP_DIR` defaulting to it and redirectable to the user's own regenerated
set.

Exclude binaries (`.elf .map .srec .sbd .bin .rpd .o`) to limit size, but **keep the generated text
layout files** — `Debug/bsp_linker_info.h`, `memory_regions.ld`, `fsp_gen.ld` — or the bundled set
won't build out of the box either. That's a deliberate exception to the "no Debug files" rule, which
applies to the working project set in `fsp_cmake/`.

### ✅ RESOLVED — Sizing
The repartition fixed this. Measured from the first clean TF-M build (Debug, 2026-08-26):

| Image | `text` | Slot code region | Used |
|---|---|---|---|
| bl2 | 55 540 | `0x18000` (96K) | 57% |
| tfm_s | 167 916 | `0x3FD00` (255.25K) | **64%** |
| tfm_ns | 3 334 | `0x2FD00` (191.25K) | 2% |

Beware `ld --print-memory-usage` on the secure image: it reports **99.85%** because the veneers are
pinned at the top of FLASH, so the region always reads as full regardless of code size. Use
`arm-none-eabi-size` for the real figure.

Still open: **secure data flash is 4 KB**, and the RA6M4 port uses ~7 KB of 8 KB (NV counters 2K +
PS 3K + ITS 2K). DESIGN.md §7 wants data flash all-secure; the solution gives half to NS. The port's
`flash_layout.h` carries a `#error` that fires if the secure partition drops below 4 KB, and splits
what it has proportionally — but there is no wear-levelling headroom at this size.

Any further repartition changes the Code Secure boundary, so the Partition Manager values above must
be recomputed **and re-checked against the 32 KB / 8 KB granularity rule**.

### Divergences from the current TF-M port config
Signature ECDSA-P256 vs RSA-3072 · overwrite-only vs swap+256K scratch · MCUboot 2.4.0 vs 2.1.0 ·
FSP 6.6.0-beta2 here vs 6.1.0 vendored in the port.
