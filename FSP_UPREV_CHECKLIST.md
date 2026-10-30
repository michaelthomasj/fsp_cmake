# FSP uprev checklist — the files that carry FSP code or FSP values

Some files in the port exist only to bridge FSP to TF-M. They carry FSP code, restate an
FSP-generated value, or depend on an FSP internal, but they are not FSP files: regenerating the
e2 projects does not update them, and nothing in the build compares them against their origin.
They drift on an FSP pack uprev, and the failure is a stale constant that links cleanly and is
wrong at run time.

Work through this before the uprev, not after. Every item below names something you can run or
an assertion that fires. `<part>` is `ra6m5` or `ra8m2` throughout.

The port ships on FSP 6.7.0-beta0, so a move to the release pack is the first uprev a customer
will make.

**Four drifts of this kind have already happened.** `FLASH_AREA_IMAGE_SECTOR_SIZE` was `0x1000`
in the RA8M2 `flash_layout.h` while the generated `mcuboot_config.h` had `0x8000`, which made
slots 9.875 sectors long and failed only on hardware. Two CMake files hardcoded the `sce9`
engine directory on a part whose engine directory is `rsip_e50d`. `config.cmake` asserted
`BSP_FEATURE_RSIP_SCE9_SUPPORTED == 1` on a part where it is `0`. An 87-line Protected Storage
comment described a data flash that the part does not have.

---

## 1. The Mbed TLS patch set

Each part carries five patches in `platform/ext/target/renesas/<part>/mbedtls/`. Four of them —
`0003`, `0004`, `0006` and `0007` — are TF-M's own patches rebased onto the FSP Mbed TLS tree.
They match `lib/ext/mbedcrypto/` in content but differ in commit hash, blob index and hunk
offset, so a plain file comparison always reports a difference and tells you nothing.

Compare them with the `From `, `index ` and `@@ ` lines removed. A difference in the remaining
lines means TF-M changed the patch and the rebased copy has not followed; read it and rebase.

`0100-FSP-fit-TF-M-config-file-name-and-owner-key-ids.patch` is port-specific, has no upstream
counterpart, and differs between the two parts. Compare it only against the previous revision
of the same part.

The four shared patches are byte-identical between RA6M5 and RA8M2, which makes comparing the
two parts a cheap cross-check.

## 2. The generated MCUboot sector size

```
findstr RM_MCUBOOT_MRAM_BLOCK_SIZE ra8m2_gcc_mcuboot\ra_cfg\mcu-tools\include\mcuboot_config\mcuboot_config.h
```

It must still equal `FLASH_AREA_IMAGE_SECTOR_SIZE` in `<part>/flash_layout.h`.

**This one cannot be machine-checked**, which is why it needs a manual step. FSP hardcodes the
value rather than deriving it from a `BSP_FEATURE` macro, and the same generated header also
defines `FLASH_AREA_IMAGE_SECTOR_SIZE`, so it cannot be included alongside the port's copy to
compare. What `<part>_layout_checks.c` does assert is that the part reports the memory type it
expects and that the sector is a whole number of write units.

## 3. `struct flash_area` — a guard collision with no diagnostic

The highest-consequence drift surface in the port, because nothing in the build signals it.

TF-M's `bl2/ext/mcuboot/include/flash_map/flash_map.h` and the FSP
`rm_mcuboot_port/flash_map_backend/flash_map_backend.h` both use the include guard
`H_UTIL_FLASH_MAP_`, so whichever is reached first suppresses the other silently. They do not
define the same type: TF-M's is 16 bytes and carries an extra `ARM_DRIVER_FLASH *fa_driver`
between `pad16` and `fa_off`, where the FSP one is 12 bytes without it. With the wrong
definition in `bootutil`, every member after `pad16` is read one slot late. Both are complete
types, the link succeeds, and the only symptom is a bootloader that rejects a correct image.

