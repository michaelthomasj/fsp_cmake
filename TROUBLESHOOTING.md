# Troubleshooting — indexed by what you actually see

Each entry: the symptom as it appears, the cause, the fix, and where the full account lives.
Harvested from `DECISIONS.md` and from comments at the fix sites, so the detail is one hop
away rather than reproduced here.

**The two that cost hardware are first.** Everything else is recoverable.

---

## Brick hazards

### The part reads back `0xDA` and will not respond

**Permanent. The board is dead.** FSPR, the option-memory permanence word, has been cleared and
block protection is latched on. Two EK-RA6M4 boards were lost this way on 2026-07-21.

**Cause.** A BL2 image whose option-setting words were coalesced by the linker into **one**
`PT_LOAD` segment spanning `0x0100A100`–`0x0100A2CC`. The gaps between the real words are
zero-filled by the loader, and zero in those positions means "protect, permanently".

**What makes it lethal is that nothing warns you.** The linker is content, the srec is clean,
and `check_ofs.py --ra6-default` once validated against a hardcoded RA6 window that still
contained the stale address, so it printed CLEAN.

**Prevention, all three of which are in place:**

- One `MEMORY` region per option word, never a shared span.
- `readelf -l` on the linked ELF is **the only place the coalescing is visible.** The pre-flash
  checklist in `MACHINE_HANDOFF.md` §4 runs it.
- `check_ofs.py` now **requires** its region and BL2 passes `--require-segments`, so an empty
  result fails rather than reading as a pass.

**Flash `bl2.elf` or `bl2.hex`, never `bl2.bin`.** The option words live in discrete segments a
flat binary cannot express. `DESIGN.md` §8.4, [D002], [D065].

### The part is provisioned with the wrong TrustZone boundaries

**RDPM erases the part** — reflash all three images afterwards. The values are per-part and
derived from the generated layout; they live in `RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md` and
nowhere else, deliberately, because a third copy is how one goes stale.

**Also: `setTZBoundaries` must be `false` in every launch configuration.** The debugger
otherwise derives boundaries from the launched project's symbols, and launched against BL2 it
gets them wrong. `DESIGN.md` §7.2.

---

## Boot failures

### `R_FLASH_HP_Open` / `R_MRAM_Open` returns `FSP_ERR_FCLK`

**Cause.** `BSP_CFG_EARLY_INIT` is 0 in the e2 project. TF-M's `Reset_Handler` runs
`SystemInit()` *before* the C runtime zeroes `.bss`; with early init off, FSP leaves
`SystemCoreClock` in `.bss`, so it is wiped immediately after `SystemInit()` computed it,
`R_FLASH_HP_Open()` derives FCLK = 0 and refuses. BL2 fails first, because MCUboot opens the
flash before anything else runs.

**Fix.** e2 → BSP tab → Early BSP Initialization = Enabled, in **both** the secure and
bootloader projects. Regenerate.

**Now caught at build time** — `<part>_layout_checks.c` and `bl2_option_setting.c` `#error` on
it, so it fails the build rather than the board. [D034], `DESIGN.md` §8.1.

### Bootloader panic immediately, before any MCUboot output

