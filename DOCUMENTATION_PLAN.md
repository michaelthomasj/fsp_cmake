# TODO — a self-contained documentation set

**Status: partly done (2026-10-04).** This file is the plan and the gap list, not the
documentation.

Done since it was written: `README.md` is no longer a stub and carries the document map;
`RA8M2_SOLUTION.md` exists; the eight RA6M4-era documents are under `archive/ra6m4/` with an
index; `DESIGN.md` has been corrected to the live parts (DECISIONS D086). **Still missing, and
still the point of this file: `CONFIGURATION.md`, `RECONFIGURING_THE_LAYOUT.md`,
`TROUBLESHOOTING.md`, `BRIDGING_FILES.md`.**

The inventory below is regenerated rather than hand-maintained - the original was months stale
and understated `DECISIONS.md` by 3,000 lines.

## The problem, with a worked example

Ask a narrow question — *what constrains `S_RAM_CODE_SIZE`, and what happens if FSP grows?* — and the
answer is split across places you can only find if you already know they exist:

| Where | What it tells you |
|---|---|
| `region_defs.h` lines 83–89 (TF-M repo) | The whole answer: `.ram_from_flash` measures `0x7d0`; ld appends a long-branch veneer *inside* the section for the RAM code's call to `flash_hp_enter_pe_df_mode`; `0x800` fit with nothing to spare, hence `0xA00`; overflow is caught loudly as `region CODE_RAM overflowed`. |
| `RA6E1_SOLUTION.md` §"code-flash P/E routines" | Why the section exists, the three macros, the upstream ordering bug. **Not** the sizing headroom or the uprev risk. |
| `DECISIONS.md` D012 | Why a hook rather than a fork. Nothing about size. |

So the limitation *is* documented — in a C header, at the fix site, in the other repository. Nobody
reconfiguring this port would find it. That pattern repeats across the port: the knowledge is good
and it is written down, but it is organised by *where the bug was fixed* rather than by *what a
reader needs to do*.

Two more found while surveying:

- **`README.md` is two lines.** 5,992 lines of markdown at this root and the entry point names none
  of it.
- **`RA6M4_BL2_HALT_AT_MAIN` is not a cache option.** `MACHINE_HANDOFF.md` §4 tells you to pass
  `-DRA6M4_BL2_HALT_AT_MAIN=ON`, and it works, but it is a bare `if()` in `CMakeLists.txt` — invisible
  to `ccmake`/`cmake-gui` and undiscoverable from the build. RA6E1's equivalents *are* declared
  `CACHE BOOL`. Documenting the options will surface more of these; fix them as they turn up.

## What exists today

Regenerated 2026-10-04. Live top-level documents only; `archive/ra6m4/` holds eight more.

| File | Lines | Last change |
|---|---|---|
| `DECISIONS.md` | 3693 | 2026-10-02 |
| `RA6E1_SOLUTION.md` | 609 | 2026-09-07 |
| `DESIGN.md` | 397 | 2026-10-04 |
| `UPSTREAM_CHANGES.md` | 304 | 2026-10-02 |
| `PROJECT_PLAN.md` | 299 | 2026-09-25 |
| `DOCUMENTATION_PLAN.md` | 215 | 2026-10-02 |
| `RA6M5_SOLUTION.md` | 213 | 2026-09-23 |
| `RA6E1_TEMPLATE_CHECKLIST.md` | 208 | 2026-10-04 |
| `MACHINE_HANDOFF.md` | 196 | 2026-09-30 |
| `RA8M2_SOLUTION.md` | 193 | 2026-10-04 |
| `RA8x2_DUAL_CORE_DESIGN.md` | 185 | 2026-07-28 |
| `README.md` | 109 | 2026-10-04 |

Most of the operational truth sits in two kinds of file, both engineering diaries:
`DECISIONS.md` (append-only, authoritative where anything disagrees) and the per-part
`*_SOLUTION.md`. That format earned its place - the reversals in it are worth keeping - but it
is not what a user reconfiguring the port needs, and a diary ages badly because nothing in it
says which entries are still true.


