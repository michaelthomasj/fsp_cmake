# Decision log — TF-M on Renesas RA

An append-only, chronological record of decisions and **why** they were made. Separate from
`DESIGN.md` on purpose: DESIGN.md describes how the port works *now*, this file records how it
came to work that way, including the turns that were later reversed.

## Rules

1. **Entries are never edited once written.** Not to soften them, not to bring them up to date.
2. **A decision that changes gets a NEW entry** at the end, with `Supersedes: Dxxx`. The old entry
   gets one line appended — `Superseded by Dyyy` — and nothing else about it changes. The old
   rationale is the point: it records what was believed at the time, which is what makes the
   reversal informative.
3. **Numbers are permanent.** Never renumber, never reuse. A withdrawn decision stays in place.
4. **Correcting a factual error inside an entry is still a new entry.** If an entry asserts
   something untrue, supersede it. Silent repair destroys the record of having believed it.
5. **Record the alternatives that were rejected, and why.** An entry that lists only what was
   chosen cannot be re-evaluated later.
6. Entries dated before this file existed are **back-filled** and say so, with the source they were
   reconstructed from. Their dates are the dates of the decision, not of the write-up.

Statuses: `Accepted` · `Superseded by Dxxx` · `Provisional` (taken, not yet validated) ·
`Withdrawn` (abandoned without a replacement).

---

## D001 — Option-setting (OFS) memory must never be linked into an image

**Date:** 2026-07-21 · **Status:** Superseded by D002 · **Back-filled** from commit `c78602fff` and
`TFM_RA6M4_STATUS.md`.

**Context.** Two EK-RA6M4 boards were permanently bricked by a BL2 image carrying the thirteen
option-setting words at `0x0100A100`–`0x0100A2CC`. After flashing, the parts read back `0xDA` and
were unrecoverable — the FSPR permanence word had been cleared, latching block protection on.

**Decision.** Remove OFS emission from BL2 entirely. Treat option memory as something firmware
images must never contain; program it only with RFP or the Device Partition Manager.

**Rationale.** The images were the only thing that touched option memory, and removing them stopped
the damage. Three "never re-add this" warnings were placed in the source.

**Rejected.** Investigating *why* the words were destructive — the boards were already dead and the
cost of another wrong guess was another board.

**Consequence.** Correct in effect, wrong in diagnosis, and it discarded a feature the port needs.
Cost about three weeks of carrying a false lesson in the source.

---

## D002 — Each OFS group gets its own linker `MEMORY` region

**Date:** 2026-08-10 · **Status:** Accepted · **Supersedes:** D001 · **Back-filled** from
`DESIGN.md` §8.4 and `MACHINE_HANDOFF.md` §1.1.

**Context.** Re-examination of the brick found the real mechanism. `ra6m4_bl2.ld` emitted the option
words as bare addressed sections with **no `> REGION` assignment**, so GNU ld coalesced all of them
into a single `PT_LOAD` spanning `0x0100A100`–`0x0100A2CC` and zero-filled the 368 bytes of FCU
configuration lying between them — including the FSPR permanence word. A debugger flashes by program
header, so it wrote those zeros. FSP's own generated linker gives each option group its own `MEMORY`
region and therefore cannot produce a spanning segment.

**Decision.** Restore OFS emission, with thirteen discrete `MEMORY` regions and a `> REGION`
assignment on every `.option_setting_*` section. Verify with `readelf -l`, never with the srec.

**Rationale.** It was never option memory in an image that was dangerous — it was the *gap fill*
between sparse sections in one segment. The srec never showed the zeros because `objcopy -O srec`
emits from sections, not program headers, which is why the earlier diff-the-srec check (`d7df90820`)
passed on an image that destroyed hardware.

**Rejected.** Keeping D001 and programming OFS externally forever — it makes every board need a
separate provisioning step and leaves the port unable to ship a bootable image.

**Consequence.** Verified byte-identical to the known-good values on both platforms. Later made
automatic: `check_ofs.py` runs post-link on `bl2` and `tfm_s` as a hard failure, so the check no
longer depends on someone remembering `readelf`.

