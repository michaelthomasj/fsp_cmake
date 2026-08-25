# RA6E1 Solution Project — standalone bring-up (pre-TF-M)

Status of the RASC **solution** project set, being brought up **independently of TF-M** first.
Device **R7FA6E10F2CFP**. FSP **6.6.0-beta2**, MCUboot **2.4.0+renesas.0**, RASC `sc_v2026-04.2`.

| Project | Role |
|---|---|
| `ra6e1_solution` | the solution — owns the shared flash layout |
| `ra6e1_solution_mcuboot` | bootloader |
| `ra6e1_solution_secure` | secure app |
| `ra6e1_solution_nonsecure` | non-secure app |

## Why a solution project at all
MCUboot needs flash-layout information that a standalone project cannot produce: the partition
symbols (`__BL_0/1_P/S_*`) are emitted into each project's generated `bsp_linker_info.h` and
`memory_regions.ld` **by the solution**. Without it, the bootloader, secure and non-secure projects
have no shared, consistent view of the slots. This is the gap that blocks driving the TF-M port
purely from individually-generated RASC projects.

The solution's bootloader is configured **dual-image** (`MCUBOOT_IMAGE_NUMBER 2`), which removes the
incompatibility that forced abandoning the `rm_mcuboot_port` graft in July 2026 (the old RASC BL2
project was single-image; see DESIGN.md §5).

## Layout (from the generated `memory_regions.ld`)

| Region | Start | Size |
|---|---|---|
| MCUboot | `0x00000` | 96K |
| Image 0 **secondary** (S) | `0x18000` | 96K |
| Image 0 **primary** (S) | `0x30000` | 96K — code at `0x30200`, `0x17D00` |
| Image 1 **primary** (NS) | `0x48100` | 32K — code at `0x48300`, `0x7D00` |
| Image 1 **secondary** (NS) | `0x50100` | 32K |

NSC flash `0x47C00` (`0x300`) at the end of secure. RAM: S `0x20000000`+`0x1FC00`, NSC `0x2001FC00`
+`0x400`, NS `0x20020000`+`0x20000`. Data flash: S 4K, NS 4K.
Upgrade mode **overwrite-only** (hence no scratch), signature **ECDSA P-256**, validate-primary on.

The **option-setting map is byte-identical to RA6M4** — all thirteen groups at the same addresses and
lengths. The `OPTION_SETTING_*` block in the TF-M port's `region_defs.h` transfers verbatim, and the
discrete-region rule (DESIGN.md §8.4) applies unchanged.

## TrustZone boundary values for this layout
Programmed with the Renesas Device Partition Manager, which takes **KB**:

| Field | Value (KB) | Bytes |
|---|---|---|
| Code Secure | **287** | `0x47C00` |
| Code NSC | **1** | `0x400` |
| Data Secure | **4** | `0x1000` |
| SRAM Secure | **127** | `0x1FC00` |
| SRAM NSC | **1** | `0x400` |
| SiP Flash Secure | **0** | none on RA6E1 |

Sums land on the coarse granularities: code 287+1 = 288 KB = `0x48000` (32 KB × 9); SRAM 127+1 =
128 KB = `0x20000` (8 KB × 16). See DESIGN.md §7.1 for why that matters.

Note the tool takes `0x400` for Code NSC although `.secure_azone` declares `FLASH_CM33_C` as `0x300`
— `CFS2` must land on a 32 KB boundary, so the hardware NSC is `0x47C00`–`0x47FFF`. The extra `0x100`
is the unused gap before `__BL_0_P_T`; harmless.

## Status
- [x] Bootloader validates both images correctly
- [x] Secure application runs
- [x] **S→NS jump works** — was failing with a security error until the TrustZone boundaries were
      programmed. Root cause: nothing in the firmware ever sets them (DESIGN.md §7.1)
- [ ] Non-secure application exercised beyond the jump
- [ ] Re-partition for TF-M sizing (see below)

## Open issues

### ⚠ Debugger auto-programs the TZ boundaries and gets them wrong
`com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` — **default enabled, must be `false`.** The
tooling derives boundaries from the launched project's symbols and cannot handle a bootloader *and*
a secure image sharing the secure region; launched against the bootloader (which has no TrustZone
knowledge) it marks everything secure and silently undoes a correct partition. Currently `false` in
`ra6e1_solution_nonsecure/ra6e1_nonsecure Debug_SSD.launch`. Keep it off in **every** launch config —
TF-M's BL2 is exactly the same shape. Full note: DESIGN.md §7.2.

### ⚠ TO FIX — NSC placement likely ignores the trailer region
**Suspected 2026-08-25, verify on regeneration.** RASC appears to compute "end of secure image" for
NSC/veneer placement without accounting for `__BL_0_P_T`. Required order:

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

### Sizing — this layout will not hold TF-M as configured
Not a problem for standalone bring-up; blocking for the TF-M port:

- **Secure slot 95.25 KB** (`0x17D00`). TF-M secure measures ~166 KB (Debug/INFO) and 121–127 KB even
  in Release with logging silenced. Needs ≥160 KB, 192 KB for headroom.
- **Secure data flash 4 KB.** The RA6M4 port uses ~7 KB of 8 KB (NV counters 2K + PS 3K + ITS 2K), and
  DESIGN.md §7 has data flash all-secure — the solution gives 4 KB of it to NS.
- NS 32 KB is probably fine (NS app ~14 KB text) but check against the FreeRTOS heap.

Repartitioning changes the Code Secure boundary, so the Partition Manager values above must be
recomputed **and re-checked against the 32 KB / 8 KB granularity rule**.

### Divergences from the current TF-M port config
Signature ECDSA-P256 vs RSA-3072 · overwrite-only vs swap+256K scratch · MCUboot 2.4.0 vs 2.1.0 ·
FSP 6.6.0-beta2 here vs 6.1.0 vendored in the port.
