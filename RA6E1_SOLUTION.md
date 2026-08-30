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

**Values below re-read from `ra6e1_secure/Debug/bsp_linker_info.h` on 2026-08-29**, after the
second repartition (2 KB NSC, for the MCUboot trailer — see the align section under Open issues).
If you are looking at a copy where the secure slot is `0x17D00`, or the NSC is `0x400` at
`0x97C00`, it predates this.

| Region | Start | Size | Components |
|---|---|---|---|
| MCUboot | `0x00000` | `0x18000` | 96K |
| Image 0 **secondary** (S) | `0x18000` | `0x40000` | hdr `0x200`, image `0x3FE00` @ `0x18200` |
| Image 0 **primary** (S) | `0x58000` | `0x40000` | hdr `0x200`, code `0x3F600` @ `0x58200`, **NSC `0x800` @ `0x97800`** |
| Image 1 **primary** (NS) | `0x98000` | `0x30000` | hdr `0x200`, code `0x2FE00` @ `0x98200` |
| Image 1 **secondary** (NS) | `0xC8000` | `0x30000` | hdr `0x200`, image `0x2FE00` @ `0xC8200` |

All four trailer partitions are **zero-size**; MCUboot writes its own trailer into the last bytes
of each slot at runtime. Both primary/secondary pairs are the same size, which MCUboot requires
and `ra6e1_layout_checks.c` asserts. Partitions are contiguous with no holes — also asserted,
because a hole makes the size sum and the address span disagree and the two sides then place the
trailer magic differently.

NSC flash `0x97800`+`0x800`, ending exactly on the NS boundary at `0x98000`. The veneers
(`.gnu.sgstubs`, `0x40`) sit at its start, leaving room for the `0x180` trailer.
RAM: S `0x20000000`+`0x1FC00`, NSC `0x2001FC00`+`0x400`, NS `0x20020000`+`0x20000`.
Data flash: **all 8K secure** (`0x08000000`+`0x2000`), NS none. Flash use ends at `0xF8000` of 1 MB.
Upgrade mode **overwrite-only** (hence no scratch), signature **ECDSA P-256**, validate-primary on,
**`MCUBOOT_ALIGN_VAL` 128**.

The **option-setting map is byte-identical to RA6M4** — all thirteen groups at the same addresses and
lengths. The `OPTION_SETTING_*` block in the TF-M port's `region_defs.h` transfers verbatim, and the
discrete-region rule (DESIGN.md §8.4) applies unchanged.

## TrustZone boundary values for this layout
Programmed with the Renesas Device Partition Manager, which takes **KB**:

> ⚠ **These have changed twice.** Code Secure was **287**, then **607**; it is now **606** with the
> NSC at **2**. Programming a stale value puts part of the secure image in the non-secure region.

| Field | Value (KB) | Bytes |
|---|---|---|
| Code Secure | **606** | `0x97800` |
| Code NSC | **2** | `0x800` |
| Data Secure | **8** | `0x2000` |
| SRAM Secure | **127** | `0x1FC00` |
| SRAM NSC | **1** | `0x400` |
| SiP Flash Secure | **0** | none on RA6E1 |

Sums land on the coarse granularities: code 606+2 = 608 KB = `0x98000` (32 KB × 19); SRAM 127+1 =
128 KB = `0x20000` (8 KB × 16). See DESIGN.md §7.1 for why that matters.

The NSC grew from 1 KB to 2 KB on 2026-08-29 to make room for the MCUboot trailer at
`MCUBOOT_ALIGN_VAL` 128. It is taken from the secure code region, so the S/NS boundary is
unmoved and only Code Secure and Code NSC change. NSC granularity is 1 KB; only the S/NS
boundary is bound by the 32 KB rule.

## Status
- [x] Bootloader validates both images correctly — but note this was proven with the MCUboot
      module set to **Signature Type: None**, so it exercised the SHA-256 hash check only.
      ECDSA P-256 was enabled in `ra6e1_mcuboot` on 2026-08-26 and the signature path has **not**
      been run standalone since. (TF-M's own BL2 is unaffected — it has always signed and verified
      EC-P256, from `MCUBOOT_SIGNATURE_TYPE` in its own cache, not from this project.)