---

## D003 — RA6E1 replaces RA6M4 as the RA6 development vehicle

**Date:** 2026-08-25 · **Status:** Accepted · **Back-filled** from `RA6E1_SOLUTION.md` and
`PROJECT_PLAN.md`.

**Context.** Both EK-RA6M4 boards were destroyed by D001's root cause. No replacement was to hand;
an EK-RA6E1 was.

**Decision.** Bring the port up on RA6E1 and keep RA6M4 building but unverified on hardware.

**Rationale.** Same Cortex-M33, same TrustZone model, byte-identical option-setting map, so nearly
everything transfers. Waiting for RA6M4 hardware would have stalled the whole schedule.

**Consequence.** RA6E1 is now considerably ahead: it has the solution project set, the split build
and a passing regression suite, while RA6M4 has none of them. Every RA6M4 defect found since has
been found by reading, not by running.

---

## D004 — Drive the flash layout from a RASC *solution*, not standalone projects

**Date:** 2026-08-25 · **Status:** Accepted · **Back-filled** from `RA6E1_SOLUTION.md`.

**Context.** MCUboot needs a shared, consistent view of the slots across bootloader, secure and
non-secure images. The partition symbols (`__BL_0/1_P/S_*`) that express it are emitted into each
project's generated `bsp_linker_info.h` and `memory_regions.ld` **by the solution**.

**Decision.** Use a four-project RASC solution (`ra6e1`, `ra6e1_mcuboot`, `ra6e1_secure`,
`ra6e1_nonsecure`) and have the TF-M port read the generated layout from it.

**Rationale.** A standalone project cannot produce those symbols, so the three images would each
carry an independently maintained copy of the layout — the class of divergence that links cleanly
and boots nowhere.

**Consequence.** An e2 studio build is now a prerequisite for building TF-M, because the layout
lives in `<project>/Debug/`, which is not committed. Accepted deliberately; the standing TODO to
bundle a default project set inside the port is what removes it.

---

## D005 — Build the NS image in its own CMake project against the installed `api_ns/`

**Date:** 2026-08-30 · **Status:** Accepted · **Back-filled** from `RA6E1_SOLUTION.md`.

**Context.** The NS application could not call a PSA API. `tfm_api_ns` is created by the NSPE build
from the installed tree and cannot exist in the SPE build, so linking it there yields
`cannot find -ltfm_api_ns`.

**Decision.** Split the build: SPE builds and installs `api_ns/`, a separate NSPE project builds and
signs the NS image against it. Keep the old single-build path behind `RA6E1_NS_IN_SPE_BUILD`,
default OFF.

**Rationale.** Required, not preferred — it is the only arrangement in which NS code can make secure
calls, and it is what the official `tf-m-tests` and `tests_psa_arch` suites build against.

**Consequence.** Everything downstream depends on it. RA6M4 never got this conversion, which is
exactly why it cannot run any test suite today (D009).

---

## D006 — Use TF-M's shared isolation HAL and generated secure linker, not port-owned copies

**Date:** 2026-08-26 · **Status:** Accepted · **Back-filled** from the port's `CMakeLists.txt` and
`region_defs.h`; the rationale below was made explicit on 2026-09-08 after the L3 work, but the
decision itself is what the port has always done.

**Context.** Two related choices. First, whether to implement `tfm_hal_isolation.c` in the port or
use `platform/ext/common/tfm_hal_isolation_v8m.c`. Second, whether to ship a platform-owned secure
linker script — as `TFM_RA6M4_STATUS.md` proposes in a standing TODO, citing STM32 — or use TF-M's
generated `tfm_isolation_s.ld` and steer it with the `#ifndef`-overridable macros in
`region_defs.h`.

**Decision.** Shared HAL, generated linker. Where placement must be controlled — pinning the NSC
veneer window — do it with `TFM_LINKER_VENEERS_START` / `TFM_LINKER_VENEERS_LOCATION_END` in
`region_defs.h` rather than by forking the script.