**Cause (RA8M2, and RA6M5 if FSP's backend is ever re-enabled).** The flash controller is opened
twice. `boot_platform_init()` opens `g_mram0_ctrl` / `g_flash0_ctrl`, then FSP's
`flash_area_open()` opens the same controller, gets `FSP_ERR_ALREADY_OPEN` and returns −1.

**Fix, already in place.** `<part>_flash_release_for_mcuboot()` calls `R_MRAM_Close()` /
`R_FLASH_HP_Close()` and is the first thing `boot_platform_post_init()` does. [D085].

### `[ERR] Image in the primary slot is not valid!` / `Unable to find bootable image`

Work through these in order — the first three are the common causes:

1. **Signed at a different `MCUBOOT_ALIGN_VAL`.** imgtool encodes `max_align` into the trailer
   magic whenever it is not 8, so an image signed at 128 is rejected by a BL2 built at 32.
   RA6M5 uses 128 and RA8M2 uses 32, so **the two parts' images are not interchangeable.**
   Reflash every slot rather than mixing.
2. **Flashed to the wrong address.** The addresses are per-part; see the per-part solution doc.
3. **A stale image in the other slot.** Erase code *and* data flash on connect.
4. **`FLASH_AREA_IMAGE_SECTOR_SIZE` disagreeing with the device.** At `0x1000` against a real
   `0x8000`, slots come out 9.875 sectors long; every build step accepts it and it fails here.
   [D054].

5. **A `struct flash_area` layout mismatch**, if BL2 takes its flash map from FSP. TF-M's and
   FSP's headers share the guard `H_UTIL_FLASH_MAP_` and define the struct differently - 16
   bytes against 12 - so the first one reached silently suppresses the other and every member
   after `pad16` is read one slot late. The image is fine; `fa_size` is not. The signature in a
   debugger is `fap->fa_off` holding what should be the size. Or check from DWARF that every
   linked object reports `sizeof(struct flash_area) == 12` (`BRIDGING_FILES.md` §3). This
   produced exactly this error on RA6M5 ([D090], which supersedes [D085]).

### `BOOT_EFLASH` from `boot_read_sectors()`

A slot offset or size that is not a whole multiple of the erase sector.
`<part>_layout_checks.c` asserts this now, so it should fail the build; if it reaches hardware,
the partitioning changed without a rebuild. [D054].

### HardFault in BL2, reading an address like `0x000b0000`

**RA8M2 only.** An MRAM offset used without its alias prefix — the address should be
`0x020B0000` (secure) or `0x120B0000` (non-secure). `MRAM_ADDR()` in
`cmsis_drivers/Driver_Flash.c` adds the right one by comparing against the boundary. [D073],
[D074].

### `HFSR.FORCED` set with every `CFSR` / `BFSR` / `MMFSR` / `UFSR` / `SFSR` bit clear

**This is the signature of a masked SVCall, not a fault in the code you were running.** With
PRIMASK set, SVCall is masked and the first `svc` escalates to HardFault. It is easily misread
as a fault in whatever was being logged from, because the usual trigger is
`LOG_INFFMT` → `printf` → `tfm_output_unpriv_string()`'s `svc 2`. [D064].

---

## Link and build failures

### `region CODE_RAM overflowed`

**RA6M5 only.** `S_RAM_CODE_SIZE` in `region_defs.h` is too small for the RAM-resident flash
P/E routines. It is `0xA00` for `0x7d0` of code **plus a long-branch veneer that ld inserts
inside the section**; `0x800` fit with nothing to spare. Revisit on any FSP uprev. RA8M2 has no
such window — `r_mram.c` needs no RAM-resident code.

### `region FLASH overflowed` while the map shows tens of KB free

Check whether the overflow is the *slot* rather than the region: the signed image carries a
~275 B imgtool TLV block and a 16-byte trailer on top of the raw image, and the slot must hold
all of it. True spare is 1,693 B on RA6M5 and 670 B on RA8M2 — see `README.md` §"Freeing space
in the secure image" for what to turn off, and [D087] for why the older, larger figures were
wrong.

### ``undefined symbol `Image$ARM_LIB_STACK$ZI$Base` `` — with single `$`

**A CMake/Ninja escaping difference, not a missing symbol.** The symbol needs `$$`, and how
many `$` a CMake string needs to survive as two on the link line is version dependent: the
literal worked under CMake 3.27.6 / Ninja 1.11.1 and was halved under 4.1.1 / 1.13.1.

**Fix, already in place.** The option is written to a response file with `file(WRITE)` and
passed as `-Wl,@file`, so no escaping layer is left to disagree. [D010].

### `'ielftool' is not recognized` — after a successful link

IAR's post-link steps need `C:\iar\ewarmc-10.10.2\arm\bin` on `PATH`. Note **`ewarmc`**, not
`ewarm`; the missing `c` was frozen into four PSA-arch build trees' caches and survived
`--regenerate-during-build`, because regeneration reads the same cache. `scripts\vs_build.bat`
prepends it. [D083].

### `targetConfigGen.c(1): fatal error C1083: Cannot open include file: 'stdio.h'`

**The MSVC installation is fine.** `stdio.h` is a **UCRT** header from the Windows SDK and has
never shipped in the MSVC toolset, so its absence from `VC\Tools\MSVC\<ver>\include` is normal.
The real failure is that `INCLUDE` was unset.

**Cause.** The psa-arch-tests build compiles `targetConfigGen.c` with `cl.exe` as a **host**
tool. Only a Visual Studio developer environment sets `INCLUDE` and `LIB`.

**Fix.** Build through `scripts\vs_build.bat`. Required for every PSA Arch build and nothing
else. [D083].

### `'vswhere.exe' is not recognized` from vcvars

**Cosmetic.** vcvars falls back to the registry and sets the SDK paths correctly. This is why
`vs_build.bat` checks the *result* — does `INCLUDE` mention "Windows Kits" — rather than
vcvars' exit code. [D083].

### An option you set appears to have no effect

**Check `CMakeCache.txt` in the build tree, not the config file.** `set(X ON CACHE BOOL "")`
does **not** overwrite an existing cache entry without `FORCE`, so a value added to
`config.cmake` after a tree was first configured never reaches it. Either pass `-DX=...`
explicitly or delete the tree.

This has produced two false conclusions already: a tree carrying hand-set debug options that no
script reproduced ([D084]), and a stale tool path surviving regeneration ([D083]).

Also check you are not expecting `TFM_PROFILE` to win. **It loses to the port's cache
defaults** — `TFM_ISOLATION_LEVEL` and the `TFM_PARTITION_*` set are already in the cache by
the time the profile file is read. [D007].

### The secure primary slot generates as 512 bytes

**Partition emission order in the e2 solution**, not geometry: `__BL_0_S_T` was emitted before
`__BL_0_P_H`. After any repartition, read `Debug/bsp_linker_info.h` back and check that
`__BL_0_P_H_START` equals `__BL_0_S_T_START`. [D078].

---

## Things that look like failures and are not

### RTT prints nothing

**Re-read the `_SEGGER_RTT` address for the exact image you flashed.** It moves on every
relink, and — the part that actually bites — it differs **per toolchain** for the same source
on the same part. Nothing in the launch configuration carries it, so a wrong address is a
silent "prints nothing", not an error.

```
arm-none-eabi-nm <image>.axf | grep -w _SEGGER_RTT
```

Also: BL2 has no RTT at all unless `MCUBOOT_LOG_LEVEL` is `INFO` — at the default `OFF` the
symbol is absent, which is expected rather than broken.

### The attestation suite passes, so measured boot works

**It does not follow.** With `component_cnt == 0` under the default
`ATTEST_TOKEN_PROFILE_PSA_IOT_1`, `attest_add_all_sw_components()` emits
`IAT_NO_SW_COMPONENTS` and returns **success**. The suite passes whether or not measured boot
is enabled, and every attestation pass recorded before 2026-10-02 was on a token with no
measurements.

**Verify by reading the boot record** at the start of secure RAM instead: look for
`SHARED_DATA_TLV_INFO_MAGIC` = `0x2016`. [D080], [D081].

### Setting `MCUBOOT_IMAGE_VERSION` changes nothing

Correct, and **it fails silently.** That environment variable is FSP's, read by
`rm_mcuboot_port_sign.py`. This port uses TF-M's `MCUBOOT_IMAGE_VERSION_S` / `_NS`. A
documented deviation — `DESIGN.md` §1.1.

### ITS partition init fails and reports pid 257

The reported pid is ITS, but **it is usually the PS half that failed** — the ITS half succeeds
silently first. `tfm_its_init()` initialises both, and both go through
`its_flash_fs_validate_config()`. Check the PS geometry: `num_blocks < 2` fails outright, and
`PS_MAX_ASSET_SIZE` has both a ceiling and a floor that move with `PS_NUM_ASSETS`. See
`ra6m5/config_tfm_target.h`, which carries the full derivation.

---

## When nothing here matches

The decision log is searchable and indexed by cause rather than symptom:
`grep -n "^## D0" DECISIONS.md`. Entries are append-only, so a later one may supersede what an
earlier one concluded — the later entry always says so.