## Status, 2026-10-09

Rewritten after five of the seven target documents landed. **What is left is one new document
and three retirements**, not a programme of writing.

| # | Document | State |
|---|---|---|
| 1 | `README.md` | **done** — one page, repo map, now points at `GETTING_STARTED.md` for procedure |
| 2 | ~~`BUILDING.md`~~ | **superseded by `GETTING_STARTED.md`** — see below |
| 2a | `GETTING_STARTED.md` | **done 2026-10-09** — clone to running board, with a document map |
| 3 | `CONFIGURATION.md` | **done** |
| 4 | `RECONFIGURING_THE_LAYOUT.md` | **done 2026-10-09** — the chain that follows automatically, the four things that do not, and the 35 assertions |
| 5 | `ADDING_FSP_MODULES.md` | **done 2026-10-09** — and the earlier claim here that it was "folded into `DESIGN.md`" was **wrong**: DESIGN.md has no such section. The only guidance was in `archive/ra6m4/TFM_INTEGRATION_COMPLETE.md`, which this plan had listed for retirement, and **19 live source files pointed at a path that did not exist**. Rescued, rewritten against the live mechanism, all 19 pointers repaired |
| 6 | `PORTING.md` | **done 2026-10-09** — the checklist covers the RASC half only; this is the TF-M platform half, sized by diffing the two live ports (8 files to author, 31 to copy) |
| 7 | `TROUBLESHOOTING.md` | **done** |
| + | `BRIDGING_FILES.md` | **done** ([D089]) — was the highest-value item on the original list |
| + | `UPSTREAM_CHANGES.md` | **done**, 14 items ([D108] added the IAR toolchain defect) |

### Why `BUILDING.md` became `GETTING_STARTED.md`

The original plan split "one-page orientation" (README) from "real build procedures"
(BUILDING). In practice the reader those were written for - someone handed the repository who
wants a board running - needs one continuous path, not two documents to interleave. A split
makes the reader decide which half they are in, at exactly the moment they know least.

`GETTING_STARTED.md` is that continuous path: prerequisites with versions, clone, the e2
solution build (the step everyone misses), the firmware build, flashing, reading RTT, what a
good run looks like, the first-build failure table, and the map to everything else. README
keeps the orientation and repository map and hands over.

### Revised 2026-10-09 — the target set is complete

Items 1-7 are all done or deliberately resolved. Three were written today (`ADDING_FSP_MODULES`,
`PORTING`, `RECONFIGURING_THE_LAYOUT`) after the owner pointed out that the plan's own status
for two of them was wrong: item 5 was recorded as "folded into DESIGN.md" when DESIGN.md has no
such section, and item 6 as "covered by the checklist" when the checklist is only the RASC half.

**Both errors were in this file, written by the same hand that wrote the documents they
describe.** That is the argument for item 3 below.

### Remaining work, in order

1. **A `## Settled questions` banner table** at the top of `DECISIONS.md`. 111 entries carry
   **20 supersession threads** and **none of the superseded entries says so in place** - every
   one still reads `Status: Accepted`. The owner's call (2026-10-09): group related entries
   under a banner periodically rather than back-annotate, since the append-only rule protects
   the *reasoning*. The chain extraction is scripted; the one-line answers are written. Cadence:
   at milestone boundaries, plus whenever a thread closes on a correction.
2. **Retire the three superseded files** - `TFM_INTEGRATION_COMPLETE.md`,
   `BUILD_TEST_RESULTS.md`, `MACHINE_HANDOFF.md` - keeping their resolved-issue narratives,
   which are the valuable part, by folding them into `TROUBLESHOOTING.md` or a decision entry.
3. **A sweep for stale cross-references.** Three have already been found and fixed by accident
   rather than by checking ([D094]'s wrong D-numbers; `RA8M2_SOLUTION.md` describing the FSP
   MCUboot backend months after [D091] removed it; `app_build_ra8m2_iar.bat` claiming the two
   project sets were out of sync after they had been reconciled). **There is no check for
   this.** A script that extracts every `DECISIONS.md` citation from every document and
   verifies the entry exists and its title matches the claim would have caught all three.