**Rationale.** The RA6 parts need nothing the shared HAL does not already do: one contiguous secure
region set by the IDAU, no MPC, no PPC, a stock ARMv8-M MPU. A port-owned copy would begin as a
copy and then diverge silently on every TF-M uprev.

**Rejected.** The platform-owned linker model. `TFM_RA6M4_STATUS.md` argues for it so that
`region_defs.h` macros *are* the section origins and the C view cannot disagree with the image. The
veneer macros solve that specific problem without the fork.

**Consequence, measured 2026-09-08.** Isolation level 3 cost one line — declaring
`PLATFORM_HAS_ISOLATION_L3_SUPPORT` (D008). The shared HAL already contained the whole L3 mechanism,
and the generated linker already emits the per-partition sections it binds MPU regions to
(`PT_UNPRIV_CODE`, `PT_APP_ROT_CODE`, `PT_PSA_ROT_DATA`, `TFM_SP_META_PTR`). Under a port-owned
linker every one of those sections would have been hand-written.

**Note for whoever revisits the RA6M4 TODO.** Its premise is inaccurate for the platform it names.
Of the upstream ports, only `stm32h5xx`, `stm32u5xx`, `stm32wbaxx` and `rpi/rp2350` ship their own
secure linker; `stm32l5xx` — the family behind `stm32l562e_dk` — uses the *generated* one and still
supports L3.

---

## D007 — Run the PSA Arch tests at `profile_large` with the port's defaults overridden

**Date:** 2026-09-07 · **Status:** Accepted

**Context.** `tests_psa_arch/spe/config/check_config.cmake` rejects `TEST_PSA_API=CRYPTO` unless
`TFM_PROFILE=profile_large`. That profile selects isolation 3 and the IPC backend; the port's
`config.cmake` sets isolation 1 and SFN, and its cache defaults win over the profile.

**Decision.** Build the test images with `-DTFM_PROFILE=profile_large -DTFM_ISOLATION_LEVEL=3
-DCONFIG_TFM_SPM_BACKEND=IPC -DTFM_SPM_DEBUG_TRACE=OFF`, leaving the port's own defaults untouched.

**Rationale.** The suite intends to exercise every PSA crypto API, which is what profile_large's
crypto configuration provides; a reduced config would silently skip tests rather than fail them. IPC
is not optional — profile_large enables the doorbell API, and SFN with it is rejected outright by
`config_spm.h`. `TFM_SPM_DEBUG_TRACE` must be off because the port's own `check_config` rejects it
outside a Debug build, where `TFM_SPM_LOG_LEVEL` defaults to SILENCE.

**Rejected.** Changing the port's defaults to match the profile. The defaults are right for the
product; the test configuration is a build-time override and should stay one.

**Consequence.** The test build differs from the shipping configuration in isolation level, SPM
backend and log level. Results must be read with that in mind — this validates the crypto
implementation, not the shipping build's configuration.

---

## D008 — Declare `PLATFORM_HAS_ISOLATION_L3_SUPPORT` for RA6E1

**Date:** 2026-09-08 · **Status:** Provisional — builds, not yet run on hardware

**Context.** `config/check_config.cmake` rejects isolation 3 unless the platform claims support.
There is no equivalent gate on level 2. Nothing platform-specific implements L3 here (D006).

**Decision.** Declare it in `platform/ext/target/renesas/ra6e1/config.cmake`, leaving the port's
default at level 1.

**Rationale.** The shared HAL implements L3 and the RA6E1 MPU meets its needs. Static region count
for this configuration (PXN off, L3, `CONFIG_TFM_PARTITION_META` on) is **five** — combined
unprivileged/ARoT code, PSA RoT code, RO data, partition metadata pointer, PSA RoT data — plus one
reserved private-data region, so six of the eight the Cortex-M33 is expected to provide. The port
adds no `PLATFORM_STATIC_MPU_REGIONS` and no partition claims MMIO regions, so nothing port-specific
inflates that.