- [x] Secure application runs
- [x] **TF-M secure image boots to completion on hardware** — 2026-08-29. Full SPM init, all
      partitions initialised, S→NS reached. Three defects had to be fixed to get here; all are
      described in the code at their fix sites:
      1. `tfm_hal_platform_init()` never called `__enable_irq()`. `Reset_Handler` does
         `__disable_irq()` (standard) and every reference port undoes it here. Under the **SFN**
         backend nothing else clears PRIMASK — the SPM's only `cpsie i` sites are IPC-backend
         paths — so the first `SVC` escalated to HardFault. Signature: `HFSR=0x40000000` (FORCED)
         with every CFSR/BFSR/MMFSR/UFSR/SFSR bit clear.
      2. `tfm_hal_platform_init()` never called `stdio_init()`, the only caller of
         `SEGGER_RTT_Init()`, so `--gc-sections` dropped it and the RTT control block stayed
         zeroed — invisible to RTT Viewer, which locates it by the `"SEGGER RTT"` ID string.
      3. `PS_MAX_ASSET_SIZE` 2048 does not fit this part. See `config_tfm_target.h`.
      Both (1) and (2) were present in the RA6M4 port too and are fixed there as well.
- [x] **S→NS jump works** — was failing with a security error until the TrustZone boundaries were
      programmed. Root cause: nothing in the firmware ever sets them (DESIGN.md §7.1)
- [ ] Non-secure application exercised beyond the jump
- [x] **Re-partition for TF-M sizing** — done; secure slot is now 255.25K (see Layout)
- [x] **TF-M port builds against this project set** — 2026-08-26, all three images signed

### Before flashing the TF-M images to a partitioned board

Both blockers previously listed here are **resolved** (2026-08-26, commit `9e3a10ef4`):

1. ~~`BSP_CFG_CLOCKS_SECURE` unset~~ — moot. BL2 is now a **flat** build, matching how this
   solution defines the bootloader, so `bsp_mcu_ofs_cfg.h` takes its `#else` branch and emits
   `OFS1_SEL = 0xFFFFF8F8` without consulting the setting. Built BL2 now carries `f8f8ffff`, the
   RA6M4 known-good value, byte-identical to this solution's own bootloader.
2. ~~BL2 has no `SystemCoreClockUpdate()`~~ — `BSP_CFG_EARLY_INIT` is now enabled in
   `ra6e1_mcuboot`, so the clock is up before `R_FLASH_HP_Open()`.

Still true, and worth knowing before you interpret a silent board:

- The NS image has **no RTT output**. `SEGGER_RTT.c` is linked but the FSP app never calls it, so
  `--gc-sections` drops the control block — the same defect that hid the secure image's output
  until 2026-08-29, and it is still unfixed on the NS side. A successful S→NS jump therefore still
  looks identical to a hang from the console alone.
- **The RTT control block address moves between builds.** It lives in `.bss`, so any change to
  secure-side buffer sizing shifts it. Re-read it rather than reusing a noted value:
  `arm-none-eabi-nm --defined-only bin/tfm_s.axf | grep _SEGGER_RTT`. Giving RTT Viewer a search
  range (`0x20000000 0x10000`) instead of a fixed address avoids the problem, and also survives the
  BL2→tfm_s handover, which swaps to a different control block.
- **The board is no longer in a virgin data-flash state.** ITS metadata is valid from an earlier
  boot, so `its_flash_fs_prepare()` now succeeds outright and the ITS create path is not exercised
  on every boot. PS took the create path on 2026-08-29 and succeeded, so both branches are covered
  between the two services — but a fresh board will behave differently from this one.

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

### ✅ RESOLVED — MCUBOOT_ALIGN_VAL is 128, matching the code flash write unit

Done 2026-08-29. RA6E1 code flash has a **128-byte** minimum write
(`BSP_FEATURE_FLASH_HP_CF_WRITE_SIZE`), so `MCUBOOT_ALIGN_VAL` and the code-flash
`program_unit` in `Driver_Flash.c` must both be 128 — otherwise the first trailer write of an
upgrade fails. They are now, and the artifacts confirm it end to end:

```
mcuboot_config.h                     MCUBOOT_BOOT_MAX_ALIGN 128
tfm_s_signed.bin  @ 0x3FFF0          80 00 2d e1 5d 29 41 0b 8d 77 67 9c 11 0f 1f 8a
bl2.bin           @ 0x00C980         (identical)
```

