# TODO — a self-contained documentation set

**Status: not started.** This file is the plan and the gap list, not the documentation. It exists so
the work is scoped and ordered rather than started three times from different ends.

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

| File | Lines | Character |
|---|---|---|
| `TFM_EXECUTION_FLOW.md` | 1271 | Reference — boot path walkthrough |
| `TFM_RA6M4_STATUS.md` | 644 | **Status + running TODO**, part historical |
| `RA6E1_SOLUTION.md` | 609 | **Status + resolved-issue log**, the de-facto RA6E1 reference |
| `TFM_FSP_NS_BUILD_GUIDE.md` | 483 | Guide — predates the split SPE/NSPE build (D005); **verify before trusting** |
| `TFM_NS_FREERTOS_TEST.md` | 461 | Guide — RA6M4 FreeRTOS NS app |
| `TFM_INTEGRATION_COMPLETE.md` | 375 | Historical milestone write-up |
| `BUILD_TEST_RESULTS.md` | 374 | Historical results |
| `DECISIONS.md` | 369 | Decision log (append-only) |
| `DESIGN.md` | 298 | Architecture + rationale |
| `TRUSTZONE_FREERTOS_REQUIREMENTS.md` | 231 | Reference — TZ/RTOS constraints |
| `UPSTREAM_CHANGES.md` | 226 | **Patch queue** — changes to common TF-M files, destined for TrustedFirmware-M |
| `RA6E1_TEMPLATE_CHECKLIST.md` | 208 | Checklist — what a RASC template must emit |
| `RA8x2_DUAL_CORE_DESIGN.md` | 185 | Forward design |
| `MACHINE_HANDOFF.md` | 171 | **Transient** — retire once the two machines are reconciled |
| `PROJECT_PLAN.md` | 164 | Schedule |
| `RASC_PROJECT_SETUP.md` | 147 | Guide — RASC project creation |
| `README.md` | 2 | Stub |

Roughly: two files carry most of the operational truth (`RA6E1_SOLUTION.md`, `TFM_RA6M4_STATUS.md`)
and both are structured as engineering diaries. That format earned its place — the reversals in it
are worth keeping — but it is not what a user reconfiguring the port needs, and status logs age badly
because nothing tells you which entries are still true.

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

**Port-specific build options.** `FSP_BL2_APP_DIR` · `FSP_S_APP_DIR` · `FSP_NS_APP_DIR` ·
`USE_FSP_MODULES` · `FSP_MODULES` · `RA6E1_STDOUT_RTT` / `RA6M4_STDOUT_RTT` ·
`RA6E1_NS_IN_SPE_BUILD` (default OFF) / `RA6M4_NS_IN_SPE_BUILD` (default ON, D009) ·
`RA6E1_BL2_HALT_AT_MAIN` · `RA6E1_ORPHAN_CHECK_STRICT` · `RA6M4_BL2_HALT_AT_MAIN` (not a cache
variable — fix) · `TFM_SPM_DEBUG_TRACE` · `TFM_EXCEPTION_INFO_DUMP` ·
`PLATFORM_HAS_ISOLATION_L3_SUPPORT` (D008).

**TF-M settings the port pins,** where a user needs to know the port has an opinion:
`TFM_ISOLATION_LEVEL` · `CONFIG_TFM_SPM_BACKEND` · the five `TFM_PARTITION_*` · the
`PLATFORM_DEFAULT_*` set · `PS_ENCRYPTION` · `PS_CRYPTO_AEAD_ALG` · `CRYPTO_HW_ACCELERATOR` ·
`SYMMETRIC_INITIAL_ATTESTATION` · `PSA_INITIAL_ATTEST_MAX_TOKEN_SIZE`. Note explicitly that these
cache defaults **beat `TFM_PROFILE`** — the trap behind D007.

**MCUboot / layout:** `MCUBOOT_IMAGE_NUMBER` · `MCUBOOT_ALIGN_VAL` (128; flag day — images signed at
another value are rejected) · `MCUBOOT_UPGRADE_STRATEGY` · `MCUBOOT_SIGNATURE_TYPE` ·
`MCUBOOT_HW_KEY` · `MCUBOOT_DATA_SHARING` · `MCUBOOT_MEASURED_BOOT` · `FLASH_AREA_BL2_*`.

**Header-level tunables** — not cache variables, but the ones people actually need to change, and the
ones with non-obvious constraints:

| Symbol | Where | Constraint to document |
|---|---|---|
| `S_RAM_CODE_SIZE` | `region_defs.h` | `0xA00` for `0x7d0` of code plus an ld-inserted veneer. Overflow → `region CODE_RAM overflowed`. Revisit on FSP uprev. |
| `S_RAM_CODE_EXTRA_SECTION_NAME` | `region_defs.h` | Bare ld pattern, not a quoted string |
| `S_DATA_EXTRA_NOINIT_SECTION_NAME` | `region_defs.h` | Must stay outside `__bss_start__..__bss_end__`, NOLOAD (D012) |
| `PS_NUM_ASSETS` | `config_tfm_target.h` | Capped at 5 by PS block capacity; **erase data flash before first boot after any change** |
| `PS_MAX_ASSET_SIZE` | `config_tfm_target.h` | Not the binding constraint — capacity is a sum |
| `TFM_NV_COUNTERS_AREA_SIZE` | `flash_layout.h` | Fixed 2048 B; PS and ITS split what remains |
| `TFM_HAL_PS_SECTORS_PER_BLOCK` | `flash_layout.h` | `(area/sector)/2` — `num_blocks < 2` fails ITS/PS init outright |
| `MCUBOOT_ALIGN_VAL` / trailer | `flash_layout.h`, solution | `0x180` at align 128; must fit the NSC window above the veneers |
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
