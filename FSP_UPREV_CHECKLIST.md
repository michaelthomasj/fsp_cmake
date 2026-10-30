# FSP uprev checklist — the files that carry FSP code or FSP values

Some files in the port exist only to bridge FSP to TF-M. They carry FSP code, restate an
FSP-generated value, or depend on an FSP internal, but they are not FSP files. Regenerating the
e2 projects does not update them, and nothing in the build compares them against their origin.
They drift on an FSP pack uprev, and the failure is a stale constant that links cleanly and is
wrong at run time.

Work through this before the uprev, not after. Every item below names something you can run or
an assertion that fires. `<part>` is `ra6m5` or `ra8m2` throughout.

The port ships on FSP 6.7.0-beta0, so a move to the release pack is the first uprev a customer
will make. For a TF-M uprev instead, work from
[UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md), which lists every common file this port modifies.

Each check below exists because that drift has already happened once.

## 1. The Mbed TLS patch set

Each part carries five patches in `<part>/mbedtls/`. `0003`, `0004`, `0006` and `0007` are
TF-M's own, rebased onto FSP's Mbed TLS, so they match `lib/ext/mbedcrypto/` in content but
never byte for byte. Compare them with the lines that always differ removed:

```
findstr /v /r /c:"^From " /c:"^index " /c:"^@@ " <tfm-copy>.patch > a.txt
findstr /v /r /c:"^From " /c:"^index " /c:"^@@ " <port-copy>.patch > b.txt
fc a.txt b.txt
```

Any remaining difference means TF-M changed the patch and the rebased copy must follow.
`0100-FSP-fit-TF-M-config-file-name-and-owner-key-ids.patch` is port-specific: compare it only
with the previous revision of the same part. The four shared patches are byte-identical
between RA6M5 and RA8M2, which makes comparing the two parts a cheap cross-check.

## 2. The generated MCUboot sector size

RA8M2:
`findstr RM_MCUBOOT_MRAM_BLOCK_SIZE ra8m2_gcc_mcuboot\ra_cfg\mcu-tools\include\mcuboot_config\mcuboot_config.h`.
RA6M5: the same header derives it from `BSP_FEATURE_FLASH_HP_CF_REGION1_BLOCK_SIZE`. Either must
equal `FLASH_AREA_IMAGE_SECTOR_SIZE` in `<part>/flash_layout.h`. This cannot be asserted at build
time, because both headers define the same macro.

## 3. `struct flash_area` — a guard collision with no diagnostic

Only relevant if FSP's MCUboot backend is linked again. TF-M's `flash_map.h` and FSP's
`flash_map_backend.h` share the include guard `H_UTIL_FLASH_MAP_` but define `struct flash_area`
differently (16 bytes vs 12), so whichever is reached first silently wins and BL2 rejects good
images. Check that every `bootutil` and `flash_map` object reports `DW_AT_byte_size` 16 for
`flash_area` (`arm-none-eabi-readelf --debug-dump=info`; IAR: `ielfdumparm`); a BSP bootloader
object reporting 12 is expected.

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

The SCE module is not shadowed at all: it is built for the secure and bootloader roles, and the
non-secure image globs it like any other. Of the three mechanisms that look like exclusions,
only one excludes anything — omitting a module from `FSP_MODULES_S` / `_BL2`
([ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §2).

---

## The option-memory family — the highest-consequence case

Mechanism: [DESIGN.md](DESIGN.md) §8.4. After an uprev, check four things. Option values are
edited in the bootloader project, not the secure one. RA8M2 derives the option addresses from
`Debug/memory_regions.*`, while RA6M5 transcribes them in `region_defs.h`, so re-read those.
RA8M2's `bl2_option_setting.c` stops the build if an unplaced option group is set, and RA6M5 has
no such guard. And `check_ofs.py` must still pass with `--require-segments`.

### What the port does with each FSP linker input

| FSP file | Treatment |
|---|---|
| `Debug/bsp_linker_info.h` | consumed, filtered to macros only, because it also declares C types and a `flash_map[]` that would collide |
| `Debug/memory_regions.{ld,icf}` | consumed on RA8M2, filtered to `option_settings.h` for the option addresses |
| `bsp_linker.c` | excluded. Its jobs are reimplemented in `bl2_option_setting.c` and `bsp_init_stub.c` on both parts, plus `ra8m2_ddsc.c` on RA8M2 |
| `Debug/fsp_gen.{ld,icf}`, `script/fsp.{ld,icf}` | unused, because TF-M supplies its own. Worth keeping as the reference for what FSP would have done: they were the source of the discrete-region pattern |
| port-owned | `<part>_bl2.ld`, `<part>_bl2.icf`, `<part>_fsp_sections.icf` |