**Provisional, and why.** The flag asserts the port has been built *and run* at L3; only the first
is true today. Two things are unproven: the region budget is checked at runtime against `MPU->TYPE`,
and the eight-region figure has not been confirmed against the hardware manual; and
`CONFIG_TFM_ENABLE_MEMORY_PROTECT` is only defined above level 1, so **this port has never
programmed the MPU on hardware at all**. Failure is loud — `TFM_HAL_ERROR_GENERIC` from
`tfm_hal_set_up_static_boundaries()`, i.e. an early panic — not subtle. If the hardware run fails,
this flag comes back out rather than staying as an aspiration.

**Cost measured:** +972 bytes of secure text over L1 (124,183 vs 123,211), bss unchanged.

**Confirmed by D015 (2026-09-08).**

---

## D009 — RA6M4 keeps its in-SPE NS app by default, behind a switch

**Date:** 2026-09-07 · **Status:** Accepted

**Context.** RA6M4 added its NS application unconditionally whenever `FSP_NS_APP_DIR` was set. Every
flow that builds the SPE alone and supplies its own NS image — `tf-m-tests`, `tests_psa_arch` —
therefore died at `ninja: error: 'bin/tfm_ns.bin' ... missing and no known rule to make it`: the FSP
integration created the `tfm_ns` target, so BL2's signing step wired itself up, but no build rule
ever produced the binary behind it.

**Decision.** Add `RA6M4_NS_IN_SPE_BUILD`, defaulting **ON** — the mirror of RA6E1's switch, but
with the opposite default.

**Rationale.** RA6E1 defaults OFF because its split build works. RA6M4's does not: its
`api_ns/platform/cpuarch.cmake` installs empty and roughly twenty other NS-side files RA6E1 exports
are not exported at all. Defaulting OFF would break the one RA6M4 flow that currently works in
exchange for one that does not yet exist.

**Consequence.** The default flips to OFF when RA6M4 gets D005's conversion. Until then RA6M4 can
build a test SPE only by passing the switch explicitly.

---

## D010 — Pass the `g_main_stack` alias through a linker response file

**Date:** 2026-09-07 · **Status:** Accepted

**Context.** FSP's `SystemInit()` derives MSPLIM from `&g_main_stack[0]`, which must alias the
image's real stack, `Image$$ARM_LIB_STACK$$ZI$$Base`. The symbol is defined by the linker script, so
neither `__attribute__((alias))` nor an assembler `.set` can express it — it was done with
`--defsym`. How many `$` a CMake string needs to survive as two on the link line turned out to be
CMake/Ninja version dependent: the literal worked under CMake 3.27.6 / Ninja 1.11.1 and failed under
4.1.1 / 1.13.1, which halved it, giving ``undefined symbol `Image$ARM_LIB_STACK$ZI$Base` ``.

**Decision.** Write the option to a response file with `file(WRITE)` and pass `-Wl,@file`.

**Rationale.** CMake writes the bytes verbatim and ld reads them verbatim, so no escaping layer is
left to disagree. Any literal-`$` spelling is correct for exactly one toolchain generation.

**Rejected.** Detecting the CMake version and branching — it encodes the bug rather than removing
it, and would need revisiting on every upgrade.

**Consequence.** Builds identically on both machines. The verification commands in the comment
changed accordingly: check the `.rsp` file, then `nm` the image.

---

## D011 — Guard the secure-only half of `tfm_hal_platform.c` on a port-private macro

**Date:** 2026-09-07 · **Status:** Accepted

**Context.** Both RA ports compile `tfm_hal_platform.c` into `platform_bl2`. Under
`MCUBOOT_FIH_PROFILE=MEDIUM` — which `profile_large` selects — `fih_ret` and `fih_int` are different
types, and `tfm_hal_platform_init()` returns one where the other is expected. The default FIH
profile is OFF, so this compiled for months.

**Decision.** Guard the secure-only functions on `RA6E1_BUILDING_BL2` / `RA6M4_BUILDING_BL2`, set on
`platform_bl2` alone.