### A documentation rule this port has earned

Every one of the stale cross-references above was written true and became false when the code
moved. The cheap defence is not more prose - it is **citing a command rather than a fact**
wherever possible. `BRIDGING_FILES.md` already does this: each entry names a check you can run
instead of a state you must trust. Apply the same to `RECONFIGURING_THE_LAYOUT.md`.

---

## Target set

Each document self-contained, stating its scope and audience at the top, and cross-referencing rather
than repeating.

1. **README.md** — what this repo is, the two-repo relationship, a map of every other document, and
   the shortest path to a build. One page.
2. **BUILDING.md** — the real build procedures end to end: toolchain and versions, the e2 solution
   build prerequisite, SPE → install → NSPE, signing, what to flash and where. Both platforms, and
   the test-suite variants (`tf-m-tests`, `tests_psa_arch`) with the overrides D007 records.
3. **CONFIGURATION.md** — *the missing one, and the reason this file exists.* Every knob a user may
   legitimately change: name, default, where it is defined, what it affects, and its constraints.
4. **RECONFIGURING_THE_LAYOUT.md** — the repartitioning procedure. What follows automatically from
   the solution (the whole `bsp_linker_info.h` → `bsp_partitions.h` → `region_defs.h` chain, all
   three linkers), what does **not** (RDPM boundaries, `PS_NUM_ASSETS` capacity, the NSC-window LMA
   budget), which `_Static_assert`s catch mistakes, and the order to do it in.
5. **ADDING_FSP_MODULES.md** — exists in substance in `DESIGN.md`; extract and make it standalone.
6. **PORTING.md** — what a new RA platform must supply. Feeds the RA8x2 work directly.
7. **TROUBLESHOOTING.md** — symptom-indexed. The port has an unusually good stock of these
   (`FSP_ERR_FCLK`, `HFSR=0x40000000` with every other bit clear, silent RTT, `region CODE_RAM
   overflowed`, `region FLASH overflowed` with 82 KB free, `undefined symbol Image$ARM_LIB_STACK...`),
   all currently buried at their fix sites.

Unchanged and separate: `DESIGN.md` (how it works), `DECISIONS.md` (why, append-only),
`PROJECT_PLAN.md` (schedule), `RA8x2_DUAL_CORE_DESIGN.md` (forward design).

To retire or fold in once the above exist: `TFM_INTEGRATION_COMPLETE.md`, `BUILD_TEST_RESULTS.md`,
`MACHINE_HANDOFF.md`, and the status half of the two big status files — keeping their resolved-issue
narratives, which are the valuable part.

## Inventory for CONFIGURATION.md

Extracted from the two ports' `config.cmake` / `CMakeLists.txt`; verify each before publishing, since
the survey already found one that is not a cache variable.

**Port-specific build options.** `FSP_BL2_APP_DIR`, `FSP_S_APP_DIR`, `FSP_NS_APP_DIR`,
`FSP_MODULES_S` / `FSP_MODULES_BL2` / `FSP_EXCLUDED_MODULES`, `<PART>_STDOUT_RTT`,
`<PART>_RTT_BLOCKING`, `<PART>_NS_IN_SPE_BUILD` (default OFF on both live parts),
`<PART>_BL2_HALT_AT_MAIN`, `<PART>_ORPHAN_CHECK_STRICT`, `TFM_SPM_DEBUG_TRACE`,
`TFM_EXCEPTION_INFO_DUMP`, `PLATFORM_HAS_ISOLATION_L3_SUPPORT` (D008), and on RA8M2 only
`DEFAULT_MCUBOOT_FLASH_MAP` / `DEFAULT_MCUBOOT_FLASH_BACKEND` (both OFF, D079/D085).

