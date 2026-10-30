# Modifications to common TF-M code

What this fork changes outside `platform/ext/target/renesas/`: what you inherit beyond the port,
and what a TF-M uprev must reconcile. **24 common files**, none Renesas-specific; the table maps
each to its section. The 14 files under `platform/ext/accelerator/renesas/` are new Renesas
content, not edits. Regenerate the list with:

```
git diff --stat TF-Mv2.2.0 HEAD -- . ":(exclude)platform/ext/target/renesas" ":(exclude)platform/ext/accelerator/renesas"
```

| File | Changed because |
|---|---|
| `platform/ext/common/iar/tfm_isolation_s.icf.template` | §1 the `STACKSEAL` block places no section, §2 veneers ignore the end location, §3 no hook for vendor sections |
| `platform/ext/common/gcc/tfm_isolation_s.ld.template` | §4 vendor no-init sections are orphaned, §5 `.ER_CODE_SRAM` ordering, §16 pinned veneers move the allocation pointer |
| `platform/ext/common/gcc/tfm_common_s.ld.template` | §4 and §5, the same two |
| `bl2/ext/mcuboot/mcuboot_default_config.cmake` | §6 `MCUBOOT_ALIGN_VAL` is capped at 32 |
| `bl2/ext/mcuboot/scripts/wrapper/wrapper.py` | §6, the same cap on the signing side |
| `config/config_base.cmake` | §7 `TFM_SPM_DEBUG_TRACE` becomes a documented option |
| `config/check_config.cmake` | §7, the option's validity check |
| `secure_fw/spm/CMakeLists.txt` | §7 |
| `secure_fw/spm/core/backend_sfn.c` | §7 |
| `secure_fw/spm/core/utilities.c` | §7 |
| `toolchain_GNUARM.cmake` | §8 `.srec` output for every toolchain |
| `toolchain_ARMCLANG.cmake` | §8 |
| `toolchain_CLANG.cmake` | §8 |
| `toolchain_IARARM.cmake` | §8 |
| `platform/ns/toolchain_ns_GNUARM.cmake` | §8 |
| `platform/ns/toolchain_ns_CLANG.cmake` | §8 |
| `platform/ns/toolchain_ns_IARARM.cmake` | §8 |
| `bl2/ext/mcuboot/CMakeLists.txt` | §9 BL2 signing depends on the target rather than the image file, §10 the same for the non-secure image |
| `bl2/ext/mcuboot/keys.c` | §11 `bootutil_key_cnt` is missing in the EC signature branch |
| `bl2/ext/mcuboot/include/flash_map/flash_map.h` | §12 a `FLASH_DEVICE_ID` redefinition guard |
| `cmake/install.cmake` | an `AND TARGET signing_layout_ns` guard. Upstreamable, not yet written up as a section |
| `lib/ext/mcuboot/CMakeLists.txt` | replaces the hard-coded `GIT_REPOSITORY` with an overridable hook. Upstreamable, and it now has no in-tree consumer |
| `platform/include/cmsis_override.h` | local, not for upstream: CMSIS-5 fallbacks, guarded on the CMSIS major version |
| `bl2/ext/mcuboot/bl2_main.c` | local, not for upstream: the `BL2_HALT_AT_MAIN` spin, a bring-up aid |

## Moving to TF-M v2.2.2

Why to move (TFMV-9, if Firmware Update is enabled): [README.md](README.md) item 8 and
[DESIGN.md](DESIGN.md) §13.8. The move is `git rebase --onto TF-Mv2.2.2 TF-Mv2.2.0`; of the 24
files above, v2.2.2 touches these six:

| File |
|---|
| `bl2/ext/mcuboot/include/flash_map/flash_map.h` |
| `config/config_base.cmake` |
| `platform/ext/common/gcc/tfm_common_s.ld.template` |
| `platform/ext/common/gcc/tfm_isolation_s.ld.template` |
| `platform/ns/toolchain_ns_GNUARM.cmake` |
| `toolchain_GNUARM.cmake` |