**Rationale.** The file cannot simply be dropped from BL2, as upstream `an521` does: it defines
`__STACK_SEAL`, which anchors `.msp_stack_seal_res`, from which the BL2 linker resolves the
`__StackSeal` that FSP's `Reset_Handler` references. Dropping it fails the link. The plain `BL2`
macro cannot serve as the discriminator either — it is defined for *every* image in the build
whenever BL2 is enabled, so guarding on it deletes the same symbols from `tfm_s`.

**Consequence.** Two more port-private macros. The tidier end state is to move `__STACK_SEAL` where
BL2 can get it without the rest of the file, at which point the guard and the macro both go.

---

## D012 — When the generated linker lacks a hook, add a generic one upstream rather than fork

**Date:** 2026-08-30 · **Status:** Accepted · **Refines:** D006 · **Back-filled** from commits
`fbc84be86` and `103520f23`.

**Context.** D006 chose TF-M's generated secure linker. Two FSP sections then needed placement it
did not provide. `.ram_from_flash` was already covered — `S_RAM_CODE_START` /
`S_RAM_CODE_EXTRA_SECTION_NAME` are upstream hooks nothing else uses, so defining them in
`region_defs.h` was the whole fix. `.ram_noinit` had no hook at all and was being orphaned: ld
invented an output section and, the input being PROGBITS, gave it a load address — 110 bytes of
flash holding initialisers no copy-table entry copies, landing inside the 2 KB NSC window, and
escaping the C-runtime's zeroing only because the orphan happened to fall below `__bss_start__`.

**Decision.** Add a **generic, macro-gated** hook to the shared template —
`S_DATA_EXTRA_NOINIT_SECTION_NAME`, emitting `.TFM_NOINIT ALIGN(4) (NOLOAD)` ahead of `.TFM_BSS` —
written and commented as an upstream contribution, taking an ld pattern so any platform can name
its own sections. Same for the `.ER_CODE_SRAM` ordering fix.

**Rationale.** The problem is not RA-specific: any vendor BSP with no-init state has it, and the
symptom is silent. A fork would have fixed it for this port and left it broken everywhere else,
while acquiring a file that diverges on every uprev — which is exactly what D006 exists to avoid.

**Rejected.** Allowlisting the orphan in the port's orphan-section check. That was the interim
state; it records the section as "placed by guesswork and known about", which is not the same as
placed correctly, and it left the wasted flash and the zeroing hazard in place.

**Consequence.** The rule for this port: an unplaced vendor section means look for an override macro
first, add a generic hook second, fork last. Only `ra6e1_bl2.ld` is genuinely forked, and only
because it also carries the thirteen OFS `MEMORY` regions from D002.

---

## D013 — Keep TF-M's `flash_map[]` and area IDs; do not adopt the solution's

**Date:** 2026-09-08 · **Status:** Accepted

**Context.** Raised when an earlier claim of mine was challenged and turned out to be wrong. The port
filters the solution's `bsp_linker_info.h` down to its `#define BSP_PARTITION_*` lines, and both
`CMakeLists.txt` and `DESIGN.md` §4 justified part of that by saying the file "carries FSP's own
MCUboot flash identity, which conflicts with TF-M's dual-image flash_map". **It does not.** The
solution's bootloader is `MCUBOOT_IMAGE_NUMBER 2`; its generated `flash_map[]` has all four entries —
both images, primary and secondary — computed from the same `BSP_PARTITION___BL_*` macros this port
derives `FLASH_AREA_*_OFFSET` from, so the two maps describe byte-identical offsets. The stale claim
described the standalone RASC BL2 project of July 2026, which was single-image and has since been
removed.

**Decision.** Unchanged in effect: TF-M's `flash_map` and area IDs, and keep filtering the header.

**Rationale, corrected.** Two narrow reasons, neither of them a layout disagreement:

1. `bsp_linker_info.h` defines `static const struct flash_area flash_map[]` under `#ifdef
   FLASH_MAP_C`, which would collide with TF-M's own definition of that object.