Both parts compile TF-M's struct, and neither builds `rm_mcuboot_port` into the secure or
bootloader image. The FSP header is nevertheless still on an include path — the bootloader
project's generated `hal_data.h` includes `rm_mcuboot_port.h`, which includes
`bootutil/image.h` — so the collision is avoided by scope rather than by absence. Those paths
are private to the BSP bootloader library and never reach `bootutil`.

**The check: every `bootutil` and `flash_map` object must report 16 bytes.**

```
arm-none-eabi-readelf --debug-dump=info <build>\bl2\...\<object>.o
```

Look for the `flash_area` structure type and its `DW_AT_byte_size`. Scope the check to
`bootutil` and `flash_map` objects: a BSP bootloader object reporting 12 is expected and is not
a failure. A `bootutil` object reporting 12 means the FSP header has reached the `bootutil`
include path. A stale object on disk can report either size, so confirm the object is still in
the build before chasing it.

An FSP uprev that adds a member to its struct, or a TF-M bump that changes TF-M's, breaks this
again with no warning.

## 4. The `rm_psa_crypto` tree

Compare the FSP `ra/fsp/src/rm_psa_crypto/` tree in a regenerated project against the previous
pack. Of its 35 files only `aes_alt.c` and `cipher_alt.c` have ever differed between the two
engine packs the port has used, so this comparison is high signal at almost no cost.

## 5. The accelerator source list

The accelerator `CMakeLists.txt` selects a subset of the `*_alt.c` sources FSP ships, with CCM
excluded deliberately. FSP adding, removing or fixing a source does not change that list, and
two session-leak fixes were nearly missed this way. After an uprev, list the FSP `*_alt.c`
files and compare them against the list.

---

## The inventory, grouped by how each drifts

### Replaces an FSP source the build excludes

The exclusion keeps applying after FSP changes the original, so nothing complains.

| File | Stands in for | Check |
|---|---|---|
| `bsp_init_stub.c` | the FSP init, copy and nocache tables, and the `g_main_stack` alias | the alias is asserted as `S_MSP_STACK_SIZE == BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` |
| `bl2_option_setting.c` | the option-setting sections `bsp_linker.c` emits | the guard in §"The option-memory family" below |
| `ra8m2_ddsc.c`, RA8M2 only | the `gp_ddsc_*` definitions from `bsp_linker.c` | stops the build on empty partitions. RA6M5 needs no such bridge, because the only unconditional user of those symbols is the ITCM and DTCM attribution, which is guarded on features the Cortex-M33 parts do not have |

### Restates an FSP-generated value

The generated value changes; the restatement does not.

| Restatement | Origin | Check |
|---|---|---|
| `FLASH_AREA_IMAGE_SECTOR_SIZE` in `flash_layout.h` | the generated `mcuboot_config.h` | manual, §2 |
| the accelerator `<engine>_fsp_cfg.h` | `ra_cfg/arm/mbedtls/config.h` | compare after a regenerate |
| `mbedtls_accelerator_config.h`, `crypto_accelerator_config.h` and their `bl2_` variants | the FSP Mbed TLS config | compare after a regenerate |
| `MCUBOOT_ALIGN_VAL` | the part's programming-size feature macro | not asserted; the value is not visible where the checks live |
| the vector-table entry count | `BSP_VECTOR_TABLE_MAX_ENTRIES` | partly asserted, as the linker region against the feature macro. The assert never sees the literal in the startup file, so a table that grew to between 113 and 128 entries would still pass while the literal stayed behind |
| the TrustZone boundary values in KB | the generated partition sizes | no build-time check is possible, because provisioning does not report back. The part guides derive them rather than transcribing them |

### Depends on an FSP internal rather than its public API

FSP may refactor something it never promised to keep. A link error is the good outcome; the bad
one is a signature that still matches with changed semantics.

| File | Depends on |
|---|---|
| `cmsis_drivers/Driver_Flash.c` | the erase block units and the `InfoGet` field layout of the part's flash driver. It also declares the generated instance objects directly rather than including `ra_gen/hal_data.h`, which would pull in the FSP `psa/crypto.h` and shadow TF-M's for the whole secure platform library |
| `ra_sce_init.c` | `HW_SCE_McuSpecificInit()`, a private adapter primitive |
| `sce_trng.c` | `HW_SCE_RNG_Read()`, likewise |
| the accelerator `crypto_hw.c` | `psa_aead_setup_vendor()`, declared locally in both engine trees |
| `<part>_fsp_sections.icf` | the FSP section names |