Re-run the regenerate command against the new base afterwards; a conflict that resolves quietly
in a linker template is the failure mode to watch for. Then re-check four things that a bump can
break without a diagnostic:

- the bootutil build glue still matches (§8 and the `MCUBOOT_VERSION` pin),
- the generated secure linker still honours the veneer macros (§2, §16),
- `<part>_bl2.ld` is still in step with the new `tfm_common_bl2.ld`
  ([DESIGN.md](DESIGN.md) §8.2),
- the option-memory guard still passes on both parts ([DESIGN.md](DESIGN.md) §8.4).

---

## The changes, one section each

### 1. IAR: `STACKSEAL` block reserves space but places no section

`platform/ext/common/iar/tfm_isolation_s.icf.template`

`define block STACKSEAL with size = STACKSEAL_SIZE { };` is empty: it reserves 8 bytes but names
no section. The `__STACK_SEAL` object is therefore never placed, though platforms put it in
`.msp_stack_seal_res`, which is where the GNU template anchors `__StackSeal`. ILINK sweeps it
into the general data area. `Reset_Handler` then seals an
address sitting on live partition data, `__iar_data_init3` overwrites the seal moments later,
the SPM seal check fails, and `tfm_core_panic()` resets — a boot loop with nothing on the
console, before `main()`.

Fix: `{ section .msp_stack_seal_res }`.

### 2. IAR: veneers ignore `TFM_LINKER_VENEERS_LOCATION_END`

`platform/ext/common/iar/tfm_isolation_s.icf.template`

The GNU template selects between an inline `VENEERS()` and an end-located one on
`TFM_LINKER_VENEERS_LOCATION_END`, honouring `TFM_LINKER_VENEERS_START`. The IAR template
honours neither — it hardcodes `block ER_VENEER` inline in `LR_CODE`, just after the vector
table.

Any platform whose Non-Secure-Callable window is fixed by hardware (SAU/IDAU, or a vendor
partition table) therefore gets its veneers outside that window. The `SG` instruction is not
permitted there, so every NS→S call faults with `SFSR.INVEP` before the veneer's first
instruction.

Fix: guard the inline placement with `!defined(TFM_LINKER_VENEERS_LOCATION_END)` and add
`place at address TFM_LINKER_VENEERS_START { block ER_VENEER, block VENEER_ALIGN };`.

### 3. IAR: no hook for vendor sections

`platform/ext/common/iar/tfm_isolation_s.icf.template`

GNU has `S_RAM_CODE_EXTRA_SECTION_NAME` (upstream, `53c10c111`) and
`S_DATA_EXTRA_NOINIT_SECTION_NAME` (item 4) so a platform can name vendor sections that must
execute from RAM, or be neither copied nor zeroed. The IAR template has no equivalent, and
a section name cannot pass through iccarm's preprocessor as a macro (it splits the leading dot),
so the ICF cannot simply mirror the GNU hook.

Fix: the platform names one file in `S_ICF_PLATFORM_SECTIONS`, which the template `#include`s
at four hook points, each with a different `TFM_ICF_HOOK_*` defined. Literal text in an
included file is not a macro expansion and passes through intact.

`initialize by copy` needs separate `ro`/`rw` selectors; see the template.

### 4. GNU: vendor no-init sections are orphaned, not placed

`platform/ext/common/gcc/tfm_common_s.ld.template`,
`platform/ext/common/gcc/tfm_isolation_s.ld.template` — commit `fbc84be86`

