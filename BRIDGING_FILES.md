# Bridging files — what carries FSP code or FSP values, and the check for each

**The concern.** Some files in the ports exist only to bridge FSP to TF-M. They carry FSP's
code, restate FSP-generated configuration, or depend on FSP internals — but they are **not**
FSP files, so regenerating the e2 projects does not update them and nothing in the build
compares them against their origin. They drift silently on an FSP pack uprev, and the failure
mode is the worst kind: a stale constant that links cleanly and is wrong at run time.

**A list of filenames is not the point. The check is.** Every entry below names something you
can run or an assertion that fires.

This has already happened more than once:

- `FLASH_AREA_IMAGE_SECTOR_SIZE` was `0x1000` in the RA8M2 `flash_layout.h` while FSP's
  generated `mcuboot_config.h` had it as `0x8000`. Slots came out 9.875 sectors long, every
  build step accepted it, and it failed only on hardware as `BOOT_EFLASH` ([D054]).
- `fsp_sce.cmake` and `fsp_bsp.cmake` both hardcoded `crypto_procedures/src/sce9/...`, carried
  from RA6M5 into a part whose engine directory is `rsip_e50d`. Both now discover it.
- `config.cmake` asserted `BSP_FEATURE_RSIP_SCE9_SUPPORTED == 1` on a part where it is `0`.
- An 87-line Protected Storage comment in `ra8m2/config_tfm_target.h` was RA6M5's arithmetic
  verbatim, opening "the RA8M2's 8 KB data flash" — a part with no data flash ([D086]).

Verified 2026-10-04 against both live parts.

---

## Run these after any FSP pack uprev

### 1. The mbedTLS patch set — content comparison

The ports carry five patches in `<part>/mbedtls/`. Four of them (`0003`, `0004`, `0006`,
`0007`) are **TF-M's own patches, rebased onto FSP's mbedTLS tree.** They are identical in
content to `lib/ext/mbedcrypto/` but differ in commit SHA, blob index and hunk offsets, so a
plain `cmp` always reports a difference and tells you nothing.

Strip the three noise line types and compare the rest:

```sh
cd <trusted-firmware-m>
for n in 0003-Allow-SE-key-to-use-key-vendor-id-within-PSA-crypto \
         0004-Initialise-driver-wrappers-as-first-step-in-psa_cryp \
         0006-Enable-psa_can_do_hash \
         0007-P256M-Add-option-to-force-not-use-of-asm; do
  diff <(sed '/^From /d;/^index /d;/^@@ /d' lib/ext/mbedcrypto/$n.patch) \
       <(sed '/^From /d;/^index /d;/^@@ /d' platform/ext/target/renesas/ra8m2/mbedtls/$n.patch) \
    >/dev/null && echo "SAME  $n" || echo "DRIFT $n"
done
```

All four report `SAME` as of 2026-10-04. A `DRIFT` means TF-M changed the patch and the port's
rebased copy has not followed — read the diff and rebase it.

`0100-FSP-fit-TF-M-config-file-name-and-owner-key-ids.patch` is port-specific, has no upstream
counterpart, and **differs between RA6M5 and RA8M2.** Compare it only against the previous
revision of the same part.

The four shared patches are byte-identical between RA6M5 and RA8M2, so they can be compared to
each other as a cheap cross-check.

### 2. FSP's generated MCUboot config

```sh
grep RM_MCUBOOT_MRAM_BLOCK_SIZE \
  <fsp_cmake>/ra8m2_gcc_mcuboot/ra_cfg/mcu-tools/include/mcuboot_config/mcuboot_config.h
```

Must still be `0x8000`, matching `FLASH_AREA_IMAGE_SECTOR_SIZE` in `ra8m2/flash_layout.h`.

**This one cannot be machine-checked**, which is why it needs a manual step: FSP hardcodes the
value rather than deriving it from a `BSP_FEATURE` macro, and the same header also defines
`FLASH_AREA_IMAGE_SECTOR_SIZE`, so it cannot be included beside the port's to compare. What
*is* asserted in `<part>_layout_checks.c` is that the part reports MRAM and that the sector is
a whole number of MRAM write units ([D086]).