*Checked 2026-10-04:* the "not a cache variable" defect this file predicted does **not** exist
on ra6m5 or ra8m2. Every user-facing `<PART>_*` option there is declared `CACHE BOOL`, some in
`CMakeLists.txt` rather than `config.cmake` - which is why a grep of `config.cmake` alone
appears to find the defect. The remaining `<PART>_*` names are internal configure-time
variables (`BUILDING_BL2`, `IAR_STACK_*`, `MAIN_STACK_*`, `OFS_READELF`, `SOLUTION`,
`SPE_CROSS_COMPILE`), not knobs.

**TF-M settings the port pins,** where a user needs to know the port has an opinion:
`TFM_ISOLATION_LEVEL` · `CONFIG_TFM_SPM_BACKEND` · the five `TFM_PARTITION_*` · the
`PLATFORM_DEFAULT_*` set · `PS_ENCRYPTION` · `PS_CRYPTO_AEAD_ALG` · `CRYPTO_HW_ACCELERATOR` ·
`SYMMETRIC_INITIAL_ATTESTATION` · `PSA_INITIAL_ATTEST_MAX_TOKEN_SIZE`. Note explicitly that these
cache defaults **beat `TFM_PROFILE`** — the trap behind D007.

**MCUboot / layout:** `MCUBOOT_IMAGE_NUMBER` · `MCUBOOT_ALIGN_VAL` (128; flag day — images signed at
another value are rejected) · `MCUBOOT_UPGRADE_STRATEGY` · `MCUBOOT_SIGNATURE_TYPE` ·
`MCUBOOT_HW_KEY` · `MCUBOOT_DATA_SHARING` · `MCUBOOT_MEASURED_BOOT` · `FLASH_AREA_BL2_*` ·
`MCUBOOT_IMAGE_VERSION_S` / `_NS` — and with them the USAGE NOTE that FSP's
`MCUBOOT_IMAGE_VERSION` environment variable is NOT read by this port and is ignored
silently. Documented deviation, DESIGN.md 1.1.

**Header-level tunables** — not cache variables, but the ones people actually need to change, and the
ones with non-obvious constraints:

| Symbol | Where | Constraint to document |
|---|---|---|
| `S_RAM_CODE_SIZE` | `region_defs.h` | `0xA00` for `0x7d0` of code plus an ld-inserted veneer. Overflow → `region CODE_RAM overflowed`. Revisit on FSP uprev. |
| `S_RAM_CODE_EXTRA_SECTION_NAME` | `region_defs.h` | Bare ld pattern, not a quoted string |
| `S_DATA_EXTRA_NOINIT_SECTION_NAME` | `region_defs.h` | Must stay outside `__bss_start__..__bss_end__`, NOLOAD (D012) |
| `PS_NUM_ASSETS` | `config_tfm_target.h` | Cap is **per-part**: 5 on RA6M5 (1,536 B PS block), 155 on RA8M2 (15,872 B). Asserted in `<part>_layout_checks.c`. **Erase data flash before first boot after any change** |
| `PS_MAX_ASSET_SIZE` | `config_tfm_target.h` | Not the binding constraint — capacity is a sum |
| `TFM_NV_COUNTERS_AREA_SIZE` | `flash_layout.h` | Fixed 2048 B; PS and ITS split what remains |
| `TFM_HAL_PS_SECTORS_PER_BLOCK` | `flash_layout.h` | `(area/sector)/2` — `num_blocks < 2` fails ITS/PS init outright |
| `MCUBOOT_ALIGN_VAL` / trailer | `config.cmake`, solution | RA6M5 128 → trailer `0x180`; RA8M2 32 → `0x60`. Flag day: imgtool encodes it in the boot magic, so images are not interchangeable. The trailer occupies the slot tail, which is the top of the NSC window |
| OFS `OPTION_SETTING_*` | `region_defs.h` | **Brick hazard** — one `MEMORY` region per word (D002); `check_ofs.py` enforces |

## Ordering