That magic is the **align-encoded** variant — `80 00` is 128 little-endian — which imgtool
substitutes whenever `max_align != 8` (`image.py:189-202`). Signing and runtime agreeing on it
is the check that matters; a mismatch means BL2 hunts for the magic where imgtool never wrote it.

Two things had to change together:

1. **Tooling.** `scripts/wrapper/wrapper.py` and `mcuboot_default_config.cmake` now accept
   64…4096, matching the list Renesas ships in the FSP MCUboot module. Note the real constraint
   was **wrapper.py's own** `click.Choice`, not imgtool's: wrapper.py builds
   `imgtool.image.Image()` directly and never invokes imgtool's CLI, and `Image()` only requires
   a power of two. The runtime already supported it for `OVERWRITE_ONLY` — the `>=8 && <=32`
   assert is guarded on the SWAP modes.
2. **Layout.** At 128 the trailer is `max_align*2 + align_up(16,128)` = `0x180`. With the old
   1 KB NSC the veneers were pinned at `0x97C00` and the signed image ended at `0x97E91` — 17
   bytes past where the trailer must begin. The NSC is now `0x800` at `0x97800`.

⚠ **This was a flag day.** Images signed at align 1 are not accepted by a BL2 built at 128, and
vice versa — the magic differs. Every slot must be reflashed; do not mix.

⚠ **Not yet exercised on hardware.** This only takes effect once BL2 *writes* code flash, i.e. on
an upgrade; validate-and-boot reads only. Proving it needs a real two-version upgrade with a
populated secondary slot. That is the next meaningful test.

### ✅ RESOLVED — code-flash P/E routines run from RAM in `tfm_s`

Fixed 2026-08-30. `bl2` got this on 2026-08-29; `tfm_s` had the same gap and it was latent, not
absent.

FSP marks the r_flash_hp code-flash program/erase routines `PLACE_IN_RAM_SECTION`
(`.ram_from_flash`) because the FCU makes the **entire code flash unreadable** while a code-flash
P/E is in progress. The data-flash path is deliberately *not* RAM-placed — `flash_hp_df_write`,
`flash_hp_df_erase`, `flash_hp_enter_pe_df_mode` carry no attribute — because code flash stays
readable during data-flash P/E.

`tfm_s` uses TF-M's generated `tfm_isolation_s.ld`, which had no `.ram_from_flash` handling, so ld
gave the section a plain flash VMA next to `.text`. All 21 routines sat at `0x00080xxx`.

Latent because the secure image only ever touches data flash: it instantiates `Driver_FLASH1`
(data) and not `Driver_FLASH0` (code). But `FLASH_HP_CFG_CODE_FLASH_PROGRAMMING_ENABLE` is `1` in
`ra6e1_secure`, so the code-flash path is compiled in and `R_FLASH_HP_Write`/`Erase` dispatch to it
on address. Anything that later hands it a code-flash address — `TFM_PARTITION_FIRMWARE_UPDATE`, a
secure flash service for NS, an FSPR/access-window/startup-area call — takes a prefetch abort
mid-operation with the FCU left in P/E mode.

**Fix, port side** (`region_defs.h`): define `S_RAM_CODE_SIZE` `0xA00`, `S_RAM_CODE_START` at the
top of the secure RAM partition, `S_RAM_CODE_EXTRA_SECTION_NAME .ram_from_flash*`, and shrink
`S_DATA_SIZE` by `S_RAM_CODE_SIZE`. TF-M's secure linker already carries the whole mechanism gated
on `S_RAM_CODE_START` — `.ER_CODE_SRAM` in a `CODE_RAM` region with its own copy-table entry, and
`S_RAM_CODE_EXTRA_SECTION_NAME` as the vendor-section hook (nothing upstream uses it). The solution
is untouched: `BSP_PARTITION_RAM_CPU0_S_SIZE` still describes the whole secure RAM, it is only
subdivided. `S_DATA_START` and everything derived from it are unchanged, and BL2 takes
`BL2_DATA_*` from the partition directly.