### 3. The rm_psa_crypto tree — the cheapest canary found so far

```sh
cd <peaks-working> && git diff --stat ra/fsp/src/rm_psa_crypto/
```

Of 35 files, only `aes_alt.c` and `cipher_alt.c` have ever differed between the SCE9 and E50D
packs, so a diff here is high-signal at near-zero cost ([D053]).

### 4. The ALT source list

The accelerator `CMakeLists.txt` selects a **subset** of what FSP ships — CCM is deliberately
excluded ([D043], [D051]). FSP adding, removing or fixing a source does not change the list,
and this is how two session-leak fixes were nearly missed ([D053], which supersedes [D052] -
the pack does ship both fixes). After an uprev,
list FSP's `*_alt.c` files and compare against the list.

---

## The inventory, grouped by how each drifts

### Replaces an FSP source that the build EXCLUDES

The exclusion in `fsp_bsp.cmake` keeps applying after FSP changes the original, so nothing
complains.

| File | Stands in for | Check |
|---|---|---|
| `<part>_ddsc.c` | `bsp_linker.c`'s `gp_ddsc_*` definitions | `#error`s on empty partitions. Lives in the `fsp_bsp` module, not `platform_s` — GNU ld does not revisit archives |
| `bsp_init_stub.c` | FSP's init / copy / nocache tables, and the `g_main_stack` alias | the alias is asserted via `S_MSP_STACK_SIZE == BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` |
| `bl2_option_setting.c` | the OFS sections `bsp_linker.c` emits | **has the best guard in the port** — see below |

### Restates an FSP-GENERATED value

The generated value changes; the restatement does not.

| Restatement | Origin | Check |
|---|---|---|
| `FLASH_AREA_IMAGE_SECTOR_SIZE` in `flash_layout.h` | FSP's generated `mcuboot_config.h` | manual, §2 above |
| accelerator `<engine>_fsp_cfg.h` | `ra_cfg/arm/mbedtls/config.h` | diff after regenerate |
| `mbedtls_accelerator_config.h`, `crypto_accelerator_config.h`, and the `bl2_*` variants | FSP's mbedTLS config | diff after regenerate |
| `MCUBOOT_ALIGN_VAL` | `BSP_FEATURE_MRAM_PROGRAMMING_SIZE_BYTES` (32 on RA8M2) | not asserted — `MCUBOOT_ALIGN_VAL` is not visible in `platform_s`, where the checks live |
| `RA8M2_VECTOR_TABLE_ENTRIES` (112) | `BSP_VECTOR_TABLE_MAX_ENTRIES` | **now asserted** via `S_CODE_VECTOR_TABLE_SIZE >= entries * 4` in both parts ([D086]) |
| the RDPM KB figures | the generated partition sizes | **no build-time check is possible** — provisioning does not come back. Derived rather than transcribed in the per-part solution docs |

### Depends on FSP INTERNALS, not its public API

FSP may refactor something it never promised to keep.

| File | Depends on |
|---|---|
| `cmsis_drivers/Driver_Flash.c` | `R_MRAM_Erase` / `R_FLASH_HP_Erase` block units, and the `InfoGet` field layout. Also declares the generated instance objects directly rather than including `ra_gen/hal_data.h`, which would pull FSP's own `psa/crypto.h` and shadow TF-M's for all of `platform_s` |
| `ra_sce_init.c` | `extern fsp_err_t HW_SCE_McuSpecificInit(void);` — a private `r_sce_adapt.c` primitive |
| `sce_trng.c` | `extern fsp_err_t HW_SCE_RNG_Read(uint32_t *OutData_Text);` — likewise |
| accelerator `crypto_hw.c` | `psa_aead_setup_vendor()`, declared locally in both engine trees |
| `<part>_fsp_sections.icf` | FSP's section names |

A link error is the good outcome here. The bad one is a signature that still matches with
changed semantics.

### Shadows an FSP module wholesale