### Shadows an FSP module wholesale

`rm_mcuboot_port`, `bsp_linker.c`, and `startup.c` with `ra_gen/main.c`. Each carries its
reason in the file.

`rm_psa_crypto` and `ra/arm/mbedtls` are a narrower case: the port excludes the FSP PSA core
module build and its Mbed TLS config, not the FSP crypto code. The `*_ALT` sources come from
`platform/ext/accelerator/renesas/<engine>` and the library from the Mbed TLS overlay, so §4
and §5 treat those sources as part of the image, which is correct.

The SCE module is not shadowed at all: it is built for the secure and bootloader roles, and is
removed only from the non-secure glob, which is a different image.
[ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §2 sets the three exclusion mechanisms side by
side; they are easy to confuse, and only two of them exclude anything.

---

## The option-memory family — the highest-consequence case

The failure mode is not a build error. Take the worked hazard: a user changes an option setting
in e2, rebuilds, and expects the new value to be programmed.

| Stage | Comes from | What goes wrong silently |
|---|---|---|
| the values | the bootloader project's `ra_cfg/.../bsp_mcu_ofs_cfg.h` | edited in the secure project instead, which has no effect and gives no warning. `bl2_option_setting.c` compiles into the bootloader platform library, so only the bootloader project is on the path, and both projects define the same groups |
| the addresses | the bootloader project's generated `Debug/memory_regions.*`, filtered into `option_settings.h` at configure time | RA8M2 derives them. RA6M5 still transcribes them by hand, which is the open back-port |
| which groups exist | the device. FSP emits a `BSP_CFG_OPTION_SETTING_*` only for what the user set | a group enabled in e2 that the port does not place is dropped with no diagnostic |
| the placement | `<part>_bl2.ld` and `<part>_bl2.icf` | one coalesced load segment zero-fills the span between the emitted words, writing `0x00` into eight defined option registers and the reserved bytes between them. **That made two EK-RA6M4 boards un-erasable and no recovery is known.** It is invisible in the srec |

Each hazard has a mechanism rather than a comment:

- `bl2_option_setting.c` ends in a guard listing every option word FSP knows for the part that
  the port does not place. Any of them being set stops the build with the three edits it needs.
  **RA8M2 carries 22 of these guards and RA6M5 none**, which is the same open back-port.
- `check_ofs.py` requires its address window to be passed. It used to hardcode the RA6 window,
  and against an RA8M2 bootloader carrying six option segments it printed `CLEAN (no OFS
  segments) … safe to flash`. A guard pointed at the wrong window is worse than none, because
  it reads as verification. The bootloader check also passes `--require-segments`, so an empty
  result fails.
- `readelf -l` on the linked ELF is the only place the coalescing is visible.
  [GETTING_STARTED.md](GETTING_STARTED.md) §6 has the pre-flash form of both checks.

### What the port does with each FSP linker input

| FSP file | Treatment |
|---|---|
| `Debug/bsp_linker_info.h` | consumed, filtered to macros only, because it also declares C types and a `flash_map[]` that would collide |
| `Debug/memory_regions.{ld,icf}` | consumed on RA8M2, filtered to `option_settings.h` for the option addresses |
| `bsp_linker.c` | excluded. Its jobs are reimplemented in `bl2_option_setting.c` and `bsp_init_stub.c` on both parts, plus `ra8m2_ddsc.c` on RA8M2 |
| `Debug/fsp_gen.{ld,icf}`, `script/fsp.{ld,icf}` | unused, because TF-M supplies its own. Worth keeping as the reference for what FSP would have done: they were the source of the discrete-region pattern |
| port-owned | `<part>_bl2.ld`, `<part>_bl2.icf`, `<part>_fsp_sections.icf` |