2. The **area-ID conventions differ**, so the two must never be mixed inside one image:

   | area | FSP | TF-M |
   |---|---|---|
   | secure primary | `FLASH_AREA_0P_ID` 1 | `FLASH_AREA_0_ID` 1 |
   | secure secondary | `FLASH_AREA_0S_ID` 2 | `FLASH_AREA_2_ID` 3 |
   | NS primary | `FLASH_AREA_1P_ID` 3 | `FLASH_AREA_1_ID` 2 |
   | NS secondary | `FLASH_AREA_1S_ID` 4 | `FLASH_AREA_3_ID` 4 |

The independent reason for filtering is unaffected: the header also declares C types and externs that
cannot survive being preprocessed as a linker script.

**Consequence.** Since the layouts now agree, adopting the solution's map is a real option rather
than a blocked one — it would delete the port's `FLASH_AREA_*` block in favour of generated code.
Not taken: the IDs are woven into bootutil, `Driver_Flash` and the signing wrapper, and the ID
remapping buys nothing. Worth revisiting only if the offsets ever drift, which the identical
derivation currently prevents.

---

## D014 — The PSA Arch test tree is a local clone with tf-m-tests' patches applied by hand

**Date:** 2026-09-08 · **Status:** Provisional — works, but the manual step is a known hazard

**Context.** `tests_psa_arch` needs a target directory that does not exist upstream
(`tgt_dev_apis_tfm_ra6e1`), so the tree has to be editable. Pointing `PSA_ARCH_TESTS_PATH` at a local
clone achieves that — and silently skips the ten patches tf-m-tests carries in
`tests_psa_arch/fetch_repo/`. `cmake/remote_library.cmake` applies them only under
`(SOURCE_PATH_IS_DOWNLOAD OR FORCE_PATCH)`, and `spe/CMakeLists.txt` does not even add the
`fetch_repo` subdirectory when the path is supplied. Nothing warns.

**Cost of finding out.** A full hardware run of the crypto suite reported one failure —
`psa_verify_hash` check 13, `PSA_ALG_RSA_PSS_ANY_SALT`, `-135` (`PSA_ERROR_INVALID_ARGUMENT`). It was
neither a port defect nor a crypto-config gap: patch `0008` replaces that case's key data
(`rsa_key_pair_public_key`/162 bytes → `rsa_128_key_data`/140) because the original is in the wrong
format. The unpatched suite fails it on any platform.

**Decision.** Keep the local clone, apply all ten patches to it with `git apply`, and treat "are the
patches applied?" as a pre-run check rather than an assumption.

**Rejected.** Letting the build download and patch the tree, and carrying the RA6E1 target as an
eleventh patch. Cleaner in principle and probably right eventually — it is also how the target would
be upstreamed — but it makes editing the target a patch-refresh cycle, which is the wrong trade while
the target is still being developed.

**Consequence.** A build from a fresh clone of psa-arch-tests is *not* equivalent to a build from the
downloaded tree, and the difference shows up as test failures that look like port defects. Whoever
writes `BUILDING.md` should record the patch step; whoever revisits this should reconsider the
rejected option once the target settles.

---

## D015 — Isolation 3 + IPC confirmed on hardware; D008 is no longer provisional

**Date:** 2026-09-08 · **Status:** Accepted · **Confirms:** D008

**Context.** D008 declared `PLATFORM_HAS_ISOLATION_L3_SUPPORT` on the strength of a build and a
static region count, and said explicitly that the flag asserts the port has been built *and run* at
L3 while only the first was true. Two things were unproven: the MPU region budget, checked at runtime
against `MPU->TYPE`, and the fact that `CONFIG_TFM_ENABLE_MEMORY_PROTECT` is only defined above
isolation 1 — so the port had never programmed the MPU on hardware at all.

