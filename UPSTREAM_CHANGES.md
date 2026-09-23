# Changes to upstream TF-M

Changes this port makes to files **outside** `platform/ext/target/renesas/`. These are not
Renesas-specific: each one is a gap or defect in common TF-M code that any platform with the
same property would hit. They are tracked here separately from `DECISIONS.md` because they
have a different destination — a patch series to TrustedFirmware-M rather than a design
record — and because a fork carrying silent edits to common files is a maintenance trap.

Fork point: **`dd2b7de19`** ("Docs: Release notes updates for v2.2.0"), i.e. TF-M v2.2.0.
Regenerate the authoritative list at any time with:

```
git diff --stat $(git merge-base HEAD upstream/main) -- \
    platform/ext/common/ platform/include/ platform/ns/ bl2/ secure_fw/ config/ \
    toolchain_GNUARM.cmake toolchain_IARARM.cmake
```

19 files differ. Each is accounted for below.

---

## Ready to upstream

### 1. IAR: `STACKSEAL` block reserves space but places no section

`platform/ext/common/iar/tfm_isolation_s.icf.template`

`define block STACKSEAL with size = STACKSEAL_SIZE { };` is empty — it reserves 8 bytes but
names no section, so the `__STACK_SEAL` object (which platforms place in
`.msp_stack_seal_res`, exactly as the GNU template anchors `__StackSeal` to that section) is
never placed. ILINK sweeps it into the general data area. `Reset_Handler` then seals an
address sitting on live partition data, `__iar_data_init3` overwrites the seal moments later,
the SPM seal check fails, and `tfm_core_panic()` resets — a boot loop with nothing on the
console, before `main()`.

Fix: `{ section .msp_stack_seal_res }`.

Observed on RA6E1/IAR 10.10.2: seal landed at `0x20009ca0` on `ER_TFM_DATA` instead of
`0x20001760`. After the fix the map reads `ARM_LIB_STACK 0x20000760 (0x1000)` →
`STACKSEAL 0x20001760 (0x8)` → `ER_TFM_SP_ITS_RWZI 0x20001768`, matching GNU.

### 2. IAR: veneers ignore `TFM_LINKER_VENEERS_LOCATION_END`

`platform/ext/common/iar/tfm_isolation_s.icf.template`

The GNU template selects between an inline `VENEERS()` and an end-located one on
`TFM_LINKER_VENEERS_LOCATION_END`, honouring `TFM_LINKER_VENEERS_START`. The IAR template
honours neither — it hardcodes `block ER_VENEER` inline in `LR_CODE`, just after the vector
table.

Any platform whose Non-Secure-Callable window is fixed by hardware (SAU/IDAU, or a vendor
partition table) therefore gets its veneers outside that window. The `SG` instruction is not
permitted there, so **every** NS→S call faults with `SFSR.INVEP` before the veneer's first
instruction.

Fix: guard the inline placement with `!defined(TFM_LINKER_VENEERS_LOCATION_END)` and add
`place at address TFM_LINKER_VENEERS_START { block ER_VENEER, block VENEER_ALIGN };`.

Observed on RA6E1/IAR: veneers at `0x58400`, NSC window at `0x97800`. The fault PC
(`0x58418`) was `tfm_psa_framework_version_veneer`.

### 3. IAR: no hook for vendor sections

`platform/ext/common/iar/tfm_isolation_s.icf.template`

GNU has `S_RAM_CODE_EXTRA_SECTION_NAME` (upstream, `53c10c111`) and
`S_DATA_EXTRA_NOINIT_SECTION_NAME` (item 4) so a platform can name vendor sections that must
execute from RAM, or be neither copied nor zeroed. The IAR template has no equivalent, and
the obvious symmetry does not work: **a section name cannot survive iccarm's preprocessor as
a macro.** It re-emits `.ram_from_flash` as `. ram_from_flash` — the dot separated from the
identifier so the two cannot paste — and ICF rejects it. This happens under every
`--preprocess` variant, a quoted name is refused by the grammar (`no_tick_identifier`), and
keeping the dot literal in the template does not help because the space is inserted ahead of
the expansion.

Fix: the platform names one file in `S_ICF_PLATFORM_SECTIONS`, which the template `#include`s
at four hook points, each with a different `TFM_ICF_HOOK_*` defined. Literal text in an
included file is not a macro expansion and passes through intact.