**Fix, upstream** (`platform/ext/common/gcc/tfm_isolation_s.ld.template`): move the
`.ER_CODE_SRAM` block *above* the end-located `VENEERS()`. `.ER_CODE_SRAM` is `> CODE_RAM AT >
FLASH`, so its LMA comes from the FLASH region pointer; the veneers are pinned at `0x97800`, which
drags that pointer to the end of flash, and every `AT > FLASH` section after it is allocated past
the region end. `LOADADDR(.ER_CODE_SRAM)` came out at `0x97840` — inside the NSC window — and ld
reported *"region FLASH overflowed by 382 bytes"* while **82 KB sat unused** below the veneers.
`tfm_common_s.ld.template` already has the block in the earlier position, so this is an ordering
inconsistency between the two templates, i.e. a genuine upstream bug. **This upstream edit is a
real fix and should reach a merge** — unlike the instrumentation below.

Verify:

```
arm-none-eabi-nm -S --defined-only bin/tfm_s.axf | grep flash_hp_cf_write   # 0x2001f...
grep -n '^\.ER_CODE_SRAM' bin/tfm_s.map                                     # LMA well below 0x97800
```

Two things the memory report does **not** mean what it looks like:

* `FLASH: 259966 B / 261632 B  99.36%` — ld measures to the end of the pinned NSC window. Real RO
  content ends around `0x84000`; there is ~82 KB free. The number that actually constrains the
  image is imgtool's: payload must end by `0x40000 - 0x180`.
* The initialised-data LMAs (`.TFM_DATA`, `.ram_noinit`) still pack into the ~1.9 KB left over
  *inside* the NSC window after `.gnu.sgstubs`' 0x40 bytes. That works today and predates this
  change, but it is fragile — if secure `.data` grows past that leftover, the link fails with an
  overflow that points nowhere near the cause. Worth moving the veneers to the very end of the
  script if it ever bites; `Image$$PT_RO_END$$Base` has to stay after them.

### ✅ RESOLVED — orphan-section check catches unhandled FSP sections

Added 2026-08-30, after the `.ram_from_flash` bug turned out to be an instance of a general
problem rather than a one-off.

`<project>/script/fsp.ld` is a stub that `INCLUDE`s `memory_regions.ld` and `fsp_gen.ld`, and
`fsp_gen.ld` carries the device's memory-section contract: `.ram_from_flash`,
`.ram_code_from_flash`, `.fsp_dtc_vector_table`, `.ram_nocache` / `.bss.*_fsp_nocache` at 32-byte
alignment, `.ram_noinit`, `.qspi_flash*`, `.data_flash*`, the `option_setting_*` windows.

`tfm_s` and `bl2` do not use `fsp.ld` — `tfm_s` links TF-M's generated `tfm_isolation_s.ld`, `bl2`
links `ra6e1_bl2.ld`. A section neither script names is not diagnosed: GNU ld **orphans** it,
invents an output section, and places it next to whatever looks similar. No warning, no error.
Only the NS image is safe; it is a full FSP application and keeps `fsp.ld`.

**What the check is not.** The first idea — diff `fsp_gen.ld` against our scripts — does not work,
because `fsp_gen.ld` is *device boilerplate, not a per-module subset*. Measured: the secure,
bootloader and non-secure projects place the same 53 sections despite different module sets,
differing only in the TrustZone entries (`.flash_nsc`, `.gnu.sgstubs*`, `.ram_nsc`, and the
`_sec`/`_sel` option-setting variants). Diffing would flag ~30 sections nothing emits into.

`ld --orphan-handling=warn` is the same idea and is the native mechanism, but it also reports every
non-allocatable orphan — `.debug_*`, `.comment`, `.ARM.attributes` from every object, hundreds of
lines on `tfm_s` — and TF-M links with `-Wl,-fatal-warnings`, so it cannot simply be switched on.

**What it is.** A post-link check on the ELF, `cmake/ra6e1_check_orphans.cmake`, run as a custom
target after `tfm_s` and `bl2`. An orphan output section's name appears nowhere in the linker
script — that is what made it an orphan — so: list allocatable, non-empty sections in the ELF and
report any whose name is not a token in the preprocessed, comment-stripped script. Substring
matching, not grammar parsing; ld's output-section syntax is `.NAME <addr-expr> <(ATTRS)> :` with
an arbitrary address expression, and parsing it is not worth the fragility.

The script comes from `$<TARGET_OBJECTS:<target>_scatter>` — `target_add_scatter_file()` in
`toolchain_GNUARM.cmake` preprocesses the `.ld` with `-E -P -xc` into that object library and hands
it to ld as `-T`. So the check reads the same text ld saw, with macros expanded and only the `#if`
branches that applied. Reading the source `.ld` would give the wrong answer for `bl2`, whose script
has both a CMSE and a non-CMSE arm.