Adds `S_DATA_EXTRA_NOINIT_SECTION_NAME` → `.TFM_NOINIT`, placed outside `.bss`, for state a BSP
sets in `SystemInit()` before the C runtime runs (FSP's `SystemCoreClock`).

Without it, ld orphans such a section and gives it a load address, silently.

### 5. GNU: `.ER_CODE_SRAM` must precede end-located veneers

`platform/ext/common/gcc/tfm_isolation_s.ld.template` — commit `103520f23`

`.ER_CODE_SRAM` is a `> CODE_RAM AT > FLASH` section, so its LMA comes from the FLASH allocation
pointer. When a platform pins veneers at an absolute address at the end of the secure region,
`.gnu.sgstubs` drags the allocation pointer to the end of flash. Every `AT > FLASH` section after
it is then placed past the region end, so FLASH overflows while the space below the veneers sits
unused.

Moving the emission before the veneers is what `tfm_common_s.ld.template` already does. With
the default veneer location the move changes nothing.

### 6. `MCUBOOT_ALIGN_VAL` capped at 32

`bl2/ext/mcuboot/mcuboot_default_config.cmake`,
`bl2/ext/mcuboot/scripts/wrapper/wrapper.py` — commit `103520f23`

Both choice lists stop at 32, so parts whose flash write unit is larger cannot be configured.
RA6M5's code flash writes 128 bytes (`MCUBOOT_ALIGN_VAL` 128). Extends both lists to
4096.

The runtime supports it for `OVERWRITE_ONLY`; `wrapper.py`'s list is the real constraint on
TF-M's signing path.

### 7. `TFM_SPM_DEBUG_TRACE` as a documented option

`config/config_base.cmake`, `config/check_config.cmake`, `secure_fw/spm/CMakeLists.txt`,
`secure_fw/spm/core/backend_sfn.c`, `secure_fw/spm/core/utilities.c` — commit `4a3632073`
(superseding the temporary instrumentation in `09dd25c1a`)

Bring-up tracing of SPM control flow (the `tfm_core_panic()` caller, and each partition init with
its status) as a real option. `check_config.cmake` rejects it with `TFM_SPM_LOG_LEVEL_SILENCE`,
under which the trace would compile away silently ([CONFIGURATION.md](CONFIGURATION.md) §6).

### 8. `.srec` output for every toolchain

`toolchain_GNUARM.cmake`, `toolchain_IARARM.cmake`, `toolchain_ARMCLANG.cmake`,
`toolchain_CLANG.cmake`, and `platform/ns/toolchain_ns_{GNUARM,CLANG,IARARM}.cmake`

Emits `.srec` beside the final ELF, for programming tools that need a format preserving address
gaps; on RA parts a flat `.bin` spans the option memory.

The IAR NS toolchain file emits no `.map`; use `nm` on the ELF.

### 9. BL2 signing depends on the target, not the image file

`bl2/ext/mcuboot/CMakeLists.txt` — commit `b78618497`

A custom target in `DEPENDS` is an order-only edge, so the signed image was never regenerated and
incremental builds shipped a stale `tfm_s_signed.bin`. Depends on
`$<TARGET_FILE_DIR:tfm_s>/tfm_s.bin` instead. Affects every platform, silently.

### 10. NS signing guarded on the target

`bl2/ext/mcuboot/CMakeLists.txt`

Adds a deferred NS-signing rule (`bl2_sign_ns_image()`, via `cmake_language(DEFER)`) that signs
`tfm_ns` in the SPE build when that target exists (the `FSP_NS_APP_DIR` model). In the split
build the NS image is signed on the NSPE side by `cmake/spe-CMakeLists.cmake`.

### 11. `bootutil_key_cnt` missing in the EC signature branch

`bl2/ext/mcuboot/keys.c` — commit `b5e450b27`

`const int bootutil_key_cnt = MCUBOOT_IMAGE_NUMBER;` is defined in some signature-type
branches but not the EC one, so an EC-P256 build with `MCUBOOT_IMAGE_NUMBER=2` fails to link.

### 12. `FLASH_DEVICE_ID` redefinition guard

`bl2/ext/mcuboot/include/flash_map/flash_map.h`

`#ifndef` guard so a platform that already defines `FLASH_DEVICE_ID` from its own flash map
does not collide.

### 13. WITHDRAWN - BL2's MCUboot flash backend cannot be replaced by a platform

**Withdrawn. Do not submit.** The port takes TF-M's backend and puts FSP's HAL behind
`fa_driver`, as ST does for STM32Cube, so `bl2/CMakeLists.txt` is byte-identical to v2.2.0 again
([DESIGN.md](DESIGN.md) §4).

### 14. IAR: `--redirect __write=__write_buffered` makes a platform `__write()` unreachable

`toolchain_IARARM.cmake` (report only; the port works around it, so no common file changes).

```cmake
add_link_options(
    --silent
    --semihosting
    --redirect __write=__write_buffered
    ...
```

Both options are unconditional, and together they make it impossible for a platform to
supply its own low-level stdout under IAR. The redirect sends every reference to `__write`
to DLIB's buffered writer, so a platform's `__write()` is defined, visible in `nm` and in the
map, and never called. The chain ends in semihosting:

```
printf -> _Prout -> fputc -> fflushOne -> __write_buffered -> __dwrite -> __iar_sh_stdout
```

`__write()` is IAR's documented hook for this, so under the stock toolchain file a platform
console is dead code: output goes to semihosting, silently without a debugger, or halts on the
semihosting breakpoint with one. On RA8M2 it showed as BL2 printing nothing over RTT while the
secure and non-secure images printed.

Suggested upstream fix: drop `--redirect __write=__write_buffered` (or make it opt-out), or at
least document that an IAR platform must implement `__dwrite()`.

Workaround carried here. `<part>/rtt/rtt_stdout.c` defines both `__write()` and
`__dwrite()` against one implementation, which also keeps `dwrite.o` and `iarwstd.o` out of
the link. A platform `setvbuf(stdout, NULL, _IONBF, 0)` is needed alongside it, because BL2
logs a few hundred bytes and chainloads without ever flushing. DECISIONS D107, D108.

### 15. WITHDRAWN - `TFM_ISOLATION_LEVEL` does reach `tfm_hal_isolation_v8m.c` upstream

**Withdrawn. Do not submit.** The macros reach the file through `psa_interface` wherever
`tfm_hal_isolation_v8m.c` is added to `tfm_spm`, which is what every upstream platform and now
every RA platform does. The port carries no hand-defines for it.

### 16. GNU: pinned CMSE veneers drag FLASH's allocation pointer

`platform/ext/common/gcc/tfm_isolation_s.ld.template` - commit `4025eedff` (2026-09-28),
"Linker: give pinned CMSE veneers their own MEMORY region" (+46 lines, template lines 41-90).

When `.gnu.sgstubs` is pinned to a fixed address inside the FLASH region, ld advances FLASH's
allocation pointer past the veneers, so everything placed afterwards starts beyond them even
when the space below is free. On this port that overran the regression-test link.

Fix, opt-in: `TFM_LINKER_VENEERS_OWN_REGION` gives the pinned veneers a `MEMORY` region of
their own and leaves FLASH's pointer where it was. Every RA platform defines it in
`<part>/region_defs.h`; other platforms are unaffected. **A TF-M bump that drops this change
breaks the regression link on every RA part.**

---

## Local — not for upstream

### `cmsis_override.h` additions

`platform/include/cmsis_override.h` (pre-existing upstream file, +47 lines)

CMSIS-5 fallbacks for the TrustZone intrinsics and the `__INITIAL_SP` / `__STACK_LIMIT` mappings,
guarded on `__CM_CMSIS_VERSION_MAIN < 6`. Compatibility shimming, not a defect fix.

### `BL2_HALT_AT_MAIN`

`bl2/ext/mcuboot/bl2_main.c` — commit `2b4b9113e`

A spin at the start of `bl2_main()`, a bring-up aid. Enabled by `<PART>_BL2_HALT_AT_MAIN`
(default OFF); with it ON, BL2 does not boot.

---

## How these changes were verified

Every change except §8's ARMCLANG and CLANG files, which no configuration here builds, is
exercised by every RA6M5 and RA8M2 build and by the regression and PSA
Arch runs in [TEST_RESULTS.md](TEST_RESULTS.md), under GNU and IAR. Sections 1 to 3 and 14 are
IAR defects that fail silently (a reset loop, a fault, or no console) rather than at build time.

After any TF-M uprev, re-run the regenerate command at the top of this file. Anything it lists
that is not in the table is an untracked divergence from upstream.