Recorded in `DECISIONS.md` D019, along with the `ro`/`rw` selector split that
`initialize by copy` requires (it splits the section; naming `ro` in the block captures the
initialiser and leaves the block empty, naming `rw` in the directive matches nothing).

### 4. GNU: vendor no-init sections are orphaned, not placed

`platform/ext/common/gcc/tfm_common_s.ld.template`,
`platform/ext/common/gcc/tfm_isolation_s.ld.template` — commit `fbc84be86`

Adds `S_DATA_EXTRA_NOINIT_SECTION_NAME` → `.TFM_NOINIT`, placed *before* `.TFM_BSS` so it
falls outside `__bss_start__..__bss_end__`. A BSP that sets state in `SystemInit()` — Renesas
FSP sets `SystemCoreClock` and its clock state there — has that state established before the
C runtime runs, so anything holding it must be excluded from both the copy and zero tables.

Unhandled, such a section is not diagnosed but **orphaned**: ld invents an output section
and, the input being PROGBITS, gives it a load address. On RA6E1 that was 110 bytes of
`.ram_noinit` landing inside the 2 KB NSC window, holding initialisers nothing ever copies.

### 5. GNU: `.ER_CODE_SRAM` must precede end-located veneers

`platform/ext/common/gcc/tfm_isolation_s.ld.template` — commit `103520f23`

`.ER_CODE_SRAM` is a `> CODE_RAM AT > FLASH` section, so its LMA comes from the FLASH
allocation pointer. When a platform pins veneers at an absolute address at the end of the
secure region, `.gnu.sgstubs` drags that pointer to the end of flash and every `AT > FLASH`
section after it is allocated past the region end. On RA6E1 that put
`LOADADDR(.ER_CODE_SRAM)` at `0x97840`, inside the NSC window, and overflowed FLASH by 382
bytes while 82 KB sat unused below the veneers.

Moving the emission before the veneers is what `tfm_common_s.ld.template` already does. With
the default veneer location the move changes nothing.

### 6. `MCUBOOT_ALIGN_VAL` capped at 32

`bl2/ext/mcuboot/mcuboot_default_config.cmake`,
`bl2/ext/mcuboot/scripts/wrapper/wrapper.py` — commit `103520f23`

Both choice lists stop at 32, so parts whose flash write unit is larger cannot be configured.
RA6E1/RA6M4 code flash is 128 (`BSP_FEATURE_FLASH_HP_CF_WRITE_SIZE`). Extends both lists to
4096.

The runtime already supports it for `OVERWRITE_ONLY`: the `>=8 && <=32` `_Static_assert` in
`bootutil_public.c` is guarded on the swap modes, and `boot_write_trailer()` pads magic writes
to `ALIGN_DOWN(off, BOOT_MAX_ALIGN)`. `wrapper.py`'s list is the real constraint on TF-M's
signing path, because `wrap()` constructs `imgtool.image.Image()` directly rather than
shelling out to imgtool's CLI.

### 7. `TFM_SPM_DEBUG_TRACE` as a documented option

`config/config_base.cmake`, `config/check_config.cmake`, `secure_fw/spm/CMakeLists.txt`,
`secure_fw/spm/core/backend_sfn.c`, `secure_fw/spm/core/utilities.c` — commit `4a3632073`
(superseding the temporary instrumentation in `09dd25c1a`)

Bring-up tracing of SPM control flow — the caller of `tfm_core_panic()`, and each partition
init with its status on failure — as a real option rather than hand-edits that get reverted
and re-applied. Includes a `check_config.cmake` guard for the trap that the trace emits
through `SPMLOG_ERRMSGVAL`, which a silent SPM log compiles away to `(void)(val)`: with
`TFM_SPM_LOG_LEVEL_SILENCE` the option reads ON, the build succeeds, and nothing is traced.
`TFM_SPM_LOG_LEVEL` defaults to SILENCE outside a Debug build, so it is easy to reach.

### 8. `.srec` output for every toolchain

`toolchain_GNUARM.cmake`, `toolchain_IARARM.cmake`,
`platform/ns/toolchain_ns_GNUARM.cmake`, `platform/ns/toolchain_ns_CLANG.cmake` — commit
`d7df90820`; `platform/ns/toolchain_ns_IARARM.cmake` — 2026-09-23

Emits `.srec` beside the final ELF. Needed wherever a device must be programmed from a format
that preserves address discontinuities — on RA parts the option-setting words at
`0x0100Axxx` mean a flat `.bin` is padded to ~16.8 MB and, worse, merges the option words
into one contiguous blob.