Write **CONFIGURATION.md** and **RECONFIGURING_THE_LAYOUT.md** first — they are the two with no
current home at all, and the layout one is the procedure most likely to damage a board through the
RDPM step. **README.md** next, because it is cheap and makes the rest findable. **TROUBLESHOOTING.md**
after that, harvested from existing fix-site comments rather than written fresh. The remainder are
largely extraction and de-duplication.

Verify every claim against the code as it is written, not against the existing markdown — the survey
above found doc-to-code drift in a file that reads as current, and copying prose forward is how that
propagates.

---

## BRIDGING_FILES.md — not yet written, and the highest-value item on this list

**The concern.** A number of files in the ports exist only to bridge FSP to TF-M: they carry all or
part of FSP's code, or restate FSP-generated configuration, but are **not** FSP files and are not
regenerated when the packs are. When FSP moves version they do not move with it, and nothing in the
build compares them against their origin. They drift silently, and the failure modes are the worst
kind — a stale constant that links cleanly and is wrong at run time.

This has already happened more than once, which is why it is worth a document rather than a comment:

- `FLASH_AREA_IMAGE_SECTOR_SIZE` was set to `0x1000` in the RA8M2 `flash_layout.h` while FSP's
  generated `mcuboot_config.h` defined it as `RM_MCUBOOT_MRAM_BLOCK_SIZE` (`0x8000`). Slots came out
  9.875 sectors long — accepted by every build step, failing only on hardware as `BOOT_EFLASH`
  (DECISIONS D054).
- `fsp_sce.cmake` and `fsp_bsp.cmake` both hardcoded `crypto_procedures/src/sce9/...`, carried from
  RA6M5 into a part whose engine directory is `rsip_e50d`. Both now discover it instead.
- `config.cmake` asserted `BSP_FEATURE_RSIP_SCE9_SUPPORTED == 1` on a part where it is `0`.

**What the document must do.** For every bridging file: name its FSP origin, say what was changed and
why, and give the **check** that detects drift — a command, a static assert, or a specific thing to
diff after a pack uprev. A list of filenames is not enough; the check is the point.

**Starting inventory** — to be completed by audit, not trusted as complete. Grouped by how they drift:

| Category | Files | How it drifts |
|---|---|---|
| Replaces an EXCLUDED FSP source | `ra8m2_ddsc.c` (for `bsp_linker.c`'s `gp_ddsc_*`), `bsp_init_stub.c` (FSP's init/copy tables), `bl2_option_setting.c` (the OFS sections `bsp_linker.c` emits) | FSP changes the original; the exclusion in `fsp_bsp.cmake` still applies, so nothing complains |
| Restates FSP-GENERATED config | accelerator `*_fsp_cfg.h` (from `ra_cfg/arm/mbedtls/config.h`), `FLASH_AREA_IMAGE_SECTOR_SIZE` in `flash_layout.h`, `mbedtls_accelerator_config.h`, `crypto_accelerator_config.h` | the generated value changes; the restatement does not |
| PATCHES applied to FSP-shipped sources | `mbedtls/0003,0004,0006,0007,0100.patch` | a patch stops applying, or applies with its purpose already upstream |
| Depends on FSP INTERNALS, not its public API | `cmsis_drivers/Driver_Flash.c` (`R_MRAM_Erase` block units, `InfoGet` field layout), `ra_sce_init.c` and `sce_trng.c` (private `r_sce_adapt.c` primitives declared as externs), accelerator `crypto_hw.c` (`psa_aead_setup_vendor`), `ra8m2_fsp_sections.icf` (FSP section names) | FSP refactors something it never promised to keep |
| Selects a SUBSET of what FSP ships | the ALT source list in the accelerator CMakeLists (CCM excluded, D043/D051) | FSP adds, removes or fixes a source and the list is unaware — this is how the two session-leak fixes were nearly missed (D052/D053) |

**Cheapest canary found so far**, worth generalising: `git diff` on `ra/fsp/src/rm_psa_crypto/` after a
regenerate. `aes_alt.c` and `cipher_alt.c` are the only 2 of 35 that have ever differed between the
SCE9 and E50D packs, so a diff there is a high-signal, near-zero-cost check ([[D053]]).