`rm_mcuboot_port`, `rm_psa_crypto` + `ra/arm/mbedtls`, `r_sce`, `bsp_linker.c`, and
`startup.c` / `ra_gen/main.c`. Each carries a stated reason.

**`rm_mcuboot_port` is no longer shadowed on RA8M2** — it supplies the flash map and backend
there ([D079]), which is what removed the running cost that [D073] / [D074] paid. RA6M5 is back
on TF-M's ([D085]), so this row differs per part.

---

## The linker and OFS family — the highest-consequence case

**The failure mode is not a build error.** Worked hazard: a user changes an OFS setting in e2,
rebuilds, and expects the new value to be programmed.

| Stage | Comes from | What goes wrong silently |
|---|---|---|
| OFS **values** | the **bootloader** project's `ra_cfg/.../bsp_mcu_ofs_cfg.h` | Edited in the **secure** project instead — no effect, no warning. `bl2_option_setting.c` compiles into `platform_bl2`, so only `FSP_BL2_APP_DIR` is on the path. Both projects define the same groups |
| OFS **addresses** | the bootloader project's generated `Debug/memory_regions.*`, filtered into `option_settings.h` at configure time | Hand-transcribed until 2026-09-24, and they were RA6M5's: OFS0 linked at `0x0100A100` instead of `0x02c9f040`. **RA6M5 and RA6E1 still transcribe theirs** — the open back-port in [D077] |
| which **groups** exist | the device; FSP emits a `BSP_CFG_OPTION_SETTING_*` only for what the user set | A group enabled in e2 that the port does not place is **dropped with no diagnostic.** OFS2, OFS3_SEC and OFS3_SEL were dropped exactly this way |
| **placement** | `<part>_bl2.ld` MEMORY + sections, `<part>_bl2.icf` region + keep + place | One coalesced `PT_LOAD` zero-fills the gaps and programs block protect to 0 → **permanent brick** ([D002]). Invisible in the srec |

### The checks that exist, and the pattern to follow

Each hazard gets a mechanism, not a comment:

- **`bl2_option_setting.c` ends in a guard** listing every `BSP_CFG_OPTION_SETTING_*` FSP knows
  for the part that the port does **not** place. Any of them being set is an `#error` naming the
  three edits needed. Verified to fire for `BPS` and `OTP_PBPS_SEC`, and correctly not to fire
  for the `OFS1_SEC_NO_HOCOFRQ` variant. **RA8M2 has 22 of these guards; RA6M5 and RA6E1 have
  none** ([D077]).
- **`check_ofs.py` requires its region.** It used to hardcode RA6's `0x0100A100` window and,
  run against an RA8M2 BL2 carrying six OFS segments, printed *"CLEAN (no OFS segments) … safe
  to flash"*. **A guard pointed at the wrong window is worse than none, because it reads as
  verification.** BL2 also passes `--require-segments`, so an empty result fails.
- **`readelf -l` on the linked ELF** is the only place the coalescing is visible. In the
  pre-flash checklist, `MACHINE_HANDOFF.md` §4.

### What the port does with each FSP linker input

| FSP file | Treatment |
|---|---|
| `Debug/bsp_linker_info.h` | **consumed**, filtered to `bsp_partitions.h` — macros only, because it also declares C types and a `flash_map[]` that would collide |
| `Debug/memory_regions.{ld,icf}` | **consumed** on RA8M2, filtered to `option_settings.h` for the OFS addresses |
| `bsp_linker.c` | **excluded**; its three jobs are reimplemented in `bl2_option_setting.c`, `bsp_init_stub.c` and `<part>_ddsc.c` |
| `Debug/fsp_gen.{ld,icf}`, `script/fsp.{ld,icf}` | **unused** — TF-M supplies its own. Worth keeping as the reference for what FSP would have done; they were the source for the discrete-region pattern |
| port-owned | `<part>_bl2.ld`, `<part>_bl2.icf`, `<part>_fsp_sections.icf` |

---

## Sequencing

**Read this before the FSP pack uprev in `PROJECT_PLAN.md`, not after.** The uprev is the event
this document exists to survive, and doing it second means auditing from memory.