**Complete as of 2026-09-23** ([[D049]]). `platform/ns/toolchain_ns_IARARM.cmake` now adds the
same `${target}_srec` target, via `ielftool --srec` as its other conversions use `ielftool`.
Verified from a clean IAR NS build.

Still uneven between the two NS toolchains: the IAR one produces no `.map`, so a symbol lookup
there needs `nm` on the ELF. Worth folding in before submitting.

### 9. BL2 signing depends on the target, not the image file

`bl2/ext/mcuboot/CMakeLists.txt` — commit `b78618497`

A target named in `DEPENDS` becomes an order-only edge — "build this first", not "re-run me
when it changes" — so the signed image was produced once and never regenerated. Every
incremental build then shipped a signed image of an earlier `tfm_s.bin`. Depends on
`$<TARGET_FILE_DIR:tfm_s>/tfm_s.bin` instead.

This is a correctness bug affecting every platform, and it fails silently.

### 10. NS signing guarded on the target

`bl2/ext/mcuboot/CMakeLists.txt`

In a split SPE/NSPE build the NS image is not built here; it is signed on the NSPE side by
`cmake/spe-CMakeLists.cmake`, using the keys and layout files this build exports into
`<api_ns>/image_signing`. Guarded on the target rather than a flag so it follows whichever
model is in use.

### 11. `bootutil_key_cnt` missing in the EC signature branch

`bl2/ext/mcuboot/keys.c` — commit `b5e450b27`

`const int bootutil_key_cnt = MCUBOOT_IMAGE_NUMBER;` is defined in some signature-type
branches but not the EC one, so an EC-P256 build with `MCUBOOT_IMAGE_NUMBER=2` fails to link.

### 12. `FLASH_DEVICE_ID` redefinition guard

`bl2/ext/mcuboot/include/flash_map/flash_map.h`

`#ifndef` guard so a platform that already defines `FLASH_DEVICE_ID` from its own flash map
does not collide.

---

## Local — not for upstream

### `cmsis_override.h` additions

`platform/include/cmsis_override.h` (pre-existing upstream file, +51 lines)

CMSIS-5 fallbacks for `__TZ_set_MSP_NS` / `__TZ_get_CONTROL_NS` / `SCB_NS` /
`__tz_naked_veneer`, and the `__INITIAL_SP` / `__STACK_LIMIT` mappings for GNU and IAR. Guarded
on `__CM_CMSIS_VERSION_MAIN < 6` so CMSIS 6 uses its own. Revisit once the CMSIS version
floor moves — this is compatibility shimming rather than a defect fix, and may not be wanted
upstream in this form.

### `BL2_HALT_AT_MAIN`

`bl2/ext/mcuboot/bl2_main.c` — commit `2b4b9113e`

A spin at the start of `bl2_main()` to isolate bricking during bring-up. Debug aid, added
when two EK-RA6M4 boards were lost. Keep local or drop before submitting.

---

## Submission notes

- Items 1–3 are IAR-template defects found while bringing up the first IAR build of this
  port. Each produced a silent failure — a reset loop, a hard fault, or no console output —
  rather than a build error, which is the argument for fixing them in the template rather
  than working around them per-platform.
- Items 4, 5 and 6 are already in the tree labelled "Upstream:" or "Upstream + RA6E1:".
  Items 7, 8, 9 are not labelled but belong in the same series.
- Verification: all items exercised on EK-RA6E1. GNU (arm-none-eabi 13.2) and IAR (10.10.2)
  both build BL2 + secure + non-secure, and the non-secure PSA service smoke test passes all
  13 steps under IAR — `psa_framework_version`, `psa_version`, `psa_crypto_init`,
  `psa_generate_random` (SCE9 TRNG), `psa_hash_compute`, ITS set/get/remove, PS set/get/remove
  (AES-GCM), `psa_initial_attest_get_token_size`. GNU is additionally verified against the PSA
  Arch tests (crypto, storage, attestation).
- Both toolchains now pass the PSA Arch suites on EK-RA6E1 at `profile_large` / isolation 3 /
  IPC: attestation 1/1, storage 17 (11 passed, 6 optional-PS skips), crypto 64/64, zero
  failures under either. That is the strongest evidence these template changes are correct -
  the suites exercise placement far harder than a boot test does. See DECISIONS.md D026.
- Before submitting, re-run the `git diff --stat` above: anything appearing there and not
  listed in this file is an untracked divergence from upstream.
