# Troubleshooting — indexed by symptom

Each entry gives the symptom, cause and fix. Hazards first.

---

## Hazards

### The part reads back `0xDA` and will not respond

**No recovery is known.** A BL2 image whose option-setting words were coalesced into one load
segment wrote `0x00` across the option registers between them ([DESIGN.md](DESIGN.md) §8.4). The
build's `check_ofs.py` guard prevents this; the pre-flash check is
[GETTING_STARTED.md](GETTING_STARTED.md) §6. **Flash `bl2.elf`, `bl2.hex` or `bl2.srec`, never
`bl2.bin`.**

### The part is provisioned with the wrong TrustZone boundaries

Reprogram with RDPM, which erases the part, then reflash all three images. Values: [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) and
[RA8M2_SOLUTION.md](RA8M2_SOLUTION.md). Rules, including `setTZBoundaries`: [GETTING_STARTED.md](GETTING_STARTED.md) §6.

---

## Boot failures

### `R_FLASH_HP_Open` returns `FSP_ERR_FCLK` (RA6M5)

**Cause.** Early BSP Initialization is disabled in the secure or bootloader project, so
`SystemCoreClock` is zero. **Fix.** Enable it in both and rebuild
([E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) §5). Current builds stop with an
`#error` instead.

### `[ERR] Image in the primary slot is not valid!` / `Unable to find bootable image`

Work through these in order. The first three are the common causes:

1. **Signed at a different `MCUBOOT_ALIGN_VAL`** ([CONFIGURATION.md](CONFIGURATION.md) §3).
   Reflash every slot.
2. **Flashed to the wrong address.** The addresses are per-part: [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md),
   [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md).
3. **A stale image in the other slot.** Erase code and data flash on connect.
4. **`FLASH_AREA_IMAGE_SECTOR_SIZE` disagreeing with the device.** At `0x1000` against a real
   `0x8000`, slots come out 9.875 sectors long; every build step accepts it and it fails here.
   [D054].
5. Only if you link FSP's MCUboot backend: a `struct flash_area` size mismatch
   ([FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md) §3).

### `BOOT_EFLASH` from `boot_read_sectors()`

A slot offset or size that is not a whole multiple of the erase sector.
`<part>_layout_checks.c` asserts this now, so it should fail the build; if it reaches hardware,
the partitioning changed without a rebuild. [D054].

### HardFault in BL2, reading an address like `0x000b0000`

RA8M2 only. An MRAM offset used without its alias prefix. The address should be
`0x020B0000` (secure) or `0x120B0000` (non-secure). `MRAM_ADDR()` in
`cmsis_drivers/Driver_Flash.c` adds the right one by comparing against the boundary. [D073],
[D074].

### HardFault with `BFAR = 0x4013C000` in `bsp_prv_clear_pfb` (RA8M2)

RA8M2 only. `BSP_TZ_CFG_MSAR=0` in `ra8m2/CMakeLists.txt` prevents it, so this means the
workaround was removed; restore it. Changing Clocks to Secure in RASC does not help
([RA8M2_SOLUTION.md](RA8M2_SOLUTION.md)).

### `HFSR.FORCED` set with every `CFSR` / `BFSR` / `MMFSR` / `UFSR` / `SFSR` bit clear

This is the signature of a masked SVCall, not a fault in the code you were running. With
PRIMASK set, SVCall is masked and the first `svc` escalates to HardFault. It is easily misread
as a fault in whatever was being logged from, because the usual trigger is
`LOG_INFFMT` → `printf` → `tfm_output_unpriv_string()`'s `svc 2`. [D064].

---

## Link and build failures

### `region CODE_RAM overflowed`

RA6M5 only: raise `S_RAM_CODE_SIZE` ([CONFIGURATION.md](CONFIGURATION.md) §7).

### `region FLASH overflowed`

The code exceeded the secure region ([CONFIGURATION.md](CONFIGURATION.md) §6). If the map shows
free space, check that `region_defs.h` still defines `TFM_LINKER_VENEERS_OWN_REGION`.

### `Image size + trailer exceeds requested size` from imgtool

The signed image is always region-sized, so adding code cannot cause this - that fails the link
instead. The slot is too small for region + header + TLVs + trailer, which means those sizes
disagree: check them against each other ([CONFIGURATION.md](CONFIGURATION.md) §6).

### `'ielftool' is not recognized` — after a successful link

Set `IAR_BIN` to your EWARM `arm\bin` directory before running the scripts
([scripts/README.md](scripts/README.md)). The default install directory is `ewarmc-10.10.2`,
not `ewarm`; the missing `c` is the usual cause.

### `C1083: Cannot open include file: 'stdio.h'` (PSA Arch builds)

Set `MSVC_VARS` to your `vcvars64.bat`; the PSA Arch scripts load the Visual Studio environment
themselves ([GETTING_STARTED.md](GETTING_STARTED.md) §2). A `'vswhere.exe' is not recognized`
message is harmless. `scripts\vs_build.bat <dir>` rebuilds an existing PSA Arch tree by hand.

### An option you set appears to have no effect

Delete the build tree or pass `-D`; cache entries are not overwritten, and `TFM_PROFILE` loses to
the port's defaults ([CONFIGURATION.md](CONFIGURATION.md)).

### The secure primary slot generates as 512 bytes

**Cause.** The e2 solution emits partition `__BL_0_P_H` before `__BL_0_S_T`; `S_T` must come
first. **Check** `FLASH_AREA_0P`'s `.fa_size` in `Debug/bsp_linker_info.h`, or the order in
`solution.xml`. Comparing the two START addresses proves nothing. The TF-M build will not catch
this.

---

## Things that look like failures and are not

### RTT prints nothing

The `_SEGGER_RTT` address changes on every relink and differs per toolchain; read it from the
image you flashed ([GETTING_STARTED.md](GETTING_STARTED.md) §6). BL2 prints nothing at
`MCUBOOT_LOG_LEVEL=OFF`, the `MinSizeRel` default.

### A test run stops partway and looks like a hang

**Where the output stops tells you which to suspect**, and it is usually the capture rather
than the target:

- Stops **after a result line**, with the next test never announced — suspect the capture.
- Stops **after a `Description:` line** — suspect the target, and the named test is where to
  look.

A target that hangs inside a test prints that test's header first, because the framework emits
it before the body runs. The non-secure RTT up-buffer is 4 KB against roughly 15 KB of log, so
losing the tail is the likelier failure. One SLIH run looked like a hang and was not:
re-running the same binaries completed normally.

### The attestation suite passes, so measured boot works

It does not follow ([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §3). Check the boot record at
the start of secure RAM for `SHARED_DATA_TLV_INFO_MAGIC` (`0x2016`).

### Setting `MCUBOOT_IMAGE_VERSION` changes nothing

Use `MCUBOOT_IMAGE_VERSION_S` / `_NS` ([CONFIGURATION.md](CONFIGURATION.md) §3).

### ITS partition init fails and reports pid 257

The reported pid is ITS, but it is usually the PS half that failed; the ITS half succeeds
silently first. `tfm_its_init()` initialises both, and both go through
`its_flash_fs_validate_config()`. Check the PS geometry: `num_blocks < 2` fails outright, and
`PS_MAX_ASSET_SIZE` has both a ceiling and a floor that move with `PS_NUM_ASSETS`. See
`ra6m5/config_tfm_target.h`, which carries the full derivation.

---

## When nothing here matches

Search [DECISIONS.md](DECISIONS.md) (headings `## Dnnn`); a later entry supersedes an earlier
one.