**Evidence.** The full PSA Arch crypto suite ran to completion on EK-RA6E1 with
`TFM_ISOLATION_LEVEL=3` and `CONFIG_TFM_SPM_BACKEND=IPC`, every visible `TEST RESULT` reading
PASSED. `tfm_hal_set_up_static_boundaries()` returning `TFM_HAL_ERROR_GENERIC` would have panicked
during SPM init, long before any test ran, so the five static regions plus one private-data region
fit the MPU this part provides. The IPC backend, also new on hardware and forced by profile_large's
doorbell API, is exercised by every PSA call the suite makes.

**Decision.** Treat D008 as validated. The flag stays.

**Not covered by this.** The transcript has RTT dropouts and no end-of-suite summary was captured, so
"no failure appeared" is not the same as a certified clean sweep — see the note on
`SEGGER_RTT_MODE_NO_BLOCK_SKIP` and the 1 KB up-buffer. Isolation 2 has never been built or run. And
a single unexplained BL2 stop was observed between runs and has not been reproduced or diagnosed;
the diagnostic BL2 built with `MCUBOOT_LOG_LEVEL=INFO` exists to catch it if it recurs.

---

## D016 — RA6M5 is the upstream target; RA6M4 is skipped

**Date:** 2026-09-09 · **Status:** Accepted · **Changes the plan recorded in** D003, D009

**Context.** D003 made RA6E1 the development vehicle after both EK-RA6M4 boards were destroyed,
keeping RA6M4 as the intended deliverable. Surveying what RA6M4 actually needs changed that: its
`flash_layout.h` contains **zero** `BSP_PARTITION` references against RA6E1's 24, so D004 —
solution-derived layout — was never applied to it at all; it consumes standalone FSP 6.1 projects
that structurally cannot emit the `__BL_0/1_*` symbols MCUboot needs. Its NS export is one
`install()` block against RA6E1's seven, so D005 is missing too. Add its three known code defects
and the fact that no working board exists.

**Decision.** Skip RA6M4. Take the port from RA6E1 to **RA6M5**, which is the platform that will be
contributed upstream. A board will be available for verification.

**Rationale.** RA6M4's only advantage was an existing platform directory, and that directory has to
be rewritten to be solution-derived regardless — so it is not a shortcut to RA6M5, it is a detour
with its own bring-up. Both parts need a new RASC solution and neither has working hardware today.
RA6M5's 2 MB flash and 512 KB SRAM also remove the fit pressure that shapes the RA6E1 layout.

**Rejected.** RA6E1 → RA6M4 → RA6M5. Would have re-run D004 and D005 twice and cost a board.

**Consequence.** The RA6M4 platform directory stays in the tree, building and unverified, with its
open defects unfixed. D009's `RA6M4_NS_IN_SPE_BUILD` switch stays as it is; the flip to OFF it
anticipated is not going to happen. Anything RA6M4-specific in the status docs should be read as
historical.

---

## D017 — The PSA Arch target stays a local patch for RA6E1; the RA6M5 one goes upstream

**Date:** 2026-09-09 · **Status:** Accepted · **Resolves the open question in** D014

**Context.** D014 left open whether `tgt_dev_apis_tfm_ra6e1` should be contributed to
ARM-software/psa-arch-tests or carried as an eleventh patch in `tf-m-tests/tests_psa_arch/fetch_repo/`
beside the three platform additions already there (Corstone-315/320, rp2350, Musca S1/B1).

**Decision.** RA6E1's target stays local and unpushed. When the RA6M5 port is complete and verified,
**that** target is the one upstreamed.

**Rationale.** RA6E1 is the development vehicle (D003), not the deliverable (D016). Upstreaming a
target for a platform that is not being contributed would commit to maintaining it, and psa-arch-tests
carries the same ongoing-maintenance expectation TF-M does. The RA6E1 target is also still moving —
`pal_crypto_config.h` is an unaudited an521 copy.

**Consequence.** Anyone reproducing the RA6E1 results needs the local target plus the ten fetch_repo
patches applied by hand, exactly as D014 describes. That reproduction gap is accepted for the
development vehicle and must not be carried into the RA6M5 contribution.