**Verified by reverting the fix.** With `S_RAM_CODE_EXTRA_SECTION_NAME` commented out:

```
RA6E1 [tfm_s]: allocatable ORPHAN section(s) - present in the image, named
nowhere in the linker script, so ld chose the address:
    .ram_from_flash (2000 bytes at 0x00080b80)
```

Two known-benign orphans are allowlisted per image, with reasons, so a *new* one is still reported:

| Image | Section | Why it is harmless |
|---|---|---|
| `tfm_s` | `.ram_noinit` (110 B) | FSP BSP noinit data — `SystemCoreClock`, `g_bsp_group_irq_sources`, `g_protect_counters`, `g_protect_pfswe_counter`. FSP places it NOLOAD; orphaned it becomes a *loaded* section, so ~110 bytes of flash hold initialisers nothing copies — it is not in the copy table. The variables end up uninitialised either way, which is what `.ram_noinit` means. Wasteful, not wrong. |
| `bl2` | `.msp_stack_seal_res` (8 B) | `bl2` is flat, so `__ARM_FEATURE_CMSE != 3` and `ra6e1_bl2.ld` takes the non-CMSE arm, which has no seal section. `startup_ra6e1.c` still emits the 8-byte `__StackSeal`, which orphans away from the stack top. Inert: FSP writes the seal only under `BSP_TZ_SECURE_BUILD`, TF-M's startup only under CMSE, and both are false here. |

Warning, not error, by default — a TF-M or FSP update can add a benign section and that should not
block a build. `RA6E1_ORPHAN_CHECK_STRICT=ON` escalates to a hard failure; use it in CI.

**Still open, deliberately.** The check tells you a section was placed by guesswork; it cannot tell
you whether the guess was wrong. It also only covers the two images built here. And it complements
rather than replaces the existing unclaimed-module warning in `fsp_add_modules()`, which catches the
C-source half. Adding an FSP module to the secure or BL2 image remains a port change, not a
configuration change — but it now fails loudly instead of silently.

Follow-up worth doing: handle `.ram_noinit` properly in the secure script rather than allowlisting
it. It would return 110 bytes of flash and relieve the LMA pressure inside the NSC window described
above.

### TODO — strip the bring-up instrumentation

Added 2026-08-29 to find the masked-SVCall HardFault. **Deliberately left in until the whole port
is tested** — remove only when hardware bring-up is signed off, not before.

| Where | What | Action |
|---|---|---|
| `secure_fw/spm/core/utilities.c` | `TFM_PANIC_TRACE` — logs `LR` in `tfm_core_panic()` | delete; marked TEMPORARY in-file |
| `secure_fw/spm/core/backend_sfn.c` | `[INIT]` / `[INIT FAIL]` partition-init logging | delete; marked TEMPORARY in-file |
| `.../ra6e1/tfm_hal_platform.c` | `"tfm_s: platform init"` probe write | delete; marked TEMPORARY in-file |
| `build_ra6e1` CMake cache | `TFM_EXCEPTION_INFO_DUMP=ON` | decide: keep or revert to `OFF` |

`utilities.c` and `backend_sfn.c` are **upstream** files, and they are the only upstream edits in
the tree that are not real fixes, so they must not survive into a merge. The other upstream deltas
(`wrapper.py` / `mcuboot_default_config.cmake` align-128, `tfm_isolation_s.ld.template` section
ordering) are genuine fixes and should be kept and reported. The rest of the table is port-local.

Keep the two permanent fixes that came out of the same session: `__enable_irq()` and `stdio_init()`
in `tfm_hal_platform_init()` (both ports). Those are not instrumentation.

On `TFM_EXCEPTION_INFO_DUMP`: it costs ~3.4 KB of secure text and it is the only reason the
HardFault was diagnosable — every fault otherwise lands in the same `tfm_hal_system_halt()` spin
with no detail. Recommend leaving it **ON** for the port's default config while bringing up, and
making that an explicit decision rather than a leftover. Note it is currently set only in the build
directory's cache, so a clean reconfigure silently loses it; if it is being kept, move it into
`platform/ext/target/renesas/ra6e1/config.cmake`.

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