### The linker/OFS family gets its own section — it is the highest-consequence case

Everything to do with FSP's linker inputs belongs in this document explicitly, because the
failure mode is not a build error. **Worked hazard, from a real question:** a user changes an OFS
setting in e2, rebuilds the TF-M port, and expects the new value to be programmed.

| Stage | Where it comes from | What can go wrong silently |
|---|---|---|
| OFS **values** | `BSP_CFG_OPTION_SETTING_*` in the **bootloader** project's `ra_cfg/.../bsp_mcu_ofs_cfg.h` | Edited in the **secure** project instead — no effect, no warning. `bl2_option_setting.c` compiles into `platform_bl2`, so only `FSP_BL2_APP_DIR` is on the path. Both projects define the same groups, which makes this easy to do and impossible to notice. |
| OFS **addresses** | the bootloader project's generated `Debug/memory_regions.icf`, filtered into `option_settings.h` at configure time | Were hand-transcribed until 2026-09-24, and were RA6M5's — OFS0 linked at `0x0100A100` instead of `0x02c9f040` ([[D054]] area). |
| Which **groups** exist | the device; FSP only emits a `BSP_CFG_OPTION_SETTING_*` for what the user sets | A group enabled in e2 that the port does not emit is **dropped with no diagnostic**. OFS2, OFS3_SEC and OFS3_SEL were configured and dropped exactly this way. |
| **Placement** | `ra8m2_bl2.ld` MEMORY + sections, `ra8m2_bl2.icf` region + keep + place | One coalesced `PT_LOAD` zero-fills the gaps and programs block-protect to 0 → permanent brick ([[D002]]). Invisible in the srec. |

**The checks that now exist for it**, and the pattern the rest of the document should follow —
each hazard gets a mechanism, not a comment:

- `bl2_option_setting.c` ends in a guard listing every `BSP_CFG_OPTION_SETTING_*` FSP knows for
  the part that the port does **not** place; any of them being set is an `#error` naming the
  three edits needed. Verified to fire for `BPS` and `OTP_PBPS_SEC`, and correctly not to fire
  for the `OFS1_SEC_NO_HOCOFRQ` variant.
- `check_ofs.py` now **requires** its region: it used to hardcode RA6's `0x0100A100` window and,
  run against an RA8M2 BL2 carrying six OFS segments, printed *"CLEAN (no OFS segments) …
  safe to flash"*. A guard pointed at the wrong window is worse than none, because it reads as
  verification. BL2 additionally passes `--require-segments`, so an empty result fails.
- `readelf -l` on the linked ELF is the only place the coalescing is visible.

**FSP linker inputs, and what the port does with each** — the inventory this section needs:

| FSP file | Port's treatment |
|---|---|
| `Debug/bsp_linker_info.h` | **consumed**, filtered to `bsp_partitions.h` (macros only; it also declares C types and a `flash_map[]` that would collide) |
| `Debug/memory_regions.icf` | **consumed**, filtered to `option_settings.h` for the OFS addresses |
| `bsp_linker.c` | **excluded** from the build; its OFS emission is reimplemented in `bl2_option_setting.c`, its init tables stubbed in `bsp_init_stub.c`, and its `gp_ddsc_*` definitions replaced by `ra8m2_ddsc.c` |
| `Debug/fsp_gen.icf`, `script/fsp.icf`, `Debug/fsp_gen.ld` | **unused** — TF-M supplies its own scripts. Worth stating: they are the reference for what FSP would have done, and were the source for the discrete-region pattern. |
| port-owned | `ra8m2_bl2.ld`, `ra8m2_bl2.icf`, `ra8m2_fsp_sections.icf` |

**Sequencing.** Write this BEFORE the pack uprev in PROJECT_PLAN.md's TODO, not after — the uprev is
exactly the event it is meant to survive, and doing it second means auditing from memory.
