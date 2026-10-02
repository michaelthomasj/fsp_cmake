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

---

## D018 — One RA-family PSA Arch target, named `tgt_dev_apis_tfm_renesas_ra`

**Date:** 2026-09-09 · **Status:** Accepted · **Refines:** D017

**Context.** The target was first written as `tgt_dev_apis_tfm_ra6e1`, matching the name
`tests_psa_arch` derives from the TF-M platform basename. Reviewing it for upstreaming showed
nothing in it is device-specific: UART and watchdog are declared unused, nvmem is a runtime
accessor, and printing goes through `tfm_log_printf`. The only build-dependent files are
`pal_crypto_config.h`, which tracks the TF-M *crypto configuration* rather than the silicon, and
`pal_storage_config.h`, whose UID size tracks `PS_MAX_ASSET_SIZE`.

**Decision.** One directory for the RA family, `tgt_dev_apis_tfm_renesas_ra`, selected with
`-DPSA_API_TEST_TARGET=renesas_ra`.

**Rationale.** Vendor+family is the honest scope: it covers RA4/RA6/RA8 without asserting a
maintenance claim beyond what is verified, and it matches the one upstream precedent for a shared
target, `tgt_ff_tfm_nrf_common`. The cost is that every NS build must pass `PSA_API_TEST_TARGET`,
since the default derivation would look for the device name.

**Rejected.** `ra6_ra4_cm33` — mixes two axes and asserts every Cortex-M33 device, which is untrue
in general: the core is not what the target depends on, the TF-M crypto config is. An RA8 on
Cortex-M85 works unchanged; an M33 with a different crypto config does not.
`tgt_dev_apis_tfm_ra6m5` — device-specific, exactly upstream convention, and no override needed;
rejected because a second RA device would then need a duplicate directory or a rename.

**Consequence.** D017 stands: this is the directory that gets upstreamed once RA6M5 is verified, and
the `Verified on:` line in `target.cfg` is the place that records which parts have actually been
run — RA6E1 today, RA6M5 to be added.

## D019 — The IAR secure image reaches FSP's sections through an included ICF fragment, not a section-name macro

**Context.** The GNU secure template takes vendor section names as preprocessor macros:
`S_RAM_CODE_EXTRA_SECTION_NAME` (upstream, 53c10c111) expands into `KEEP(*(...))`, and
`S_DATA_EXTRA_NOINIT_SECTION_NAME` (added here, fbc84be86) into `.TFM_NOINIT`. The obvious move was
to give `tfm_isolation_s.icf.template` the same two hooks and reuse the macros. It cannot be done.
iccarm re-emits a macro expansion token by token, and `.ram_from_flash` is two preprocessing tokens
(`.` and the identifier — `.r` is not a valid pp-number), so the expansion arrives at ILINK as
`. ram_from_flash` and the parse fails with `syntax error, unexpected 'ram'`.

Three spellings were tried and all fail:
- every `--preprocess` variant (`n`, `cn`, `l`, `sn`, `s`) inserts the space — it is not a flag choice;
- a quoted name, `section ".ram_from_flash*"`, is refused by the grammar: `no_tick_identifier`,
  and IAR's own shipped `.icf` files contain no quoted selector anywhere;
- keeping the `.` literal in the template and putting only the identifier in the macro still yields
  `. ram_from_flash`, because the space is inserted ahead of the expansion result, not inside it.

Literal text is unaffected. `ra6e1_bl2.icf`, which spells these same sections out, preprocesses and
links correctly through the identical pipeline — that contrast is what identified the cause.

**Decision.** The platform names one file, `S_ICF_PLATFORM_SECTIONS` = `"ra6e1_fsp_sections.icf"`.
`tfm_isolation_s.icf.template` includes it at four hooks, each with a different `TFM_ICF_HOOK_*`
defined around the `#include`, so a single platform file serves every insertion point:
`RAM_CODE_INIT` (inside `initialize by copy`), `RAM_CODE_MEMBERS` (inside `ER_CODE_SRAM`),
`DIRECTIVES` (top level, `do not initialize`), and `DATA_MEMBERS` (inside the `DATA` block).

A second finding is recorded with it, because it is not discoverable from the ICF documentation and
cost two wrong builds: the selector must be `ro section` in the `initialize by copy` directive and
`rw section` in the block. That directive *splits* the section — the flash half becomes initialiser
bytes, the RAM half flips to `rw`. Naming `ro` in the block captures the initialiser and leaves the
block empty (0 bytes, code still in flash); naming `rw` in the directive matches nothing, so no copy
is set up and the code stays in flash. Both were observed on the way to this. The template's own
pre-existing `ro object *libflash_drivers*` / `rw section .text` pair works the same way.

**Rationale.** The hook keeps the shape the common template already uses: optional, guarded, with no
platform name anywhere in it. The text ILINK sees is the text the platform wrote, which is the only
arrangement the preprocessor cannot corrupt. One file per platform rather than one per hook keeps the
platform side to a single addition.

**Rejected.** Quoted section names — refused by the ICF grammar. A dot-literal template with a
dot-less macro — still splits. Forking `tfm_isolation_s.icf.template` into the platform directory —
a 460-line upstream file to re-sync on every TF-M update, for two sections; the GNU side deliberately
took upstream hooks instead, and this follows it.

**Consequence.** The GNU macros are unchanged and still drive the GNU build; the fragment and the
macros name the same two sections and must be kept in step — a section that matters under one
toolchain matters under both. Verified on the RA6E1 secure image: `flash_hp_cf_write` at
`0x2001f2c9`, `flash_hp_cf_erase` at `0x2001f399` and `flash_hp_enter_pe_cf_mode` at `0x2001f64b`,
all at `S_RAM_CODE_START` with flash veneers branching to them, the initialiser left in flash at
`0x7397c`, and all five `.ram_noinit` contributors `uninit` at `0x2000ca38`, where `SystemCoreClock`
also resolves. The RA6M5 port needs the same fragment.

## D020 — `g_main_stack` is redirected, not defined, under IAR; one response file serves both images

**Context.** D010 records why FSP's `g_main_stack` is aliased to TF-M's stack with a GNU `--defsym`
through a response file. IAR needs the same result by a different route: ILINK has no block-address
expression, so there is nothing in the `.icf` to alias a symbol *to*, and the link fails with
`Error[Li005]: no definition for "g_main_stack"`. Other TF-M ports were checked first, as none of
them solve this with linker aliasing — TF-M maps `__STACK_LIMIT`/`__INITIAL_SP` per toolchain in
`cmsis_override.h`, onto the same `ARM_LIB_STACK$Base` symbol ILINK creates for the `.icf` block.

**Decision.** Redirect the *reference* instead of defining the symbol:
`--redirect g_main_stack=ARM_LIB_STACK$Base`, written to a response file for the same reason D010
gives — `file(WRITE)` emits the bytes verbatim, so no CMake/Ninja `$`-escaping layer can disagree.
The response file is defined once, next to the GNU one, and applied to both `tfm_s` and `bl2`.

**Rationale.** It targets the symbol ILINK already creates for the stack block, which is the same one
TF-M's own `cmsis_override.h` uses for IAR, so the two agree on which stack the CPU is running on.

**Consequence.** D010 stands for GNU and is unchanged. Both mechanisms now cover both images.

## D021 — FSP 6.6 `.icf` files need `with alignment preservation` removed to build under IAR 9.50.2

**Context.** The RASC solution generates `initialize manually with alignment preservation {rw};` in
`fsp_gen.icf`. IAR 9.50.2's ILINK rejects it: `Error[Lc003]: expected "copy routine", "packing",
"complex", or "simple"`. The clause is newer than that toolchain.

**Decision.** Remove `with alignment preservation` when building an FSP-generated `.icf` under
9.50.2. Confirmed to build after the edit.

**Consequence.** Affects the e2 studio reference projects used as templates, not the TF-M `.icf`
files written here, which do not use the clause. Anyone regenerating from RASC on a newer FSP with an
older IAR hits it again.

## D022 — The non-secure image under IAR: four toolchain branches, not a fork

**Context.** The NS image is the only one of the three that links FSP's own generated linker
script (D005), so it is the only one where the toolchain difference reaches outside TF-M. Four
things differ between GNU and IAR, and each could have been "solved" by forking the NS build.

**Decision.** Four narrow branches, all keyed on `CMAKE_C_COMPILER_ID`:

- `ns/CMakeLists.txt` selects `script/fsp.icf` instead of `script/fsp.ld` for
  `INTERFACE_LINK_DEPENDS`. Read with `get_target_property()` and tested with `EXISTS` at
  CONFIGURE time, so it cannot be a generator expression - it has to be an `if()`.
- `--config_search <dir>` replaces `-L <dir>`. `fsp.icf` is a two-line stub that includes
  `memory_regions.icf` and `fsp_gen.icf` by bare name; `--config_search` is ILINK's exact
  counterpart to ld's `-L` for resolving those.
- `--wrap hal_entry` replaces `-Wl,--wrap=hal_entry`. ILINK has `--wrap` with the same
  `__wrap_`/`__real_` convention, verified on the linked image: `main` calls
  `__wrap_hal_entry`, which calls the real `hal_entry`. `rtt_ns_init.c` is unchanged between
  toolchains - only the spelling of the option differs.
- The `memory_regions.ld` existence guard in `ns_app/CMakeLists.txt` looks for
  `memory_regions.icf` under IAR. A GCC solution emits `.ld`, an IAR one `.icf`.

`ns/syscalls_ns.c` is split differently, because it is a source file rather than an option:
the newlib syscall family (`_close`/`_fstat`/`_isatty`/`_lseek`/`_read`/`_write`, and
`<sys/stat.h>`) stays under `#else`, and an `__ICCARM__` branch provides DLIB's
`__write`/`__read` from `<LowLevelIOInterface.h>`. `<sys/stat.h>` does not exist anywhere in
the IAR installation, so it cannot be included conditionally - it has to be out of the branch
entirely. The weak stubs are shared: TF-M's IAR builds pass `-e`, so the GCC
`__attribute__((weak))` spelling is accepted by iccarm. Without `-e` it is not (Pe079/Pe130).

**Rationale.** Every difference is a spelling of the same intent, so a branch at the point of
difference is smaller and more honest than a parallel build. The alternative - a separate NS
CMake project per toolchain - duplicates the consistency checks that exist precisely because
the NS image must come from the same solution as the secure one.

**Consequence.** `RA6E1_IAR_nonsecure` must be regenerated from the partitioned solution: the
first one supplied was the unpartitioned whole-device map (`RAM 0x20000000/0x40000`,
`FLASH 0x0/0x100000`, non-zero `OPTION_SETTING_*` lengths), which would have placed the NS
image on top of BL2 and emitted option words from the NS image. The regenerated one reads
`RAM 0x20020000/0x20000`, `FLASH 0x00098200/0x2fe00`, all option lengths 0. Verified: NS image
at `0x00098200`, NS RAM at `0x20020000`, zero symbols in secure RAM, OFS guard passes.

## D023 — The IAR stack-seal block must name a section, not merely reserve space

**Context.** With the seal misplaced, the secure image reset in a loop before `main()` with
nothing on the console. `Reset_Handler` seals `&__STACK_SEAL`, an ordinary C object the port
places in `.msp_stack_seal_res`. The GNU script anchors that section immediately above the
stack (`__StackSeal = ADDR(.msp_stack_seal_res)` -> `0x20001760`). The IAR template had
`define block STACKSEAL with size = STACKSEAL_SIZE { };` - 8 bytes reserved, no section named -
so the object was never placed there. ILINK swept it to `0x20009ca0`, on top of `ER_TFM_DATA`.
The seal was written onto live partition data, `__iar_data_init3` overwrote it moments later,
the SPM seal check failed, and `tfm_core_panic()` called `tfm_hal_system_reset()`.

That is why it presented as a reset loop rather than a hang: `HardFault_Handler` in
`startup_ra6e1.c` is `while(1)`, but panic reboots.

**Decision.** `define block STACKSEAL with size = STACKSEAL_SIZE { section .msp_stack_seal_res };`
in `platform/ext/common/iar/tfm_isolation_s.icf.template`. `.msp_stack_seal_res` is a TF-M-wide
convention (`tfm_common_bl2.ld`, `tfm_common_s.ld.template`, `tfm_isolation_s.ld.template`,
mps4, rp2350), not a Renesas name, so it belongs in the common template.

**Rationale.** Fixing it in the template rather than the platform: any IAR platform that seals
its stack hits this, and the failure is silent - no build error, no diagnostic, just a reboot
before the first line of output.

**Consequence.** Verified: `STACKSEAL$$Base` = `0x20001760`, map ordering
`ARM_LIB_STACK 0x20000760 (0x1000)` -> `STACKSEAL 0x20001760 (0x8)` ->
`ER_TFM_SP_ITS_RWZI 0x20001768`, and `Reset_Handler`'s seal literal now reads `0x20001760`
instead of `0x20009ca0`. Filed in [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) item 1.

## D024 — CMSE veneers are pinned at the NSC window under IAR too

**Context.** With the seal fixed the secure image booted and handed off, and the first
non-secure PSA call hard-faulted: `SFSR = 0x1` (INVEP - a Non-secure to Secure call that did
not land on an `SG`), `PC = 0x00058418`, called from NS at `0x00098EC9`. The veneers were
correct - `e97f e97f` is the `SG` encoding - but at `0x58400`, immediately after the vector
table, while the hardware NSC window is at `0x97800`.

The GNU template selects between an inline `VENEERS()` and an end-located one on
`TFM_LINKER_VENEERS_LOCATION_END`, honouring `TFM_LINKER_VENEERS_START`. `region_defs.h`
already set both (D-series work for the RA6M4, commit `93ce7d6de`). The IAR template honoured
neither and hardcoded `block ER_VENEER` inline in `LR_CODE`.

**Decision.** Mirror the GNU contract in the IAR template: guard the inline placement with
`!defined(TFM_LINKER_VENEERS_LOCATION_END)`, and add
`place at address TFM_LINKER_VENEERS_START { block ER_VENEER, block VENEER_ALIGN };` with a
`keep`. The platform supplies the address; no platform file changed.

**Rationale.** A platform whose NSC window is fixed by hardware - SAU/IDAU, or a vendor
partition table - cannot use the default placement at all. This is not a tuning preference,
it is the difference between working and faulting on every NS-to-S call.

**Consequence.** Verified: `tfm_psa_framework_version_veneer` at `0x97818` (it was `0x58418`,
exactly the faulting PC), `sg` followed by `b.w` into the secure implementation, NS relinked
against the regenerated import library and calling `0x97801`/`0x97819`/`0x97821`. Two clean
LOAD segments, code ending at `0x75fe0` with ~134 KB before the window, and 64 of the 2048
NSC bytes used. Filed in [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) item 2.

## D025 — RTT under IAR needs `--keep __write`, and each image has its own control block

**Context.** Two separate reasons the console was silent under IAR, found while chasing the
above.

`rtt_stdout.c` defined `_write()` under `#if defined(__GNUC__)` only. IAR's DLIB calls
`__write()`, so BL2 - whose `BOOT_LOG_*` macros expand to `printf()` - had no backend at all
and fell through to the semihosting stub, silent without a debugger. Adding `__write()` was
not enough: TF-M's IAR toolchain links with `--redirect __write=__write_buffered`, which
leaves *zero* references to `__write`, so ILINK garbage-collected the definition. It was
present in `rtt_stdout.o` and absent from the image.

Separately, the secure image was silent because that build was configured
`TFM_SPM_LOG_LEVEL_SILENCE` while GNU used `DEBUG` - nothing called the logger, so the whole
path was GC'd. That is configuration, not a defect.

**Decision.** `--keep __write` on the IAR link for `bl2` and `tfm_s`, alongside the
`__ICCARM__` branch in `rtt_stdout.c`. Verify after any toolchain change:
`readelf -sW bin/bl2.axf | grep " __write$"` present, and `SEGGER_RTT_Write` pulled in behind
it.

**Rationale.** The redirect is an upstream toolchain choice and cannot be removed per target;
`--keep` is the narrow answer that leaves it intact.

**Consequence.** BL2 `__write` `0x3abb`, `stdio_output_string` `0x3aa5`, `SEGGER_RTT_Write`
`0x4803`. Note that the three images have three separate RTT control blocks and a viewer sees
only the one it is attached to - bl2 `0x20002ccc`, tfm_s `0x2000b6dc`, tfm_ns `0x200204a0`.
`tfm_service_tests.c` records every result to `g_ns_test_results` for exactly this reason, so
a debugger can read the outcome with no host tooling. Filed in
[UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) item 8 (the `rtt_stdout.c` half is platform code
and stays here).

## D026 — Run the PSA Arch suites under IAR with `TOOLCHAIN=INHERIT`, not an IAR port of psa-arch-tests

**Date:** 2026-09-14 · **Status:** Accepted

**Context.** `psa-arch-tests` ships toolchain files for ARMCLANG, GNUARM, GCC_LINUX and
HOST_GCC only - there is no IAR support anywhere in its tools, its CMakeLists or the Renesas
target. Worse, the defaulting is silent: `tests_psa_arch/CMakeLists.txt` maps
`CMAKE_C_COMPILER_ID` GNU->GNUARM and ARMClang->ARMCLANG but leaves `TOOLCHAIN` **unset** for
IAR, and `api-tests/CMakeLists.txt` then defaults it to GNUARM and includes
`compiler/GNUARM.cmake`, which hardcodes `arm-none-eabi-gcc`. Left alone, an IAR run either
fails or quietly compiles the suite with GCC.

**Decision.** Pass `-DTOOLCHAIN=INHERIT` to the NSPE build. `INHERIT` is listed in both
`PSA_TOOLCHAIN_SUPPORT` and `CROSS_COMPILE_TOOLCHAIN_SUPPORT`, and `INHERIT.cmake` sets no
compiler at all - it only forwards `ARCH_TEST_EXTERNAL_DEFS`. Because the suite is pulled in
with `add_subdirectory` from the NSPE build, it then compiles with the iccarm already selected
by `toolchain_ns_IARARM.cmake`. The `-DCPU_ARCH` requirement is gated to ARMCLANG/GNUARM and
does not apply.

**Rationale.** The mechanism exists for exactly this case. Writing an `IAR.cmake` for
psa-arch-tests would be a second, redundant place to describe the compiler, and would have to
be maintained upstream in a repo we are already patching as little as possible (D014, D017).

**Consequence.** No change to psa-arch-tests is needed for IAR, so this does not add to the
upstreaming burden. Results on RA6E1, IAR 10.10.2, `profile_large` / isolation 3 / IPC, all
matching the GNU baselines: attestation 1/1; storage 17 tests, 11 passed, 6 skipped (the
optional PS `set_extended`/`create` APIs TF-M does not implement, skip code 0x2b), 0 failed;
crypto 64/64, 0 failed. Test 242 check 13 (`PSA_ALG_RSA_PSS_ANY_SALT`) passes, confirming the
`fetch_repo` patches of D014 are applied in this clone.

## D027 — The NSPE test build must set `CMAKE_BUILD_TYPE` explicitly

**Date:** 2026-09-14 · **Status:** Accepted

**Context.** `tests_psa_arch`'s NSPE project does not default `CMAKE_BUILD_TYPE`. Left empty,
the arch-test objects compile with no optimisation flag at all - the compile lines carry
`--cpu cortex-m33 --fpu=none -e -e --dlib_config=full ...` and no `-Ohz`. The secure side is
unaffected; TF-M's own build sets `MinSizeRel`.

**Cost of finding out.** The crypto NS image came to 205,364 bytes against a 196,096-byte
slot - `Error[Lp011]: section placement failed ... total estimated minimum size of 0x32234
bytes in <[0x98200-0xc7fff]> (total space 0x2fe00)`. The attestation and storage images fit
anyway at 27,136 and 50,688, so only the largest suite exposed it. Diagnosing this as a
capacity problem rather than a layout problem needed the map's overcommit line.

**Decision.** Always pass `-DCMAKE_BUILD_TYPE=MinSizeRel` to the NSPE configure, matching what
the GNU runs used.

**Consequence.** attestation 27,136 -> 23,040; storage 50,688 -> 39,424; crypto 205,364 ->
159,232, which fits with ~36 KB spare and lands within 2% of the GNU image (156,032). The
2% agreement is the evidence that the overflow was the missing flag and not IAR codegen.

## D028 — Two host-environment constraints on the PSA Arch test builds

**Date:** 2026-09-14 · **Status:** Accepted

**Context.** Two failures that look like code problems and are not.

*The database generator needs a host compiler.* `psa_generate_database` is an
`ExternalProject` that builds and runs `TargetConfigGen` on the build machine. It passes no
compiler, so CMake must discover one; commit `55cd71c` in the psa-arch-tests clone
deliberately lets it identify the host compiler rather than inheriting the cross settings.
With no host compiler on PATH the sub-build fails at `project()` with
`CMAKE_C_COMPILER-NOTFOUND`. The GNU runs used MSVC 14.29.30133, and with the Ninja generator
CMake needs the full MSVC environment, not just `cl.exe` on PATH.

*Windows MAX_PATH.* The crypto SPE failed with
`Error[Ms003]: could not open file "...intermedia_tfm_internal_trusted_storage.o.d" for
writing` - a 259-character path. CMake's four "cannot be safely placed under this directory"
warnings at configure time are the advance notice.

**Decision.** Drive the NSPE builds from a shell that has run `vcvars64.bat`. Keep the SPE
build directory names short: `build_spe_ra6e1_iar_cry`, not `..._crypto`. Three characters
is the entire margin at the current checkout path.

**Rationale.** Both are properties of this machine's layout rather than of the port, so they
belong in a decision record rather than in the build files - a shorter checkout path or a
different host toolchain makes either disappear.

**Consequence.** The RA6M5 work should start from a short build root (`C:\b\...` or similar)
rather than inheriting `tests_psa_arch/build_*`: the platform name is longer and the margin is
already three characters. Deferred deliberately for RA6E1 so the existing layout and launch
configs keep working.

## D029 — OPEN DEFECT: `.ram_from_flash` is excluded from copy-init at `profile_large` / L3

**Date:** 2026-09-14 · **Status:** Open - diagnosed, not fixed

**Context.** In the isolation-1 secure image the FSP code-flash program/erase routines are
relocated to RAM as intended: `ER_CODE_SRAM` at `0x2001f200` (0x500), `.ram_from_flash inited`,
`flash_hp_cf_write` at `0x2001f2c9`. In every `profile_large` / isolation-3 SPE - attestation,
storage and crypto alike - the same source, the same `r_flash_hp.o` (byte-identical section
attributes) and an ICF differing only by the `TFM_SP_META_PTR` block produce
`flash_hp_cf_write` at `0x0006ee2d`, in flash, with `ER_CODE_SRAM` empty and no initialiser.

The maps differ by exactly one line in the "No sections matched" list: at L3,
`rw section .ram_from_flash in block ER_CODE_SRAM` is listed as unmatched, so the copy split
never happened and the `ro` original fell through to the `ER_TFM_CODE { ro code }` catch-all.

`--log initialization` gives ILINK's reason verbatim:

```
++ The following sections would have been initialized by copy but were
   excluded because they were  marked as possibly 'needed for init':
     .ram_from_flash (r_flash_hp.o(libfsp_flash_s.a) #24)
```

Note that the same log shows copy batch C4 (`ER_RO_DATA -> ER_TFM_DATA`) with first match
`.data (r_flash_hp.o ...)`, which is the likely route by which r_flash_hp enters ILINK's
init-dependency closure at L3 and not at L1.

**Why it is not urgent.** The FCU makes code flash unreadable only during a *code*-flash
program/erase. The secure image instantiates Driver_FLASH1 (data flash) and the PSA Arch
storage suite exercises ITS and PS on data flash, which FSP deliberately leaves un-relocated.
All three suites pass with the defect present; that is not evidence it is harmless.

**Why it matters.** `FLASH_HP_CFG_CODE_FLASH_PROGRAMMING_ENABLE` is 1 in `ra6e1_secure`, so
`R_FLASH_HP_Write/Erase` dispatch to the code-flash path on address. Any secure image that
programs code flash at isolation 3 takes a prefetch abort mid-operation with the FCU left in
P/E mode - a hang, not a fault. See [[D012]] and `region_defs.h`.

**Next step.** Establish what drags `r_flash_hp` into the init closure at L3 and break it -
candidates are excluding the section from the `ER_TFM_DATA` initialiser batch, placing it with
`initialize manually` and copying it in `tfm_hal_platform_init()`, or marking the routines
`__ramfunc` so ILINK treats them as `.textrw`. The isolation-1 build is unaffected and ships
correctly.

---

## D030 — RA6M5 uses the whole 2 MB, with a reserved secure scratch block

**Date:** 2026-09-21 · **Status:** Accepted

**Decision.** BL2 96 KB, a 32 KB **secure** scratch block at `0x18000`, secure slots 512 KB
each, non-secure slots 448 KB each. Full table in `RA6M5_SOLUTION.md`.

**Why a reserved block rather than a bigger BL2.** Every slot boundary above `0x10000` has to
land on a 32 KB erase block. From `0x18000` there are 61 such units, an odd count, which cannot
be split into two secure plus two non-secure slots. The two ways to absorb it are a 128 KB BL2
or a separate 32 KB partition. The partition wins: `FLASH_CM33_B` stays at 96 KB so a BL2 that
outgrows its budget fails at link instead of quietly eating the spare block, and a later switch
to swap-using-scratch is then an MCUboot configuration change with no repartition and no
re-provisioning of the TrustZone boundaries.

**Why the scratch is secure.** During a swap the scratch holds fragments of the **secure**
image. In the non-secure region that is both an exposure and something NS code could corrupt.
Rejected: placing it at the top of flash after the NS secondary slot, which reads more
naturally but puts it in the NS region for exactly that reason.

**Split 512/448 rather than 480/480.** The secure side is what grows — SCE9 ciphers,
`profile_large`, and FSP's crypto stack — while the largest non-secure image measured so far
is the 159 KB PSA Arch crypto test. Both divisions are legal; this one puts the headroom where
the pressure is.

**Data flash is 8 KB, all secure** — carried over from RA6E1 ([[D019]] territory): NV counters
2048 B, PS 3072 B, ITS 3072 B, and `PS_MAX_ASSET_SIZE` / `PS_NUM_ASSETS` derive from the
resulting 1536-byte FS block. The stock template's 4/4 KB split does not fit these services.

**Partition Manager values:** code flash Secure 1150 KB, NSC 2 KB, SRAM Secure 255 KB, NSC
1 KB, data flash Secure 8 KB.

---

## D031 — The RA6M5 port was verified against a staged project set, not the e2 projects

**Date:** 2026-09-21 · **Status:** Provisional - re-verify once the e2 projects are regenerated

**Context.** `platform/ext/target/renesas/ra6m5` is the RA6E1 port with the device deltas
applied (wider `BPS`/`PBPS` OFS words, 2 MB `FLASH_TOTAL_SIZE`, the new layout). The
`ra6m5_gcc_*` e2 projects cannot drive it yet: the secure project has neither `r_flash_hp` nor
`r_sce`, its `BSP_CFG_STACK_MAIN_BYTES` is 0x400, the bootloader's flash instance generated as
`g_flashRA_NOT_DEFINED` instead of `g_flash0`, and all three still carry the RA6E1 1 MB
partitioning.

**Decision.** Verify the port against a **staged copy** of the three projects with those four
gaps filled in by hand, rather than editing the user's e2 projects or hand-editing
`configuration.xml` and regenerating with a RASC whose FSP version (6.6.0-beta.1 installed)
does not match what generated them (6.6.0-rc1).

**Result.** All three images build on GNUARM: bl2 54.2 KB, tfm_s 174.8 KB, tfm_ns 6.1 KB.
Veneers at `0x11F800`, discrete OFS LOAD segments, SCE9 TRNG linked, layout and orphan checks
pass.

**What this does not prove.** That a regenerated project produces the same generated files.
The staging is a build-level check of the port, not of the solution. `RA6M5_SOLUTION.md`
carries the list of e2 changes that have to be made for real.

**Rejected:** copying the projects into `fsp_cmake/ra6m5_*` now. They have to be regenerated
first, and committing the current state would put a wrong layout in the repo under names that
look authoritative.

*Superseded by D033.*

---

## D032 — CORRECTION to the SCE9 size figures quoted on 2026-09-21

**Date:** 2026-09-21 · **Status:** Accepted

**The error.** An earlier answer in the same session sized FSP's SCE9 stack from the
`ra6m4_der_conversion` linker map as `r_sce` 264.8 KB, `rm_psa_crypto` 34.6 KB, FSP mbedTLS
93.9 KB, and concluded the driver could not fit in an RA6E1 secure slot. The parse summed the
**discarded-section list** at the top of the GNU map along with the linked sections.

**Corrected figures**, counting only what appears after `Linker script and memory map`:

| Component | Flash | RAM |
|---|---|---|
| `r_sce` | 58.5 KB | 0.1 KB |
| `rm_psa_crypto` | 12.8 KB | 1.5 KB |
| FSP mbedTLS | 29.3 KB | 2.0 KB |

That is ~100 KB for a project exercising RSA, ECC and AES through PSA — which **does** fit the
78–134 KB of RA6E1 secure-slot headroom, where the earlier figure said it could not. The TRNG
alone costs 8.9 KB in the RA6M5 secure image, consistent with the ~8 KB measured on RA6E1.

**Rule that follows.** Size any FSP module from a map only after skipping to
`Linker script and memory map`; `--gc-sections` makes the head of the file misleading by an
order of magnitude. Noted in `fsp_sce.cmake`.

---

## D033 — RA6M5 builds against the real e2 projects

**Date:** 2026-09-21 · **Status:** Accepted · **Supersedes:** D031

The four project-side gaps D031 listed were fixed in e2 — `r_flash_hp` and `r_sce` added to
`ra6m5_gcc_secure`, `BSP_CFG_STACK_MAIN_BYTES` raised to 0x1000, the bootloader's flash
instance renamed to `g_flash0`, and the solution repartitioned to the 2 MB layout of [[D030]]
with `__BL_*_T` sizes 0 and all 8 KB of data flash secure.

All three images now build on GNUARM from the generated projects, with no staging: bl2 54.2 KB,
tfm_s 174.8 KB, tfm_ns 6.1 KB. Veneers at `0x11F800`, signed images padding to the full 512 KB
and 448 KB slots, discrete OFS LOAD segments, SCE9 TRNG linked, layout and orphan checks
passing.

**What the staged pass was worth.** Every one of those four gaps was found by building against
a staged copy before the projects were touched, and each surfaced as a specific error rather
than a runtime symptom — the missing flash module at configure time, the stack size and the
partitioning as static assertions. The stale partitioning alone would otherwise have produced
`BOOT_EFLASH`, a wrong-address erase on upgrade, and `PSA_ERROR_INSUFFICIENT_STORAGE`, all on
silicon.

**Still open:** the projects are not copied into `fsp_cmake/ra6m5_*`, so the build points at
`e2_studio/workspace66`. Nothing has run on hardware. IAR is untouched — `ra6m5_iar`'s solution
still selects GCC.

---

## D034 — `BSP_CFG_EARLY_INIT` is asserted at build time, in both secure and BL2

**Date:** 2026-09-21 · **Status:** Accepted

**What happened.** The first RA6M5 hardware run failed `R_FLASH_HP_Open` with `FSP_ERR_FCLK` —
the July 2026 RA6E1/RA6M4 failure, recorded in `DESIGN.md` §8.1. The port's linker half of the
fix carried over (`.ram_noinit` / `.TFM_NOINIT` are NOBITS and outside `.bss` in both images);
the project half did not. `BSP_CFG_EARLY_INIT` was 0 in `ra6m5_gcc_secure` and
`ra6m5_gcc_mcuboot`, so `SystemCoreClock` sat in `.bss` (`0x2000D2BC` in `tfm_s`, `0x200045EC`
in BL2) and was zeroed after `SystemInit()`. On RA6E1 it sits at the start of `.TFM_NOINIT`.

The requirement was already written down twice — `RA6E1_TEMPLATE_CHECKLIST.md` §5 and the
RA6M5 requirements table — and was still missed, including by the build verification in
[[D033]], which checked modules, stack size, instance names and layout but not this.

**Decision.** `#error` when `BSP_CFG_EARLY_INIT` is 0: in `ra6m5_layout_checks.c` for the
secure image, in `bl2_option_setting.c` for BL2 (BL2-only, and it already includes
`bsp_api.h`). Verified: both fire against the current projects.

**Rejected:** overriding `boot_platform_post_init()` to call `SystemCoreClockUpdate()` in BL2,
which `DESIGN.md` §8.1 names as the preferred BL2 fix. It repairs `SystemCoreClock` but not the
other state early init moves out of `.bss` (`g_protect_counters`, `g_bsp_group_irq_sources`),
and it would leave the secure image depending on the project setting anyway. One rule, checked
in both images, matches what RA6E1 actually runs with.

**Follow-up:** the RA6E1 port has the same exposure with no guard; its projects happen to be
correct. Same two checks apply there.

---

## D035 — Stay on TF-M 2.2; the TF-M 2.3 rebase is cancelled

**Date:** 2026-09-21 · **Status:** Accepted

**Decision.** Do not move to TF-M 2.3. It replaces Mbed TLS with TF-PSA-Crypto — v1.1.0 in
2.3.0, v1.1.1 in 2.3.1 (`config/config_base.cmake:38` at each tag; 2.3.0 release notes: "Use
TF-PSA-Crypto 1.1.0 in place of Mbed-TLS"). The port stays on v2.2.0 / Mbed TLS 3.6.3. P5 of
`PROJECT_PLAN.md` is cancelled.

**Consequence for SCE9.** On 3.6.3 the `MBEDTLS_xxx_ALT` mechanism is available, so FSP's
`rm_psa_crypto` ALT sources are no longer a throwaway path. In 2.3.0 the CC312 legacy (ALT)
driver API is gone and no accelerator config defines an `_ALT` any more.

**What the partial rebase established (for whenever 2.3 is revisited):**
- Fixed upstream in 2.3.1: item 9 (signed image depends on `${bin_dir}/tfm_s.bin`) and item 11
  (`bootutil_key_cnt` in the EC branch of `keys.c`).
- Obsolete in 2.3.1: item 10 — the SPE build no longer signs the NS image at all.
- Still needed: item 6 — the CMake `MCUBOOT_ALIGN_VAL` list accepts 4096, but the relocated
  `bl2/ext/mcuboot/scripts/wrapper.py` still caps `--align` at 32.
- SPM logging was rewritten (`lib/tfm_log`, `ERROR_RAW`/`INFO_RAW`, `LOG_LEVEL_*`):
  `SPMLOG_*`, `tfm_spm_log.h` and the `TFM_SPM_LOG_LEVEL_SILENCE` vocabulary are gone, so item 7
  and the RTT SPM-log backend both need porting. 2.3 also adds
  `CONFIG_TFM_BACKTRACE_ON_CORE_PANIC`, GCC-only (`<unwind.h>`), overlapping item 7's panic trace.
- 10 of the 20 surviving shared files conflicted; `wrapper.py`, `lib/ext/mcuboot/CMakeLists.txt`,
  `toolchain_CLANG.cmake` and `platform/ns/toolchain_ns_CLANG.cmake` moved or were removed.

Nothing was committed; the worktree and branch were deleted.

---

## D036 — SCE9 acceleration via FSP `*_ALT`: AES, AES-GCM, SHA-256 first; ECC held back

**Date:** 2026-09-21 · **Status:** Provisional - builds; not yet run on silicon

**Decision.** `platform/ext/accelerator/renesas/sce9` (`CRYPTO_HW_ACCELERATOR_TYPE=renesas/sce9`,
ON in `ra6m5/config.cmake`) compiles FSP's `rm_psa_crypto` ALT sources from the secure e2
project into TF-M's Mbed TLS 3.6.3 for the crypto partition: `aes_alt`, `gcm_alt`,
`sha256_alt` and their `*_process.c`. TF-M's `LEGACY_DRIVER_API_ENABLED` path, as CC312 uses it;
`crypto_init.c` then calls `crypto_hw_accelerator_init()` before `psa_crypto_init()`.
Plaintext keys only (`PSA_CRYPTO_CFG_*_FORMAT` = 0x01); the wrapped-key vendor driver is not
built. BL2 stays software.

**Verified in the build:** `mbedtls_aes_crypt_ecb`, `mbedtls_gcm_setkey/starts` and
`mbedtls_sha256_starts` resolve to the ALT objects; 109 `HW_SCE_*` procedures linked, including
AES-128/192/256 ECB/CBC/CTR, AES-GCM and `HW_SCE_Sha224256GenerateMessageDigestSub`. Secure
`text` 179.2 KB → 230.2 KB (+49.8 KB), `bss` −8.7 KB (software AES tables gone). BL2 has no
`HW_SCE_*` and its OFS segments are unchanged.

**What had to be bridged, and why each is safe:**
- The ALT files are forks of Mbed TLS library sources and include internals by bare name
  (`common.h`, `bn_mul.h`, ...). FSP's `*_alt.h` do too, and `mbedtls/<module>.h` includes them
  once the ALT is defined - so `library/` is on the config's interface include path.
- The Mbed TLS config now includes `bsp_api.h` (the ALT sources test `BSP_FEATURE_RSIP_*`);
  FSP/SCE include paths and defines reach the config consumers from `fsp_sce_s`'s interface,
  without linking it into them.
- `BYTES_TO_WORDS` lives in FSP's `platform_alt.h`, reached only under
  `MBEDTLS_PLATFORM_SETUP_TEARDOWN_ALT`, which TF-M has no use for. Defined in the accelerator
  config.
- `psa_aead_setup_vendor` is called under a **runtime** `vendor_flag` that only FSP's patched
  Mbed TLS core sets. Stubbed to `psa_panic()`: dead here, and reaching it would mean a
  plaintext key going to a wrapped-key procedure.
- `HW_SCE_McuSpecificInit()` software-resets the engine on every call. The TRNG and the
  accelerator now share one latched `ra_sce_init()` in the platform, so neither resets the SCE
  under the other.
- BL2's `mcuboot_crypto_config.h` includes `MBEDTLS_ACCELERATOR_PSA_CRYPTO_CONFIG_FILE`
  unconditionally under `CRYPTO_HW_ACCELERATOR`; both BL2 macros point at a no-op header.
  `bl2_main.c` already stubs BL2's `crypto_hw_accelerator_*`.

**Why ECC is held back.** FSP's ECDSA/ECP ALT has **no software fallback**: a curve with no SCE9
procedure returns `MBEDTLS_ERR_ECP_FEATURE_UNAVAILABLE`, and ECDSA cannot be taken without
`MBEDTLS_ECP_ALT` because it reads FSP's patched group struct (`grp->vendor_ctx`). TF-M's
default set enables P-521, Curve25519, Curve448 and secp256k1; SCE9 has no P-521 or 25519
procedures (they failed to compile). Enabling ECC as-is swaps working software curves for
runtime failures. Needs a curve-set decision.

**Mbed TLS version.** Built against 3.6.3 as-is. FSP's tree is 3.6.6; the AES/GCM paths and
their internals are identical between the two, and the ALT sources do not use the 3.6.4+
`mbedtls_f_rng_t`. TF-M 2.2.2 (same 2.2 line) carries 3.6.5 if a bump is wanted.

**Open before M4:** hardware run (smoke test exercises SHA-256 and AES-GCM through PS); PSA Arch
crypto suite as the regression gate against 64/64; at isolation 2/3 the crypto partition must
be able to reach the SCE registers, not yet checked.

*ECC hold-back superseded by D037.*

---

## D037 — SCE9 ECC enabled; P-521, Curve25519 and deterministic ECDSA removed from RA6M5

**Date:** 2026-09-21 · **Status:** Provisional - builds; not yet run on silicon · **Supersedes:** D036 (ECC hold-back only)

**Decision (option 1 of the three put in D036).** Enable `MBEDTLS_ECP_ALT`,
`MBEDTLS_ECDSA_SIGN_ALT` and `MBEDTLS_ECDSA_VERIFY_ALT` with FSP's `ecp_alt`, `ecp_curves_alt`
and `ecdsa_alt` sources, and remove from the RA6M5 PSA configuration what SCE9 cannot do
correctly, in the accelerator's `crypto_accelerator_config.h`:

| Removed | Why |
|---|---|
| `PSA_WANT_ECC_SECP_R1_521` | No SCE9 procedure - `ecp_can_do_sce()` admits P-521 only on RSIP-E51A/E50D, and its HW tables do not compile on SCE9 |
| `PSA_WANT_ECC_MONTGOMERY_255` | No SCE9 procedure; its HW tables reference RSIP-only functions |
| `PSA_WANT_ALG_DETERMINISTIC_ECDSA` | FSP's `mbedtls_ecdsa_sign()` ignores `f_rng` - the SCE draws its own nonce - and Mbed TLS 3.6's deterministic path under `ECDSA_SIGN_ALT` is that call with an HMAC-DRBG as `f_rng`. It would return a valid but randomised signature for `PSA_ALG_DETERMINISTIC_ECDSA`. Nothing in TF-M uses it (the attestation key is `PSA_ALG_ECDSA(SHA_256)`) |

**Kept, contrary to the original option-1 wording:** secp256k1 - SCE9 does sign and verify it
(`ecp_can_do_sce()`); Curve448 - no hardware references, and ECP scalar multiplication falls back
to software (`ecp_mul_mxz`).

**Verified in the build:** `mbedtls_ecdsa_sign/verify`, `mbedtls_ecp_mul` and
`mbedtls_ecp_group_load` resolve to the FSP ALT objects; `HW_SCE_ECC_256/384` GenerateSign,
VerifySign and WrappedScalarMultiplication linked; curve data present for secp256r1, secp256k1,
secp384r1 and Curve448 only. Secure `text` 276.3 KB against 179.2 KB all-software (+97.1 KB);
about 233 KB of the 509.5 KB secure code region remains.

**Note for FSP.** The ignored `f_rng` means any FSP application that enables
`MBEDTLS_ECDSA_DETERMINISTIC` alongside `MBEDTLS_ECDSA_SIGN_ALT` on SCE9 gets randomised
signatures from deterministic ECDSA - worth raising with the rm_psa_crypto owners.

*The "Note for FSP" above is corrected by D038.*

**Consequence for the PSA Arch gate.** P-521, X25519 and deterministic-ECDSA cases now report
not-supported rather than pass; the crypto suite total will drop below the 64/64 software
baseline by that many, and the gate is "no failures", not "same count".

---

## D038 — CORRECTION to D037: deterministic ECDSA is unsupported in FSP by design

**Date:** 2026-09-21 · **Status:** Accepted

D037's "Note for FSP" called the ignored `f_rng` in `mbedtls_ecdsa_sign()` a defect affecting FSP
applications that enable `MBEDTLS_ECDSA_DETERMINISTIC`. That is wrong. Per the rm_psa_crypto
owner, deterministic ECDSA is **not supported** by FSP on the SCE, and the FSP configurator does
not allow the setting - so no FSP application can reach that path.

The exposure exists only in the TF-M integration, because TF-M's own PSA configuration enables
`PSA_WANT_ALG_DETERMINISTIC_ECDSA`. Removing it in `crypto_accelerator_config.h` (D037) is
therefore the correct and complete handling: it aligns TF-M with what FSP supports. Nothing to
raise with FSP.

---

## D039 — BL2 SHA-256 on the SCE9; P-256 verify stays on p256-m

**Date:** 2026-09-21 · **Status:** Provisional - builds; not yet run on silicon

**Decision.** BL2 accelerates its image hash only: FSP's `sha256_alt` in a `bl2_crypto_hw` library
linked into `bl2_crypto`, `r_sce` in the bootloader role (`FSP_MODULES_BL2 += sce` under
`CRYPTO_HW_ACCELERATOR`), and the SCE brought up in the port's `boot_platform_post_init()`
(`bl2_boot_hal.c`), which MCUboot calls before the first slot is hashed. `ra_sce_init()` moved to
its own file so BL2 can link it without the TRNG. BL2 `text` 55.7 KB → 56.1 KB.

**Why not the verify.** BL2 routes P-256 to p256-m (`MBEDTLS_PSA_P256M_DRIVER_ENABLED`), so an
ECDSA ALT is never reached; replacing p256-m pulls in bignum plus FSP's whole `ECP_ALT` for one
verify per image, against a 96 KB budget. The hash scales with image size and is the win.

**Two traps found on the way:**
- `CRYPTO_HW_ACCELERATOR` reached bootutil (via `tfm_config`) but not `bl2_crypto`, so the first
  build linked upstream software `sha256.o` while bootutil compiled against FSP's
  `mbedtls_sha256_context` - a struct-layout mismatch across translation units. The define is
  now on `bl2_crypto_config` itself.
- `bsp_common.h` includes the bootloader project's `bsp_linker_info.h`, whose FSP MCUboot
  helpers (`FLASH_AREA_IMAGE_PRIMARY/SECONDARY` as inline functions) sit under
  `#ifdef __SYSFLASH_H__` - the same guard TF-M's `sysflash.h` uses. Defining FSP's own opt-out
  `__SYSFLASH_BSP_LINKER_H` in the BL2 accelerator config skips that block.

## D040 — PSA Arch crypto on RA6M5 SCE9: generic Renesas target, deterministic ECDSA gated

**Date:** 2026-09-21 · **Status:** Provisional - built, not yet run

**Build.** `C:\b\m5cry` (SPE: profile_large, isolation 3, IPC, `TFM_SPM_DEBUG_TRACE=OFF`) and
`C:\b\m5cryns` (NS, MinSizeRel, from a `vcvars64` shell per D028), against the local
psa-arch-tests clone with `PSA_API_TEST_TARGET=renesas_ra` - the clone's
`tgt_dev_apis_tfm_renesas_ra` replaced the RA6E1-specific target. The short `C:\b` root is the
D028 recommendation, taken up for RA6M5.

**Deterministic ECDSA.** The target defined `ARCH_TEST_DETERMINISTIC_ECDSA` unconditionally,
while the accelerated SPE removes the algorithm (D037/D038); NS builds compile against the client
config and cannot see that. The SPE now exports `RA6M5_SPE_CRYPTO_HW_ACCELERATOR` in
`ra6m5_ns_config.cmake`, the NS platform turns it into `RENESAS_RA_NO_DETERMINISTIC_ECDSA`, and the
Renesas target skips the deterministic tests on it. The target already covers only P-256 and
P-384, so the P-521 and X25519 removals do not affect it.

**Pass bar.** Zero failures; the total is below the 64/64 software baseline by the deterministic
cases. Open: whether the crypto partition reaches the SCE registers at isolation 3 - the TRNG did
on RA6E1 at L3, which suggests it will.

---

## D041 — Two FSP `aes_alt.c` fixes carried in the RA6M5 secure project; PSA Arch crypto 61/64

**Date:** 2026-09-22 · **Status:** Accepted for the TF-M port; the fixes belong in rm_psa_crypto

**Result.** PSA Arch crypto on RA6M5 with SCE9 (profile_large, L3, IPC): **61 passed, 2 failed,
1 skipped** of 64. The skip (252) is the deterministic-ECDSA gate from D040. The failures are
multi-part GCM (261 finish, 263 verify) - see below.

**Fix 1 - `mbedtls_aes_free()` closes an open SCE AES session.** CBC/CTR/XTS issue `InitSub` on
first use and set `ctx->state = UPDATE`; nothing issued the matching `FinalSub`, so the first
multi-part CBC update (test 236) left the engine mid-session and every later SCE command failed -
AES key-index generation (-132), SHA (-147) and the TRNG (-148). Free now issues the key-size
`FinalSub` only when `state == UPDATE`. First version from the rm_psa_crypto owner; the state gate
and NULL-safety added here.

**Fix 2 - `mbedtls_aes_crypt_ctr()` handles partial blocks.** The unaligned path dropped the
`length % 16` tail (15-byte input produced no output, returned success); the aligned path passed a
partial length to a worker that only handles whole blocks; `nc_off`/`stream_block` were ignored.
Rewritten to upstream `aes.c` semantics: leftover keystream, whole blocks on the SCE (bulk if
aligned, bounced otherwise), trailing keystream from the SCE over a zero block. 237 now 13/13.

**Where they live.** In `fsp_cmake/ra6m5_gcc_secure/ra/fsp/src/rm_psa_crypto/aes_alt.c` - a
generated file. Regenerating the project in e2 overwrites both; they need to land in rm_psa_crypto.

**Open - multi-part GCM.** FSP's GCM ALT depends on two FSP patches to the Mbed TLS core that
TF-M's upstream 3.6.3 does not have: `psa_crypto_aead.c` keeping the ciphertext length
`mbedtls_gcm_finish()` reports (upstream forces 0), and `psa_crypto_driver_wrappers.h` routing GCM
verify to `sce_gcm_verify()` with the expected tag (upstream passes an uninitialised scratch tag to
finish and compares after). One-shot GCM passes, and PS uses one-shot.

## D042 — TF-M's crypto is built from FSP's Mbed TLS, not upstream

**Date:** 2026-09-22 · **Status:** Accepted for RA6M5 (`RA6M5_FSP_MBEDTLS`, default ON)

**Why.** FSP's `*_ALT` sources are written against FSP's Mbed TLS core, not upstream's. D041 left
multi-part GCM (261/263) failing because two FSP changes live in the core - `psa_crypto_aead.c`
keeping the ciphertext length `mbedtls_gcm_finish()` reports, and `psa_crypto_driver_wrappers.h`
routing GCM verify to `sce_gcm_verify()` with the expected tag. Patching those into upstream would
mean carrying FSP core deltas as TF-M patches forever, and re-deriving them at every FSP release.
Taking FSP's tree instead makes the pairing the one FSP ships and tests.

**How - an overlay, built in the build directory** (`ra6m5/cmake/fsp_mbedtls.cmake`):

- FSP ships `include/` + `library/` only; TF-M needs the whole release (CMakeLists, `scripts/`,
  `framework/`, `3rdparty/p256-m`). So: clone upstream at FSP's own version (read from
  `build_info.h` - 3.6.6 for FSP 6.6.0-rc1), copy FSP's `include/` and `library/` over it
  (CRLF→LF), apply the TF-M patches FSP lacks, point `MBEDCRYPTO_PATH` at the result.
- Only patches 0003, 0004, 0006, 0007 are applied: FSP's tree already carries TF-M's
  builtin-key-loader (0001) and CC3XX (0005) changes. 0002 (code sharing) is unused here.
- Port-owned patch `0100`: restore upstream's default `MBEDTLS_CONFIG_FILE`
  (FSP defaults to `mbedtls/config.h`, which only exists in a generated FSP project, and the
  everest subtarget is built without TF-M's `-D`), and make `psa_encapsulate`/`psa_decapsulate`
  take `mbedtls_svc_key_id_t` - mandatory under `MBEDTLS_PSA_CRYPTO_KEY_ID_ENCODES_OWNER`, which
  TF-M sets and FSP does not.
- `git apply` runs with `GIT_CEILING_DIRECTORIES` so git does not discover the enclosing TF-M
  checkout; the overlay stays a plain directory, which matters because a `.git` in it survives
  `file(REMOVE_RECURSE)` on Windows and would stale the next configure.
- The overlay is regenerated on every configure from `FSP_S_APP_DIR`, so a regenerated e2 project
  flows through. `-DRA6M5_FSP_MBEDTLS=OFF` falls back to upstream.

**ALT set.** Now everything FSP enables for SCE9: `cipher_alt`, `aes_alt`, `gcm_alt`, `ccm_alt`,
`cmac_alt`, `sha256_alt`, `ecp_alt`, `ecp_curves_alt`, `ecdsa_alt`, `rsa_alt`. `cipher_alt.c`
supplies the block chunking and session finalisation the PSA layer expects.

**Cost.** One upstream clone per build directory (network on first configure), and the port owns a
patch that has to be checked at each FSP uprev - the failure is loud: configure aborts naming the
patch.

**Also.** `aes_alt.c` needed the SCE private headers (`hw_sce_aes_private.h`, `hw_sce_private.h`,
`hw_sce_ra_private.h`) for the `FinalSub` calls D041 added - they were implicitly declared. Part of
what goes back into rm_psa_crypto.

## D043 — SCE9 CCM stays in software; a third rm_psa_crypto session leak; crypto suite 63/64

**Date:** 2026-09-22 · **Status:** Accepted · Supersedes nothing; extends [D041], [D042]

**Result.** PSA Arch crypto on RA6M5 with SCE9 and FSP's Mbed TLS: **63 passed, 0 failed,
1 skipped** of 64. The skip is the deterministic-ECDSA gate (D040). 261 and 263 - the multi-part
GCM failures that motivated the move to FSP's Mbed TLS - now pass, which is the confirmation D042
was waiting for.

**MBEDTLS_CCM_ALT is not defined on this port.** FSP's SCE9 CCM formats the whole B-block
sequence into one 128 B hardware buffer, so it accepts at most 110 B of associated data:
`16 + roundup16(2 + aad_len) <= HW_SCE_AES_CCM_B_FORMAT_BYTE_SIZE`. Protected Storage
authenticates its object table with the table as associated data - about 140 B at
`PS_NUM_ASSETS` 10 - so every object-table write returned `MBEDTLS_ERR_CCM_BAD_INPUT`
(`PSA_ERROR_INVALID_ARGUMENT`), PS init failed and the partition never started. CCM therefore
runs in software, where it still reaches the SCE9 per block through `MBEDTLS_CIPHER_ALT` and
`MBEDTLS_AES_ALT`. Everything else FSP enables for SCE9 is accelerated.

**Third session leak, same family as D041.** `mbedtls_cipher_cmac_starts()` issues the SCE CMAC
init and sets `vendor_state = UPDATE`; only `cmac_finish()` issues the matching final.
`mbedtls_cipher_free()` released the CMAC context without closing the session, so an aborted MAC
operation left the engine mid-CMAC and every later SCE command failed. PSA Arch test 226 aborts a
CMAC setup, which wedged the engine for the 36 tests after it - 28/64, with the first casualty
being the same `psa_mac_sign_setup` call that had just passed. Fixed in the project's
`cipher_alt.c`: when `vendor_state == UPDATE`, free issues `mbedtls_cipher_cmac_finish()` into a
scratch MAC first.

**The pattern, for rm_psa_crypto.** Three defects of one shape are now carried in the project's
generated files (D041 fix 1 and 2, plus this one): an operation that is abandoned rather than
finished leaves the SCE mid-session, and the next SCE user in the system fails. None are visible
to a caller who only performs complete, successful operations - which is why they survive normal
use and fall over under PSA Arch. The CCM AAD ceiling is the same kind of gap: a real hardware
limit surfacing as a generic PSA error with no indication of a size limit.

**Diagnosis notes worth keeping.**
- `PSA_ERROR_HARDWARE_FAILURE` (-147) cascading across unrelated tests means the engine is
  wedged, not that each test is broken. Find the last test that passed and look at what it
  aborted.
- `STATUS_NEED_SCHEDULE` (-254) seen at a `psa_call` return is a debugger artifact: the SPM
  returns it and relies on PendSV, which single-stepping with masked interrupts prevents.
- A core panic with `CONFIG_TFM_HALT_ON_CORE_PANIC=OFF` resets the device, so "constant reboot
  from secure code" is a repeating panic. The PSA Arch SPE wrapper sets no `CMAKE_BUILD_TYPE`,
  so `TFM_SPM_LOG_LEVEL` defaults to SILENCE and the panic is silent - set both to debug.
- MCUboot erases a primary slot it judges invalid, so a failed boot has to be re-flashed before
  the next attempt.

## D044 — The CTR fix is dropped; `mbedtls_aes_crypt_ctr()` is not an FSP API

**Date:** 2026-09-22 · **Status:** Accepted · Supersedes the second fix in [D041]

**Decision (rm_psa_crypto owner).** FSP supports the PSA APIs only; `mbedtls_aes_crypt_ctr()` is
not public. Fixes 1 and 3 of [D041]/[D043] go into FSP and reach this port through regenerated
packs. Fix 2 - the CTR partial-block rewrite - does not, and has been reverted in
`ra6m5_gcc_secure`, so the project matches what FSP ships.

**Why it is unreachable through PSA.** FSP's `cipher_alt.c` does the caching itself and always
calls `ctr_func(ctx, block_size, NULL, ctx->iv, NULL, ...)` - one whole block, no carry-over
state. The dropped `length % 16` tail and the ignored `nc_off`/`stream_block` need a caller that
passes a partial length or carries keystream between calls, which the PSA path never does. This
port enables `MBEDTLS_CIPHER_ALT` ([D042]), so the contract holds here too.

**What still depends on it, for the record.** A direct `mbedtls_aes_crypt_ctr()` caller gets a
silent wrong answer, not an error - a 15 byte call produces no output and returns 0. `aes_alt.c`'s
own CTR self-test vector set is `{16, 32, 36}` and calls the function with real
`nc_off`/`stream_block`, so `mbedtls_aes_self_test()` fails on CTR wherever `MBEDTLS_SELF_TEST` is
enabled - it is in FSP's default `mbedtls_config.h`, though not in TF-M's config, which supplies
its own. Neither is reachable from a PSA-only application.

**How it was found.** PSA Arch 237 check 6, "psa_cipher_finish - Encrypt - AES CTR (short input)",
in the earlier build that had no `cipher_alt.c` in the ALT set. Adding `cipher_alt.c` is what put
the caching back in front of it.

## D045 — Confirmed on FSP 6.7.0-beta0: 63/64 with no port-local rm_psa_crypto patches

**Date:** 2026-09-22 · **Status:** Accepted · Confirms [D043], [D044]

**Result.** PSA Arch crypto on RA6M5 with SCE9: **63 passed, 0 failed, 1 skipped** of 64, with

- **FSP 6.7.0-beta0** (`6.7.0-beta0+20260922.be8f27e2`), up from 6.6.0-rc1; Mbed TLS unchanged at
  3.6.6, so the overlay ([D042]) is unaffected;
- the AES `free()` and CMAC `free()` fixes arriving **from the pack**, in the rm_psa_crypto owner's
  own wording, in the secure and bootloader projects;
- `mbedtls_aes_crypt_ctr()` **unmodified** - FSP's code, byte-identical to what the pack ships;
- CCM in software, per [D043].

The port now patches nothing in rm_psa_crypto. `git status` on `ra6m5_gcc_secure` shows only what
the regenerated pack changed.

**What this confirms about the CTR question ([D044]).** Test 237 check 6, "psa_cipher_finish -
Encrypt - AES CTR (short input)", passes with FSP's unmodified `mbedtls_aes_crypt_ctr()`. The
partial-length path really is unreachable through PSA, because `cipher_alt.c` caches and only ever
passes whole blocks with NULL `nc_off`/`stream_block`. Measured, not inferred.

**Process note.** An earlier run of the reverted build looked like a failure and was not: its log
stopped mid-test, which read as a hang. It was RTT dropping output under load - the same run shows
whole tests missing from the transcript while the final report counts them as passed - and the tail
of that run, pasted later, showed 236 and 237 passing before a reflash interrupted it at 238. A
truncated RTT capture is not evidence of a hang; wait for the suite report.

## D046 — RA6M5 PSA Arch on GCC and IAR: crypto, attestation, storage; RTT made lossless

**Date:** 2026-09-23 · **Status:** Accepted · Extends [D045]

**Result.** All three PSA Arch suites run on hardware from both toolchains, on FSP 6.7.0-beta0
with the SCE9 accelerator and FSP's Mbed TLS. Identical results, zero failures:

| Suite | GCC | IAR |
|---|---|---|
| crypto | 63 pass / 0 fail / 1 skip | 63 / 0 / 1 |
| attestation | 1 / 0 / 0 | 1 / 0 / 0 |
| storage (ITS + PS) | 11 / 0 / 6 | 11 / 0 / 6 |

Both skips are expected: deterministic ECDSA, which FSP does not support ([D040]), and the
optional PS APIs (`psa_ps_create`/`set_extended`), which TF-M does not implement - test 414
passes by confirming they refuse correctly.

**One SPE per toolchain serves all three suites.** profile_large has crypto, ITS, PS,
attestation and platform all enabled, which is what the suites need; only the NS app differs.
This follows the RA6E1 GCC arrangement. Build directories: `m5cry` + `m5cryns`/`m5att`/`m5sto`
(GCC), `m5icry` + `m5icryns`/`m5iatt`/`m5isto` (IAR).

**What an IAR build needs that a GCC one does not.** Four things, none obvious from an error
message:
- IAR on `PATH` - `toolchain_IARARM.cmake` names `iccarm` without a path;
- `-DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM` - CMake 4.1's IAR-ASM module cannot detect it and
  aborts the *re-configure*, after the first configure has succeeded;
- `-DTFM_TOOLCHAIN_FILE=<spe>/api_ns/cmake/toolchain_ns_IARARM.cmake` on the NS build, or it
  silently uses GNUARM and fails looking for `script/fsp.ld` in an IAR project;
- `-DTOOLCHAIN=INHERIT`, or psa-arch-tests compiles with arm-none-eabi-gcc while being handed
  IAR flags.

The IAR projects also needed the same `BSP_CFG_EARLY_INIT` and main-stack settings the GCC
ones did; the build-time guards from [D034] caught both at compile time rather than on the
board.

**RTT no longer drops output: `RA6M5_RTT_BLOCKING`** (default OFF). SEGGER's default
`SEGGER_RTT_MODE_NO_BLOCK_SKIP` discards a whole write when the 4 KB up-buffer is full, so a
fast talker loses entire lines and whole tests from the transcript while the run itself is
fine - which is what made a truncated capture look like a hang and cost two flash cycles
([D045]). ON selects `BLOCK_IF_FIFO_FULL` for BL2, the secure image and the NS app, and is
carried to NS builds through the exported platform config.

Test builds only, hence the default: with no viewer attached nothing drains the buffer and the
first write past 4 KB blocks forever. The define has to be applied in `ns/CMakeLists.txt` as
well as the main one - `platform_ns` compiles `SEGGER_RTT.c` there, and patching only the
secure-side list leaves the NS transcript still lossy.

## D047 — FSP 6.7 is the baseline

**Date:** 2026-09-23 · **Status:** Accepted · Supersedes the FSP 6.6 target in the plan

The RA6E1 solutions were already on 6.7.0-beta0 and the RA6M5 projects moved there on
2026-09-22, where M4 was met: full chain on both toolchains, SCE9 active, all three PSA Arch
suites passing. Carrying a plan that names 6.6 while every project is on 6.7 invites a third
version when RA8x2 projects are generated in P5.

6.7 is therefore the baseline for the remaining work. Mbed TLS is unchanged at 3.6.6 between
the two, so the FSP Mbed TLS overlay ([D042]) is unaffected.

## D048 — `.ram_from_flash` is copied by the platform, not by ILINK — closes [D029]

**Date:** 2026-09-23 · **Status:** Accepted · Resolves the open defect in [D029]

**The defect, reproduced on RA6M5.** IAR at isolation 3 left FSP's code-flash program/erase
routines in flash: `.ram_from_flash` at `0x000B0120`, listed under "No sections matched", with
`ER_CODE_SRAM` empty. Isolation 1 relocated them correctly from the same sources. GNUARM was
correct at both levels. So the defect is ILINK-specific and isolation-dependent, exactly as
diagnosed on RA6E1.

**Fix.** Stop asking ILINK to do the copy. The ICF declares
`initialize manually { section .ram_from_flash }`, and `ra_ram_code_init()` in
`tfm_hal_platform.c` copies the section as the first act of `tfm_hal_platform_init()`, before
anything can reach the flash driver. `__DSB`/`__ISB` follow the copy, since the bytes are then
executed. The initialiser ILINK leaves behind, `.ram_from_flash_init`, is read-only data and is
swept into `ER_RO_DATA` by its `ro data` catch-all - no placement directive needed.

**Result** - all four configurations now place `flash_hp_cf_write` in RAM at `0x2003f200`:
IAR L1, IAR L3, GNUARM L1, GNUARM L3.

**Why this shape rather than the alternatives in D029.** Excluding the section from a copy batch
argues with a decision ILINK makes for itself and would have to be re-checked at every isolation
level and toolchain version; `__ramfunc` means editing generated FSP source. Doing the copy
ourselves is the same code path at every isolation level, so the two can no longer diverge
silently - which was the real defect. The section stayed in flash with nothing in the build to
say so; only reading the map showed it.

**Still true:** the GNU build reaches the same result through the linker script and needs none
of this. Keep the two in step - a section that matters under one toolchain matters under both.

## D049 — The IAR NS toolchain emits `.srec` — closes the second open defect

**Date:** 2026-09-23 · **Status:** Accepted

`platform/ns/toolchain_ns_GNUARM.cmake` builds `.bin`, `.elf`, `.hex` and `.srec` for the
non-secure application; `toolchain_ns_IARARM.cmake` built the first three. The Renesas debug
launches flash S-records, so an NS application built with IAR had nothing to hand a launch
configuration that a GNU one did - the two toolchains disagreed about what a build produces.

Added the `${target}_srec` target and its dependency, using `ielftool --srec` as the other
conversions there use `ielftool`. Verified from a clean IAR NS build: `tfm_ns.srec` is emitted
alongside the rest.

**Shared file.** This is `platform/ns/`, not the RA6M5 port - it affects every IAR NS build, so
it belongs in `UPSTREAM_CHANGES.md` with the other shared-file changes and is a candidate for
the P6 Gerrit submissions.

**Still missing on the IAR NS side:** no `.map` is produced, so `_SEGGER_RTT` has to be read
out of the ELF with `nm`. Same family, not fixed here.

## D050 — RSIP-E50D gets its own accelerator directory, consolidated with SCE9 at P7

**Date:** 2026-09-24 · **Status:** Accepted

**What was expected.** `sce9/CMakeLists.txt` said RA8's engine "is a different driver API and
lands beside this as renesas/rsip, not as a variant of it." That is wrong, and the comment is
corrected.

**What is actually true.** FSP routes RSIP-E50D through the **same `r_sce` driver** —
procedures under `crypto_procedures/src/rsip_e50d/plainkey/`, the same `HW_SCE_*` primitive
names — and **33 of the 35 `rm_psa_crypto` ALT sources are byte-identical** between the
RA6M5 (SCE9) and RA8M2 (E50D) packs. The engine difference is below the ALT layer, not at it.

**Decision.** Copy to `platform/ext/accelerator/renesas/rsip_e50d/` for bring-up; do not
generalise now. One engine-parameterised directory is the right end state, and it is scheduled
for **P7**, where the ALT model is replaced by a PSA transparent driver anyway. Generalising
today would churn a validated RA6M5 path for no bring-up benefit, and the consolidation would
then be done twice.

**Cost accepted:** every fix to the shared build logic lands twice until P7. Recorded so the
duplication is a decision rather than an oversight.

---

## D051 — E50D ALT selection: SCE9's module set, CCM still out, P-521 and Curve25519 kept in

**Date:** 2026-09-24 · **Status:** Accepted · Refines [D043]

**Module set held to SCE9's.** E50D is a superset — the pack also ships `sha512_alt`,
`sha3_alt`, `chacha20_alt`, `chachapoly_alt`, `mlkem_alt` and `mldsa_alt`, none of which SCE9
has. All are left off, matching the e2 solution's own configuration, so the first RA8M2
bring-up differs from the validated RA6M5 one **by the engine alone**. Enabling one means its
`MBEDTLS_*_ALT` in `mbedtls_accelerator_config.h` *and* its source pair in the CMakeLists.

**CCM stays out, diverging from FSP.** The E50D solution enables `MBEDTLS_CCM_ALT`. The port
does not. Whether E50D formats B-blocks into the same 128 B buffer that caps SCE9's associated
data at 110 B is **unmeasured on this engine**, and taking FSP's configuration at face value is
exactly how PS init returned `-132` on RA6M5 ([D043]). Measure, then enable.

**P-521 and Curve25519 are kept, unlike SCE9.** `ecp_can_do_sce()` in `ecdsa_alt.c` returns 1
for `MBEDTLS_ECP_DP_SECP521R1` and `MBEDTLS_ECP_DP_CURVE25519` under
`BSP_FEATURE_RSIP_RSIP_E50D_SUPPORTED`, which `bsp_feature.h` defines as `1` for R7KA8M2. So
the E50D `crypto_accelerator_config.h` does **not** carry SCE9's two `#undef`s — that is the
one PSA-visible capability difference between the engines. Neither curve has run on hardware
yet; if either misbehaves, `#undef` it there rather than editing the ALT sources.
`PSA_WANT_ALG_DETERMINISTIC_ECDSA` stays undefined — FSP does not support deterministic
ECDSA on either engine, by design.

---

## D052 — The E50D pack is missing both session-leak fixes; RA8M2 bring-up proceeds anyway

**Date:** 2026-09-24 · **Status:** Accepted · Known-failing, deliberately

**The gap.** Of the 35 `rm_psa_crypto` ALT sources, the only two that differ between the SCE9
and E50D packs are `aes_alt.c` and `cipher_alt.c` — and the E50D copies are the **unfixed**
versions. Both session-closes added for SCE9 are absent:

| File | Missing | Was found as |
|---|---|---|
| `aes_alt.c` | session close in `mbedtls_aes_free()` | AES multi-part session leak |
| `cipher_alt.c` | CMAC session close in `mbedtls_cipher_free()` | crypto suite **28/64** cascade ([D044]) |

Not a chronology problem: RA6M5's pack is `12e48ca1` (20260923) and has the fixes; RA8M2's is
`9abf2155` (20260924, **newer**) and does not. The fixes landed in the SCE9 variant only.

**E50D needs them.** Verified rather than assumed: `HW_SCE_Aes{128,192,256}EncryptDecryptFinalSub`
exist under `rsip_e50d/plainkey/primitive/` (`hw_sce_p_p47f.c`, `hw_sce_p_p50f.c`), and both
`SCE_MBEDTLS_CIPHER_OPERATION_STATE_UPDATE` and `SCE_MBEDTLS_CMAC_OPERATION_STATE_UPDATE` are
defined. Same state machine, same primitives, same two leaks.

**Decision.** Bring the port up without them and treat the resulting crypto-suite cascade as a
**confirmed-expected failure**, not a port defect. The fix belongs in `rm_psa_crypto` for the
E50D variant, as it was done for SCE9; carrying it as a port-owned patch would add debt against
the P7 rebase for a defect that is not the port's.

**What this predicts:** the PSA Arch crypto suite cascading from the aborted-CMAC test the way
RA6M5 did at 28/64, and AES multi-part leaking sessions. If RA8M2 shows *different* crypto
failures, they are not this and should be diagnosed on their own.

## D053 — The E50D pack ships both session-leak fixes — supersedes [D052]

**Date:** 2026-09-24 · **Status:** Accepted · **Supersedes [D052]**

[D052] recorded that the RA8M2 pack was missing the two `rm_psa_crypto` session-leak fixes
the SCE9 pack had, and accepted a known-failing bring-up on that basis. **That is no longer
true.** The `6.7.0-beta0+20260924.4dfe9b7f` pack carries both:

| File | Fix | Verified |
|---|---|---|
| `aes_alt.c` | session close in `mbedtls_aes_free()`, `HW_SCE_Aes{128,192,256}EncryptDecryptFinalSub` | +32 lines, 4 symbol matches |
| `cipher_alt.c` | CMAC session close in `mbedtls_cipher_free()` | +10 lines, 4 symbol matches |

**So the prediction in [D052] is withdrawn.** The PSA Arch crypto suite is *not* expected to
cascade from the aborted-CMAC test. If RA8M2 shows a 28/64-style cascade anyway, it is a new
defect and must be diagnosed on its own rather than attributed to this.

**Why [D052] was written at all.** The pack in hand at the time
(`6.7.0-beta0+20260924.9abf2155`) genuinely lacked them, while the RA6M5 pack
(`12e48ca1`, *older*) had them — so it read as a per-device-variant gap rather than a
sequencing artefact. It was a same-day pack difference, not a missing fix.

**Carried forward:** check the two files after every pack uprev. They are the only two of the
35 ALT sources that have ever differed between the SCE9 and E50D variants, which makes them
the cheapest possible canary — `git diff` on `rm_psa_crypto/` after a regenerate.

---

## D054 — DF_EMULATION is 64 KB because FSP's MRAM sector size forces it

**Date:** 2026-09-24 · **Status:** Accepted · Refines [D051]

**The constraint.** FSP's generated `mcuboot_config.h` defines
`FLASH_AREA_IMAGE_SECTOR_SIZE` as `RM_MCUBOOT_MRAM_BLOCK_SIZE`, **0x8000 (32 KB)**. Every
MCUboot area's offset and size must be a whole multiple of it, and DF_EMULATION sits between
BL2 and the first slot, so its size shifts every slot after it.

On a 1 MB device with a 64 KB BL2 that leaves exactly one solution:

| DF_EMULATION | Remainder | Splits into 2xS + 2xNS on 32 KB? |
|---|---|---|
| `0x8000` (32 KB) | `0xE8000` | **no** |
| **`0x10000` (64 KB)** | `0xE0000` | **yes** — S `0x48000`, NS `0x28000` |
| `0x18000` (96 KB) | `0xD8000` | **no** |

So 64 KB is not generosity and not alignment convenience — it is the only value that works.
An earlier revision used 8 KB "to match RA6M5's secure data flash" and compensated by setting
`FLASH_AREA_IMAGE_SECTOR_SIZE` to `0x1000`. That was wrong twice over: it overrode
FSP-generated configuration (see the TODO in PROJECT_PLAN.md), and it produced slots of 9.875
sectors, which `flash_area_get_sectors()` rejects — a failure visible only on hardware, as
`boot_read_sectors()` returning `BOOT_EFLASH`.

**The mistake was reading `r_mram.c`'s `flash_info.block_size` (32) as the sector size.** That
field is the *write* unit, `BSP_FEATURE_MRAM_PROGRAMMING_SIZE_BYTES`, which FSP uses for
`MCUBOOT_BOOT_MAX_ALIGN` and which `MCUBOOT_ALIGN_VAL` matches. Two different numbers, both
needed, neither interchangeable.

**Consequence — storage is 8x RA6M5's.** PS and ITS get 31,744 B each instead of 3,072,
with NV counters unchanged at 2,048. The PS budget assertion now has 15,008 B of slack against
584 needed, where at 8 KB it had 88. This retires the open question in
`ra8m2_layout_checks.c` about whether the 32 B MRAM write alignment would eat that margin —
at this size it cannot.

`PS_MAX_ASSET_SIZE` and `PS_NUM_ASSETS` in `config_tfm_target.h` stay at RA6M5's 512 and 5 for
bring-up, so the first RA8M2 run is comparable to the validated one. They are now far more
conservative than the space requires and can be raised; the headroom is documented for the
user in the platform's configuration notes.

## D055 — RA8M2 full chain builds and links on IAR; four defects found by building it

**Date:** 2026-09-24 · **Status:** Accepted · Not yet run on hardware

BL2, `tfm_s` and `tfm_ns` all build and link for RA8M2, at the application configuration
(Debug / isolation 1 / SFN / SPM trace on). Measured placement:

| Image | Range | Size | Headroom |
|---|---|---|---|
| `bl2` | `0x02000000`-`0x0200C5C3` | 50,627 B | +14,909 in 64 KB |
| `tfm_s` | `0x02020200`-`0x0206789C` | — | **+868 B** before the NSC veneers |
| NSC veneers | `0x02067C00`-`0x02067C40` | 64 B | at `FLASH_CPU0_C_START` exactly |
| `tfm_ns` | `0x120B0200`-`0x120B1A00` | 6,144 B | +156,928 in 160 KB |

Both signed images pad to exactly their slot spans (`0x48000`, `0x28000`), so imgtool and
`flash_layout.h` agree. The NS side needed **no source changes at all** — it configured and
linked first time, and emits `.srec`, so [D049] carries to this port.

**868 bytes of secure headroom is the number to watch.** That is the Debug build at isolation 1;
the same measurement on RA6M5 said Debug costs 78 KB over MinSizeRel, so the application
configuration should move off Debug before anything is added to the secure image.

**What building it found — none of these were visible by inspection:**

1. **ITS/PS program unit 32 → NAND emulation.** `its_flash.c` switches backend above 16 and
   allocates two static buffers per partition, ~62 KB of secure RAM. MRAM writes SINGLE BYTES
   (`block_size_write` is 1; `mram_write_data()` copies byte at a time and flushes partial
   buffers), so 32 is the programming buffer, not a minimum write. Now 4, as on RA6M5.
2. **`fsp_module_common.cmake` never applied `COMPILER_CP_FLAG`.** TF-M adds it per target, and
   the FSP libraries are created in the port's own macro, so they took the compiler's default
   FPU. Invisible on M33 (default `none`); on M85 ILINK refused the image with `Lt006`,
   VFP against No vfp.
3. **The OFS addresses were RA6M5's** — see [D056].
4. **The brick guard was inert** — see [D056].

**Toolchain note:** only `ra8m2_iar_*` projects exist, so there is no GCC recipe. The
QUICKSTART's GNUARM section named `ra8m2_gcc_*` projects that have never existed, inherited from
RA6M5; corrected, and `scripts/app_build_ra8m2_iar.bat` now captures the working recipe.

---

## D056 — OFS addresses are generated, and a guard that reports PASS on the wrong window is worse than none

**Date:** 2026-09-24 · **Status:** Accepted · Extends [D002]

**The transcription defect.** `region_defs.h` hand-wrote the thirteen RA6 option-setting
addresses, and because the RA8M2 port was seeded from RA6M5 they were RA6M5's:
`.option_setting_ofs0` linked at `0x0100A100` when this part's OFS0 is at `0x02c9f040`. The
image wrote option words outside the device's option memory and never touched its real OFS or
block-protect registers. The comment above them even asserted "the same start addresses as
RA6E1/RA6M4" and "2 MB of code flash", both false.

**Fix.** `option_settings.h` is GENERATED at configure time from the bootloader project's
`Debug/memory_regions.icf`, exactly as `bsp_partitions.h` is generated from
`bsp_linker_info.h`. Nothing is transcribed. `bsp_linker_info.h` does not carry the OFS
addresses, which is why they were hand-written in the first place.

**RA8M2's group set is not RA6's:** 26 against 13. No `DUALSEL`, `BANKSEL` or non-OTP `PBPS`;
new `OFS2`, `OFS3(+_SEC/_SEL)`, `SAS`, and an OTP block (`FSBLCTRL0-2`, `SAMR`, `SACC00-13`,
`PBPS(+_SEC)`, `ZHUK`). `BPS` is `0x80`, not `0xC`.

**The silent-drop defect.** `OFS2`, `OFS3_SEC` and `OFS3_SEL` were set in the solution and
emitted by nothing, because `bl2_option_setting.c` came from RA6M5. No section, so no linker
error, so no diagnostic — a security setting configured and quietly not applied. Now emitted,
and every group FSP recognises that the port does NOT place is an `#error` naming the three
edits required. Verified to fire for `BPS` and `OTP_PBPS_SEC`, and not for the
`OFS1_SEC_NO_HOCOFRQ` variant, which is a field of `OFS1_SEC` rather than a separate word.

**The guard was inert, which is worse than absent.** `check_ofs.py` hardcoded RA6's
`0x0100A100-0x0100A2CF`. Run against an RA8M2 BL2 carrying six OFS segments it printed

```
  bl2.axf        CLEAN (no OFS segments)
  PASS: OFS (if any) is in discrete per-word segments - safe to flash.
```

It would also have passed the genuinely wrong build, because `0x0100A100` IS inside its window
and the segments were discrete: **it checks spanning, never whether the addresses belong to the
device.** `--region` is now required, BL2 passes `--require-segments` so an empty result fails,
and the RA6 ports pass `--ra6-default`. Negative-tested four ways, including that the old
hardcoded window now fails.

**Provenance rule, newly documented:** only the BOOTLOADER project's OFS settings land.
`bl2_option_setting.c` compiles into `platform_bl2`, so values resolve through `FSP_BL2_APP_DIR`
and addresses through its `memory_regions.icf`. Editing OFS in the SECURE project has no effect
and nothing warns — and both projects currently define the same six groups, which makes the
mistake easy and invisible.

**Unchanged:** the placement rule. Discrete regions per word, one tiny `PT_LOAD` each. Verified
`readelf -l`: six 4-byte LOAD segments at `0x02c9f040/044/0c0/0c4/120/124`, gaps untouched.

---

## D057 — The GCC leg is the reference; the IAR solution's RAM split is stale

**Context.** Both project sets were regenerated on pack `6.7.0-beta0+20260925.818e720c`. Diffing
all ~55 memory partitions in the two `solution.xml` files, they agree everywhere except two lines:

```
-RAM_CPU0_C 0xE9C00 0x400    (gcc, fixed)
-RAM_CPU0_S 0x0     0xE9C00
+RAM_CPU0_C 0xE9F80 0x80     (iar, FSP default)
+RAM_CPU0_S 0x0     0xE9F80
```

Flash is byte-identical between them. The 1 KB NSC fix went into the GCC solution only.

**Why they cannot stay split.** Two solutions for one part feed **one** RDPM entry. RDPM already
refused 768 B for the NSC, so 128 B is out. The IAR set also keeps the `Lp035` alignment warning,
where ILINK silently relocates `__ddsc_RAM_NSC` to `0x220EA000` — inside NS RAM.

**Decision.** With the IAR licence expired, the **GCC set is the reference** for the RA8M2 layout.
The IAR `solution.xml` takes the same two lines and is regenerated when the licence is back;
regeneration needs RASC, not the compiler, so this is not gated on the licence — only the build is.
`app_build_ra8m2_iar.bat` carries the divergence in its header until then.

**Consequences of the RAM change, measured on the rebuilt GCC chain:**

| | before | after |
|---|---|---|
| secure RAM region | 935.875 KB | **935 KB** |
| NS RAM region | 936.125 KB | **936 KB** |
| NSC | 128 B | **1 KB** |

Whole-KB throughout, which is what RDPM requires. No size regression: `tfm_s` 293,564 B, `bl2`
27,552 B, `tfm_ns` 6,916 B. OFS guard PASS — `bl2.axf` carries six discrete 4-byte segments at
`0x02C9F040/044/0C0/0C4/120/124`, `tfm_s.axf` none.

**Headroom, unrelated to this change but now visible.** `tfm_s` is **293,564 B against a 294,400 B
slot — 99.72%, 836 bytes spare**, at MinSizeRel / isolation 1 / SFN. Isolation 2, the IPC backend,
or another partition will not fit. Growing the secure slot means moving `__BL_0_P_H` and every
partition above it, so it is a layout revision, not a tweak. See [D054] for why `DF_EMULATION`
cannot give back less than 64 KB.

**Also added.** `scripts/app_build_ra8m2_gcc.bat`, which did not exist — the GCC chain had been
built by hand. It pins `MinSizeRel` (Debug does not fit on GNUARM, [D055]) and quotes `%GCC_BIN%`
everywhere, the `(x86)` paren bug from `psa_arch_spe.bat`.

---

## D058 — The flat `.bin` is a second route to the brick, and the ELF guard never saw it

**Found while listing the GCC artifacts to flash.** `bl2.bin` was **13,234,472 bytes**. The MRAM
image is 27,552.

`objcopy -O binary` lays the flat image out from the lowest load address to the highest and
**zero-fills every gap**. BL2's last OFS word is at `0x02c9f124`, so the flat binary spans
`0x02000000`-`0x02c9f128` and 13,206,920 bytes of it are fill — fill that covers the option
memory. Flash it at the MRAM base and it is [D0xx/DESIGN.md 8.4] again: block-protect written to
zero, part dead.

**What makes this worse than the original.** The ELF was *correct* — six discrete 4-byte `PT_LOAD`
segments, and `check_ofs.py` PASSed, rightly. The guard reads program headers, and program
headers are exactly what `objcopy -O binary` discards. A build could pass every check this port
has and still hand you a brick in the output directory. `.hex` and `.srec` are record-based and
skip the gaps; **only the flat binary coalesces**.

**RA6 has it too, unfixed.** `/c/b/m5app/bin/bl2.bin` is **16,818,820 bytes**, spanning
`0x00000000`-`0x0100a284`. That is the precise address range that killed the two EK-RA6M4 boards
on 2026-07-21. Not fixed here — out of the RA8M2/GCC scope this session — and it is the first
thing to do on the RA6 leg.

**Fix, RA8M2 only.** Two parts, because either alone is insufficient:

- `ra8m2_strip_ofs_from_bin(bl2)` re-emits the binary with
  `--wildcard --remove-section=.option_setting*`. Its own target, not
  `add_custom_command(TARGET bl2_bin POST_BUILD)` — that form requires the target to be created
  in the same directory and `bl2_bin` is made in `bl2/`. `add_convert_to_bin_target()` is generic
  upstream code shared by every platform, so it is not the place to patch.
- `check_ofs.py --check-flat-bin` verifies the result, and the guard target depends on the strip
  target so it inspects the file that actually landed.

**The verdict is taken from the file on disk, not from the ELF.** An earlier cut of this derived
it from the ELF alone to dodge the ordering question; that would have failed the build forever,
since the ELF always implies a spanning binary whether or not the strip ran. **A missing `.bin`
is a FAILURE, not a pass** — the same rule as [D056]: a guard that cannot see its subject must
not print PASS.

**Verified.** `bl2.bin` 13,234,472 → **27,552**, byte-identical to the stripped reference. The
`.hex` still carries all six words as discrete 4-byte records at
`0x02c9f040/044/0c0/0c4/120/124`, so flashing the `.hex` or `.elf` still programs the options.
Guard negative-tested five ways, including with the `.bin` deleted.

**Flashing rule for this port:** BL2 by `.elf` or `.hex`. `bl2.bin` is now safe but carries no
option settings, so a `.bin`-only flash silently leaves the OFS unprogrammed.

---

## D059 — P-521 and Curve25519 come out of the E50D config until after TF-M 2.3

**Decision.** `rsip_e50d/crypto_accelerator_config.h` now `#undef`s `PSA_WANT_ECC_SECP_R1_521`
and `PSA_WANT_ECC_MONTGOMERY_255`, matching the SCE9 configuration. **To be restored after the
TF-M 2.3 migration** — deleting the two `#undef`s is the whole change.

This is a **flash** decision, not a capability one. E50D really does have procedures for both,
and [D051] kept them on exactly that reasoning. What that missed is the cost: each HW procedure
is a large constant instruction table in its own object, and these two curves drag in their
transitive closure of `hw_sce_p_func###.o` members.

**Measured on `tfm_s`, GCC MinSizeRel:**

| | before | after |
|---|---|---|
| `.text` | 239,142 | **216,165** |
| `HW_SCE_*` tables | 127,542 | **105,708** |

**−22,977 bytes of text.** For scale, the same tables are **8,124 bytes on SCE9** — the E50D set
is still 13× larger after the removal, which is the engine, not the configuration.

The port keeps secp256r1, secp256k1, brainpoolP256r1, secp384r1 and brainpoolP384r1 — the same
set the validated RA6M5/RA6E1 ports advertise. Nothing in TF-M needs more; attestation signs with
`PSA_ALG_ECDSA` on P-256.

---

### Correction to [D057]: the "99.72% full, 836 bytes spare" figure was wrong

D057 reported the secure slot at 99.72% and treated 836 bytes as the remaining headroom, and I
repeated that as a hard constraint. **It is an artifact of how the region is measured.**

GNU ld's "Memory region Used Size" runs to the end of the last section placed in the region, and
`.gnu.sgstubs` — the NSC veneers — is **pinned at `0x020afc00`, the top of the region**, because
the NS image has to find it at a fixed address. So the figure reads ~99.7% **whatever the image
size is**. The proof: text fell by 22,977 bytes and `tfm_s.bin` stayed at **exactly 293,564**.

The real picture:

```
main image   0x02068200 - 0x0209CEAC    216,748 B
gap (zero fill)                          77,140 B   <- the actual free space
.gnu.sgstubs 0x020AFC00 - 0x020AFCBC        188 B
```

**Free space in the secure slot is ~77 KB, not 836 bytes** (~54 KB before this change). `tfm_s.bin`
is the whole span including the fill, which is why it does not shrink. Isolation 2, the IPC
backend and a Debug build were never ruled out on size the way D057 said — that needs retesting
rather than assuming either answer.

**Rule for this port: do not read the linker's region-usage percentage as headroom while the NSC
is pinned at the top of the region.** Measure the gap between the end of the main LOAD segment
and `.gnu.sgstubs`.

---

## D060 — RA6M5 execution-path audit: what the boot trace turned up

Traced RA6M5 reset&rarr;runtime to build an execution map
(<https://claude.ai/artifact/6x3gWcieKoCZj3SbfGHrvh>). Everything below is verified against the
built image or the link map, not read off source. No change made to the RA6M5 port — these are
findings, recorded so they are not rediscovered.

**Architectural fact worth stating plainly: the SAU is FSP's, not TF-M's.** `sau_and_idau_cfg()`,
`mpc_init_cfg()` and `ppc_init_cfg()` in `target_cfg.c` are all no-ops. The real SAU/IDAU
programming is `R_BSP_SecurityInit()` &rarr; `R_BSP_SAUInit()` inside FSP's `SystemInit()`, i.e.
**before `main()`** and before `tfm_hal_set_up_static_boundaries()`. On a canonical TF-M diagram
the isolation-boundary box sits in `tfm_core_init`; here it moves back into `Reset_Handler`. The
comment in `target_cfg.c:36` claiming TF-M's common framework programs the SAU is wrong — the
framework just calls the empty function.

### Finding 1 — `SECUREFAULTENA` is never set

Every other TF-M platform calls `enable_fault_handlers()` and `system_reset_cfg()` from its
`tfm_hal_platform.c`. This port defines both in `target_cfg.c` and **calls neither**.
`target_cfg.o` links with **zero bytes of `.text`** — wholly garbage-collected — and neither
symbol is in `tfm_s.axf`.

Most of the effect is covered by accident, which is why it went unnoticed: FSP sets
`AIRCR.SYSRESETREQS = 1` and `BFHFNMINS = 0`; TF-M sets `AIRCR.PRIS`; `ARM_MPU_Enable()` sets
`SHCSR.MEMFAULTENA`. **The gap is `SHCSR.SECUREFAULTENA`, `BUSFAULTENA` and `USGFAULTENA`.**

Not an isolation hole — SAU and MPU are hardware and unaffected, and a violation still traps. But
it escalates to `HardFault_Handler` instead of the `SecureFault_Handler` that `faults.c` provides,
losing `SFSR` routing on precisely the fault worth diagnosing. Note the oddity: TF-M sets
SecureFault's *priority* and leaves it disabled.

### Finding 2 — the secure image hashes 297 KB of zero fill every boot

`.gnu.sgstubs` must sit in the NSC window at `0x11F800` because the device order is
Secure|NSC|Non-secure. Secure code ends at `0x0D557C`. The gap is fill **inside** the MCUboot
image, so `img_size` is 521,932 against 218,492 of content, and `MCUBOOT_VALIDATE_PRIMARY_SLOT`
is defined — SHA-256 + ECDSA-P256 over all of it, 58% zeros, at every boot.

The NS image does not pay this: imgtool pads the *file* to the slot with 0xFF but `img_size`
stays 6,208, so the padding is outside the hash. The secure image cannot do the same because its
fill is interior. A genuine trade — the gap *is* the growth room — but it should be a measured
choice, not an accident. Same shape on RA8M2 at 77,140 bytes.

### Finding 3 — RA6M5 has no mechanical guard for the `bl2.bin` brick

`bl2.bin` is **16,818,820 bytes**, `0x00000000`–`0x0100A284`, 16,791,916 of it zero fill over the
option memory. DESIGN.md 8.4 and MACHINE_HANDOFF.md both already say to flash the `.hex` — but
8.4 frames it as *"pads `bl2.bin` to ~16.8 MB"*, which reads as an inconvenience rather than a
part-killer, and it is a comment, not a check. [D058] gave RA8M2 the strip + `--check-flat-bin`
guard. **Porting both to RA6M5/RA6E1/RA6M4 is the first item on the RA6 leg.**

### Smaller findings

- **BL2's stack seal is 10 KB from its stack.** `CMakeLists.txt:636` claims `__ARM_FEATURE_CMSE != 3`
  for BL2. True of the preprocessed linker script, false of the C compile — `-mcmse` reaches the
  `bl2` target via `platform_bl2 PUBLIC`. So `__TZ_set_STACKSEAL_S` runs and lands on the weak
  definition in an orphaned `.msp_stack_seal_res` at `0x200009A8`, while the stack is
  `0x200034C0`–`0x20004CC0`. Inert in a flat build; the comment is still wrong.
- **All 96 peripheral interrupts are targeted non-secure.** `bsp_irq_cfg()` writes
  `ITNS[] = 0xFFFFFFFF` because the secure project links zero events. Correct today; it is FSP
  that decides this, not `target_cfg.c`, whose NVIC functions are documented no-ops and are not
  called anyway.
- **`tfm_interrupts.c` is in no CMake file and no map**; `tfm_peripherals_def.c` is listed but its
  object is absent (`CONFIG_TFM_MMIO_REGION_ENABLE` off). Both switch on untested the moment a
  partition claims an IRQ or a peripheral — which the PSA Arch partitions do.
- **1 KB of NSC SRAM (`RAM_CM33_C`) holds nothing**, same as RA8M2 before the fix.
- **`bl2_main.c` carries a local patch** (`BL2_HALT_AT_MAIN`, `:112–125`) that will conflict on the
  2.3 uplift. Belongs on the upstream-delta list.
- **`psa_crypto_init()` never crosses the boundary** — it returns `PSA_SUCCESS` NS-side. Step 3 of
  the NS smoke test proves nothing about the boundary; steps 4/5 are the first real crossings.

---

## D061 — Secure interrupts on RA: delete the dead HAL, and write down why the upstream recipe does not apply

**Trigger.** [D060] found `tfm_interrupts.c` in no build. Following that up showed the RA ports
cannot service a secure peripheral interrupt at all, and that the mechanism they document for
adding one does not work.

### What was wrong

- **All four `renesas/*/tfm_interrupts.c` were byte-identical dead code** (md5
  `e818d27e…`), referenced by no CMakeLists. They duplicated
  `platform/ext/common/tfm_hal_nvic.c` — which already implements exactly the three required HAL
  functions — and added `tfm_hal_irq_set_priority()`, which **is in no TF-M header and is called
  by nothing**. It was invented.
- **`ra6m4/CMakeLists.txt:72` wired in the wrong file**: `ext/common/tfm_interrupts.c`, Arm's
  TIMER0 *test fixture*. It defines `TFM_TIMER0_IRQ_Handler` and **none** of the HAL, and
  references `TFM_TIMER0_IRQ`, which no RA port defines. Enabling FLIH/SLIH there would fail to
  compile *and* fail to link. (`DEFAULT_IRQ_PRIORITY` is defined; only `TFM_TIMER0_IRQ` is not.)
- **The vector table cannot reach FSP's ISRs.** `startup_ra*.c` declares one self-contained table
  with `[16 ... N] = Default_Handler`. Those are array initialisers, not weak symbols, so the
  comment promising that "the weak `Default_Handler` binding is overridden at link time" is wrong
  for the 96 ICU slots — it is only true of the 16 named Cortex exceptions. FSP instead uses two
  contiguous tables (16 fixed + `g_vector_table[]` in `.application_vectors`), and
  **`.application_vectors` is placed by no SPE linker script.** Net effect of following the port's
  own instructions: `bsp_irq_cfg()` correctly marks the slot secure, the interrupt fires, and
  lands in `Default_Handler`, which is `while(1);`.

### The RA-specific rule, which inverts the upstream model

Every Arm port makes an IRQ secure at run time with `NVIC_ClearTargetState()` inside the
partition's `<source>_init()`. **On RA that is wrong.** Attribution lives in *two* registers,
`NVIC->ITNS` **and** `R_CPSCU->ICUSARG`, written together by `bsp_irq_cfg()` under
`BSP_REG_PROTECT_SAR`; FSP's own comment says they must match. `NVIC_ClearTargetState()` writes
only one of them. And there is no runtime API for the other — the whole `R_BSP_Irq*` family sets
priority, context and pending only. `ICUSARG` is written exactly once, in `SystemInit()`, from the
generated `g_interrupt_event_link_select[]`.

> **An interrupt is secure if and only if the SECURE e2 project configures it.**

Attribution is a build-time, configurator-driven property on this family.

### Decision

1. **Deleted** all four `renesas/*/tfm_interrupts.c`.
2. **All four CMakeLists** now pull `${PLATFORM_DIR}/ext/common/tfm_hal_nvic.c` under the existing
   `FLIH_API OR SLIH_API` guard — the real HAL, not the test fixture. (STM32H5 is the upstream
   precedent for doing exactly this.)
3. **`target_cfg.c` in all four** now carries the full recipe next to the two no-op NVIC functions
   — including that neither is called, why `NVIC_ClearTargetState()` must not be used here, and
   the five steps to add an interrupt. That is where someone adding a timer will look.

**Keep the single 112-entry vector table.** An earlier draft of this proposed adopting FSP's
two-table layout; that is wrong, because it hands each ICU slot to FSP's own driver ISR
(`sci_uart_rxi_isr`), which calls the driver callback directly and **bypasses the SPM entirely**.
The port owning `startup_ra*.c` is an advantage. Override individual slots keyed on the generated
macro — `[16 + VECTOR_NUMBER_xxx] = TFM_xxx_Handler` — so RASC stays the source of truth and
renumbering cannot silently break it.

Nothing upstream routes through a vendor callback registry: `spm_handle_interrupt()` must run in
the exception context. The pattern to copy for the ISR body is Infineon PSoC64's (ack with the
vendor driver, then call SPM) — NXP's LPC55S69 states the same idea more clearly but is
bit-rotted, with `TFM_TIMER0_IRQ_Handler` unresolved in v2.2.0.

### Context worth keeping

**Almost nobody does this upstream.** The only `irqs:` blocks in the whole TF-M tree are the
mailbox agent (itself SPM-adjacent) and the `tf-m-tests` FLIH/SLIH partitions. Secure UARTs are
polled everywhere; MPC/PPC fault IRQs are SPM-owned. A port with no secure partition interrupts is
the mainstream, CI-covered configuration — so this was a latent-defect cleanup, not a missing
feature.

**SFN supports interrupts.** `spm_handle_interrupt()` has an explicit
`#if CONFIG_TFM_SPM_BACKEND_SFN != 1` branch and `interrupt.c` is gated on FLIH/SLIH only, not on
the backend. SFN forces isolation 1, so a FLIH is called directly, privileged, in handler mode.
Use FLIH: SLIH under SFN only works if a caller is already blocked inside one of the partition's
own SFN services, because `psa_wait(PSA_BLOCK)` is a `__WFI` spin on the single thread.

**Verified:** RA8M2 GCC chain rebuilds clean, OFS guards pass, image sizes byte-identical
(`tfm_s` 293,564 / `bl2` 27,552 / `tfm_ns` 6,916) — the deleted files were never compiled.

---

## D062 — RA declares test capabilities; ra6m4 could not build TEST_S at all

**Two blockers found by the test-surface audit, both fixed.**

**No RA part had a `tests/` directory.** tf-m-tests reads platform capabilities from the
*installed* tree — `tests_reg/CMakeLists.txt:38` includes
`${CONFIG_SPE_PATH}/platform/tests/tfm_tests_config.cmake` and
`tests_psa_arch/CMakeLists.txt:29` the psa_arch one, both `OPTIONAL`. With no such file the
includes silently found nothing. That is *why* the FLIH/SLIH suites were absent rather than
reported unsupported, and why `-DPSA_API_TEST_TARGET=renesas_ra` had to be passed by hand on
every PSA Arch invocation. All four ports now ship `tests/` **and** an
`install(DIRECTORY ... DESTINATION ${INSTALL_PLATFORM_NS_DIR})` rule — the files are useless
without the install, which is the part an521 does at its `CMakeLists.txt:191`.

The IRQ flags are deliberately **left unset**: `config.cmake:78-86` auto-enables
`TEST_NS_FLIH_IRQ` whenever `PLATFORM_FLIH_IRQ_TEST_SUPPORT` is on and `TEST_NS` is asked for, so
turning them on before the platform side exists would break every `TEST_NS` build. The file lists
the four things needed (secure timer instance, `plat_test.c`, `TFM_PERIPHERAL_TIMER0`/
`TFM_TIMER0_IRQ`, the vector override).

**`ra6m4` was missing `TFM_PERIPHERAL_STD_UART`** — the only one of the four. tf-m-tests'
*common* `tfm_secure_client_service` declares it as an `mmio_region`, and that partition links
whenever `TEST_S` is on, so `tfm_hal_bind_boundary()` would have failed the allow-list lookup and
panicked during partition init. **`TEST_S` could not have built on ra6m4 at all.** Added, with
SCI0 at `0x40118000` (`R_SCI0_BASE` in `R7FA6M4AF.h` — same address as RA6M5, confirmed from the
device headers rather than assumed).

### Scope of what was never tested

`TEST_S*`/`TEST_NS*` appear in **no** RA `config.cmake` and in **no** build cache under `C:\b`;
`TEST_BL2=OFF` in all 8. The entire `tf-m-tests/tests_reg` tree — 13 suites, ~25 toggles, 7 test
partitions — has never been built for any RA part. Everything run to date is a smoke app or PSA
Arch (`CRYPTO`, `STORAGE`, `INITIAL_ATTESTATION`).

**And the shipping default has never been tested.** RA defaults to SFN + isolation 1; every PSA
Arch build forced `IPC` + L3 (5 of 5). The configuration that ships is covered by a smoke app and
nothing else.

### Trap worth recording

`-DTEST_S=ON -DTEST_NS=ON` passed to the **TF-M** build is **silently ignored** — it produced a
byte-identical `tfm_s` (text 216,165, bin 293,564) with no test partitions and no warning. Those
are meta-flags for tf-m-tests; `tests_reg/utils/regression_flag_parse.cmake:25-42` translates them
into the internal `TFM_S_REG_TEST`/`TFM_NS_REG_TEST`, and that only runs when
**`tf-m-tests/tests_reg/spe`** is the top-level project. The correct invocation is
`cmake -S <tf-m-tests>/tests_reg/spe -DCONFIG_TFM_SOURCE_PATH=<tfm> ...`, which sets
`CONFIG_TFM_TEST_DIR` and configures TF-M as a sub-build; the NS side is then
`-S <tf-m-tests>/tests_reg -DCONFIG_SPE_PATH=<spe>/api_ns`.

---

## D063 — Pinned CMSE veneers get their own MEMORY region; the regression suite now links

**The defect.** `VENEERS()` places `.gnu.sgstubs` at `TFM_LINKER_VENEERS_START` into the `FLASH`
region. When that start is an **absolute** address at the top of the secure partition — which is
what RA does, because the solution fixes the NSC window there — ld advances FLASH's allocation
pointer to the end of the veneers. **Every `AT > FLASH` section emitted after `VENEERS()` then
takes its load address from the top of the partition**, in whatever spare bytes the NSC window
leaves, while the flash below the veneers is unreachable.

Measured on RA6M5 with the regression tests linked in:

```
code          0x000A0000 - 0x000E4144
FREE          0x000E4144 - 0x0011F800   243,388 bytes (238 KB) unusable
veneers       0x0011F800 + 0x40
data LMAs     0x0011F840 -> past the slot end
```

It failed imgtool by **177 bytes with 238 KB free**. RA8M2 failed the same way with
`.TFM_DATA will not fit in region FLASH`, over by **528 bytes**.

**This was already half-fixed.** The template's own comment above `.ER_CODE_SRAM` documents the
identical mechanism, discovered on ra6e1 (overflowed by 382 bytes with 82 KB unused), and hoists
**that one section** above `VENEERS()`. `.TFM_DATA` and the other RAM-init load images were never
moved, so the cause survived.

**Fix.** New opt-in `TFM_LINKER_VENEERS_OWN_REGION` in `tfm_isolation_s.ld.template`: `FLASH` ends
where the veneers begin, and `.gnu.sgstubs` goes into its own `VENEER` region, so pinning it cannot
touch FLASH's pointer. Fully gated — no behaviour change for a platform that does not set it.
Enabled on all four RA ports (ra6m4 also needed `TFM_LINKER_VENEERS_SIZE`).

**Nordic nrf5340/nrf91 and Laird bl5340 must not set it.** They define the same
`TFM_LINKER_VENEERS_SIZE` and `..._LOCATION_END` macros, but compute
`TFM_LINKER_VENEERS_START` from `.` so the veneers float to just above the code. Their start is not
a constant, so it cannot be a MEMORY origin — and they never had the problem. **Do not auto-derive
this from the existing macros**; that was the first instinct and it would have changed their
layout.

**Verified.** Data LMAs now sit immediately after the code (`0x000E4144` on RA6M5, `0x020ABBB8` on
RA8M2), veneers still pinned in the NSC window. Trailer slack 1,984 bytes against the 384 needed.
App builds unaffected except `tfm_s.bin` shrinking **124 bytes** — exactly the load images that
used to sit above the veneers (`0x020AFCBC` → `0x020AFC40`). OFS guards still pass.

**Not fixed by this:** the secure image still *spans* to the veneer end, so the zero fill between
code and veneers is still inside `img_size` and still hashed at every boot ([D060] finding 2).
That is a layout question, not a linker one.

### Two traps hit getting the regression build to run

- **`lib/ext/tf-m-tests/version.txt` pins `TF-Mv2.1.2-RC2`**, inherited from upstream's own v2.2.0
  release commit (`3d9621e73`). `tests_reg/CMakeLists.txt` includes `check_version`
  **unconditionally** — `TFM_TESTS_REVISION_CHECKS=OFF` does not gate it — and it hard-fails when
  `git rev-parse` cannot resolve the tag. The tag exists on the tf-m-tests remote but was not
  fetched locally. Fixed with `git fetch --tags`, **not** by editing `version.txt`: the local repo
  is at `TF-Mv2.2.2`, so the check now warns that HEAD is ahead of the recommendation and
  continues, which is the honest state.
- **`cmake --build` on the SPE wrapper is not enough.** `tests_reg/spe/CMakeLists.txt` installs
  `secure_fw/partitions/initial_attestation/*.h` into `api_ns/` through an `install()` rule, so
  without `cmake --install` the NS attestation suite fails on a missing `attest_token.h`.

### What is now covered

Six NS suites link and fit (106,024 B in a 458,752 B slot): `ns_attestation_interface`,
`ns_crypto_interface`, `ns_platform_interface`, `ns_psa_its_interface`, `ns_psa_ps_interface`,
`ns_sfn_interface` — i.e. the Tier-1 gaps from [D062], including token *verification* and the SFN
backend that ships by default and had never been tested. Still to do: run them on hardware.

---

## D064 — BL2 masking interrupts is sound and complete; the SPMON hazard does not exist on these parts

**Question raised:** does it make sense for BL2 to disable interrupts, both because it uses none and
because there is a window during secure init — before VTOR is set — where an interrupt would be
undefined behaviour?

**Answer: yes on both counts, and the second reason is the stronger one.** The handover window is
wider than VTOR alone. Across the jump, all of the following is stale or unset:

- **VTOR** still points at BL2's table until the secure image's `SystemInit()` rewrites it
  (`system.c:237`).
- **The SAU is never configured in BL2 at all** — BL2 is a flat FSP build
  (`FSP_TZ_DEFS_BL2` empty), so `R_BSP_SecurityInit()`/`R_BSP_SAUInit()` first run in the secure
  image.
- **MSPLIM was zeroed** by `boot_platform_start_next_image()` before the branch.
- **BL2's RAM was just erased** — `boot_clear_ram_area()` wipes `.data`, `.bss`, stack and heap
  immediately before the jump.
- **Every peripheral is attributed secure** (`PSARB/C/D/E = 0`) from BL2's flat build.

An interrupt landing there would vector through BL2's table into handlers whose data no longer
exists, with no TrustZone attribution programmed.

**The masking genuinely covers it.** `__disable_irq()` at `startup_ra6m5.c:140` is never undone
anywhere in the BL2 path — verified: no `__enable_irq`/`cpsie` in `bl2/`, `boot_hal_bl2.c`,
`bl2_boot_hal.c` or the startup file. PRIMASK therefore persists from BL2 reset through to
`tfm_hal_platform.c:134` in the secure image. The secure `Reset_Handler` also re-disables
immediately, so the secure side does not *depend* on BL2's state — belt and braces on both ends.

The enable point is equally deliberate and already documented in place
(`tfm_hal_platform.c:116-132`): with PRIMASK set, SVCall is masked and the first `svc` escalates to
HardFault. That is what killed ITS partition init on 2026-08-29 —
`LOG_INFFMT` → `printf` → `tfm_output_unpriv_string()`'s `svc 2`, faulting with `HFSR.FORCED` and
every `CFSR`/`BFSR`/`MMFSR`/`UFSR`/`SFSR` bit clear, the signature of a masked SVCall and easily
misread as a fault in the code being logged from.

### Correction: I claimed BL2 leaves an unmaskable NMI source armed. It does not.

PRIMASK does not mask NMI, so the reasoning above has a gap in principle, and I asserted FSP's
`SystemInit()` fills it — arming the stack-pointer monitor with
`BSP_STACK_POINTER_MONITOR_NMI_ON_DETECTION` on **BL2's** stack window, writing
`R_ICU->NMIER` (whose bits FSP's own comment says "cannot be cleared after reset"), and jumping with
it still armed on a window the secure image never enters.

**That block never compiles on any of these parts.** `BSP_FEATURE_BSP_HAS_SP_MON` is `0UL` for
**all four** — ra6m5, ra8m2, ra6m4, ra6e1 (single definition each, in
`ra/fsp/src/bsp/mcu/<part>/bsp_feature.h`). The `#if BSP_FEATURE_BSP_HAS_SP_MON` at `system.c:326`
is false, so no monitor is configured and `NMIER` is never written. The `R_MPU_SPMON` register block
exists in the device headers, but FSP does not use it on these devices.

**Consequence: no disarm was added, because there is nothing to disarm.** Writing
`R_MPU_SPMON->SP[0].CTL = 0` would be dead code implying a hazard the silicon does not present.

**Net position:** on these four parts no asynchronous unmaskable source is armed during the handover,
so PRIMASK covers everything that can actually fire. The residual exposure is HardFault, which is
synchronous — it only occurs if the code is already wrong — and `Default_Handler`'s `while(1)` is a
defensible response to a fault in a window with no working stack.

### Portability note — this becomes real on a part with the monitor

Keep the mechanism on record. On an RA device where `BSP_FEATURE_BSP_HAS_SP_MON` is 1, BL2 **would**
arm an NMI on its own stack window and jump with it live, and `NMIER` could not be cleared. The
secure image only disarms at `system.c:329`, after its `Reset_Handler` has already pushed via
`bl SystemInit` at an MSP outside the monitored range. For reference, the two windows on RA6M5 are
disjoint and would have qualified:

```
BL2 stack     0x200034C0 - 0x20004CC0   (and erased before the jump)
secure stack  0x20000760 - 0x20001760   initial MSP 0x20001760
```

The hook to disarm in would be `boot_platform_post_load()` — a weak upstream no-op, called per image
after verification and before `do_boot()`, so it is the last port-owned point before the branch.
`boot_platform_post_init()` is too early: it would drop stack monitoring for the whole of image
verification.

---

## D065 — the flat-binary brick guard is now on all four ports, and a stale `.bin` is as lethal as a fresh one

**Date:** 2026-09-29 · **Status:** Accepted · Extends [D002], [D058]

**What was still exposed.** [D058] added the flat-binary strip and `check_ofs.py --check-flat-bin`
to **RA8M2 only**. RA6M5, RA6E1 and RA6M4 kept the ELF-level guard alone, which structurally
cannot see this failure. Measured on the RA6M5 regression build, 2026-09-28:

```
bl2.elf   three discrete 4-byte OFS PT_LOADs at 0x0100A100/0x0100A200/0x0100A280   -> guard PASSes
bl2.bin   16,818,820 bytes spanning 0x00000000-0x0100A284 for 26,912 bytes of content
```

The zero fill covers **PBPS at `0x0100A1E0`** — the one-time Permanent Block Protect word, the
exact word that destroyed two EK-RA6M4 boards on 2026-07-21. A correct ELF, a passing guard, and
a lethal artifact in the same `bin/` directory.

**Fix.** `<port>_strip_ofs_from_bin()` plus `--require-segments --check-flat-bin` in ra6m5, ra6e1
and ra6m4, matching ra8m2. `<port>_add_ofs_check()` now forwards `${ARGN}`. Verified: RA6M5
`bl2.bin` 16,818,820 -> **26,904** bytes, guard reporting `flat .bin OK ... OFS sections stripped`.

`--require-segments` is now on for every BL2. A CLEAN result there was previously a pass; it is
the signature of dropped sections or a wrong region window, which is how the guard was silently
inert on RA8M2 until [D056].

**A stale artifact is a live hazard.** Eleven oversized `.bin` files were sitting in build
directories that predated the fix — six RA6M5 at 16.8 MB, five RA8M2 at 13.2 MB, in `bin/`,
`build-spe/bin/` and `api_ns/bin/`. Nothing in the repo flashes a `.bin`, and no launch
configuration references one, but they are indistinguishable from a safe one except by size.
All deleted. **Over ~1 MB means it spans the option memory** — that is the only tell, and it is
now the stated check in DESIGN.md 8.4 and the MACHINE_HANDOFF pre-flash list. The "never
`bl2.bin`" rule stands even though current builds emit a safe one: a hand-run `objcopy`, an older
build dir, or an unguarded toolchain path all still produce the brick.

**Not a build-dir problem.** `m5rs/bin/` is an orphan from an earlier layout; the live outputs are
`m5rs/build-spe/bin/` and `m5rs/api_ns/bin/`. Auditing by the path one expects would have missed
two of the three copies.

---

## D066 — RA8M2's partition comments described RA6M5, including the values that get provisioned

**Date:** 2026-09-29 · **Status:** Accepted · Extends [D056], [D057]

**The dangerous one.** `ra8m2/region_defs.h` carried a **verbatim copy** of
`ra6m5/region_defs.h`'s NSC paragraph: window `0x800 at 0x11F800`, boundary `0x120000`, and
"the Partition Manager takes the SECURE size in KB (1150) and the NSC size in KB (2)". Every
number is RA6M5's. RA8M2's window is `0x400 at 0x020AFC00`, boundary `0x020B0000`.

Those KB values are **what gets provisioned**, and on this part provisioning is not reversible:
`BSP_FEATURE_TZ_HAS_DLM` is 1, so FSP's runtime PSCU monitor writes are compiled out and the
partition is a non-volatile device property written once by RDPM. Corrected, with both parts'
real figures stated and the copy-from-RA6M5 called out so it cannot be re-derived:

| | code flash | SRAM |
|---|---|---|
| RA8M2 | secure 703 KB + NSC 1 KB (`0xB0000`) | secure 935 KB + NSC 1 KB (`0xEA000`) |
| RA6M5 | secure 1150 KB + NSC 2 KB (`0x120000`) | — |

NSC is counted separately from secure; RA6M5's own 1150 + 2 = 1152 KB = `0x120000` confirms it.

**Three more, all in `flash_layout.h`, all from the pre-2026-09-24 partitioning:** the secure
slot addresses (claimed primary `0x12000` / secondary `0x61000` / `0x4F000` each; actually
secondary `0x20000`, primary `0x68000`, `0x48000` each — and the **secondary is the lower slot**
on this part); the 1024 K tally (`8 K DF_EMULATION + 2 x 316 K secure`; actually `64 K + 2 x 288
K` — both total 1024 K exactly, so it read as plausible); and DF_EMULATION described as `0x2000`
two sentences before the same block correctly derives 31,744 B of PS and ITS from `0x10000`.

**The code was never wrong.** `flash_layout.h` derives everything from `BSP_PARTITION_*`, and
`ra8m2_layout_checks.c` `_Static_assert`s contiguity, no-overlap and whole-sector sizing —
`DF_EMULATION % 0x8000 == 0` would have failed outright at `0x2000`. Only the prose drifted,
which is the failure mode a generated-and-asserted layout leaves open.

**Rule.** A comment that states a number a human will type into a provisioning tool is not a
comment. Seeding a port by copying another part's files puts those numbers in the new file
already wrong, and nothing in the build checks them.

---

## D067 — first full tf-m-tests regression pass on hardware, and two suites that report PASSED without testing

**Date:** 2026-09-29 · **Status:** Accepted · Closes the open item from [D062], validates [D063]

**Result.** RA6M5 (CK-RA6M5 v2), GCC, `MinSizeRel`, SFN backend, isolation 1, SCE9, dummy
provisioning. Launch config `ra6m5_TFM_regression_gcc`, images from `C:\b\m5rs` and `C:\b\m5rn`.
**14 suites, zero failures.**

| Secure | Tests | Non-secure | Tests |
|---|---|---|---|
| PS interface (1XXX) | 20 | SFN backend (1XXX) | 5 |
| PS reliability (2XXX) | 2 | PS interface (1XXX) | 20 |
| PS rollback protection (3XXX) | 9 | ITS interface (1XXX) | 24 |
| ITS interface (1XXX) | 22 | Crypto (1XXX) | 39 |
| ITS reliability (2XXX) | 2 | Platform | 1 |
| Crypto (1XXX) | 38 | Attestation | 2 |
| Attestation | 2 | | |
| Platform | 1 | | |

**What this validates beyond the services themselves:**

- **[D063]'s veneer MEMORY region, on real silicon.** The NS suites only run if every NS->S call
  resolves through `.gnu.sgstubs` at `0x11F800`, and `TFM_NS_SFN_TEST_1003/1004` exercise both
  connection-based and stateless RoT services. The fix is not merely link-clean.
- **[D065]'s flat-binary strip did not damage the image.** This is the same build that emits the
  26,904-byte `bl2.bin`; it boots and runs.
- **The data flash is genuinely working, not stubbed.** `TFM_S_PS_TEST_3001..3009` drive the NV
  counters through nine rollback scenarios, including "NV counter 1 cannot be incremented".
- **PS and ITS reliability**, 15 iterations each of set/get and set/get/remove, on both sides.

**TWO TESTS REPORT PASSED WITHOUT TESTING ANYTHING. Do not read them as coverage.**

1. **`TFM_S_CRYPTO_TEST_1056` / `TFM_NS_CRYPTO_TEST_1056` (ECDSA-SECP384R1-SHA384)** log
   "P384 is unsupported. Skipping..." and set `ret->val = 0`. The gate is

   ```c
   #if defined(PSA_WANT_ECC_SECP_R1_384) && defined(CC3XX_RUNTIME_ENABLED)
   ```

   `CC3XX_RUNTIME_ENABLED` is **Arm's CryptoCell driver**. The test self-skips on every platform
   that is not CC3xx, so the message is about the test, not about this port.
   `PSA_WANT_ECC_SECP_R1_384` is **not** disabled in `sce9/crypto_accelerator_config.h` - only
   `SECP_R1_521` and `MONTGOMERY_255` are, per [D059]. **P-384 is therefore untested here, and
   probably works.** It needs a standalone check before anyone claims P-384 support from this log.

2. **`TFM_S_CRYPTO_TEST_1045` / `TFM_NS_CRYPTO_TEST_1044` (DETERMINISTIC_ECDSA-SECP256R1)** log
   "Algorithm NOT SUPPORTED by the implementation for signing, continue to verification". This one
   is **intended**: `sce9/crypto_accelerator_config.h:34` has `#undef
   PSA_WANT_ALG_DETERMINISTIC_ECDSA`, because SCE9 has no RFC 6979 path and the attestation key
   signs with plain `PSA_ALG_ECDSA`. Verification did run. Legitimate partial pass.

So the honest statement is **twelve suites fully exercised, plus crypto on both sides carrying one
upstream self-skip and one deliberate config gap** - not "14/14 means everything is covered".

**Corroborating detail worth keeping:** the secure and non-secure ECDSA-P256 signatures over the
identical hash `8d2da584...` differ (`d0270eef...` vs `a288908b...`), which is the correct result
for non-deterministic ECDSA and shows the RNG is live on both paths rather than returning a
constant.

---

## D068 — the FLIH/SLIH fixture, and two silent defects the IAR build found in D065

**Date:** 2026-09-30 · **Status:** Accepted · Closes the TODO in [D062], fixes [D065]

### The interrupt fixture

[D062] left a four-item TODO in `ra6m5/tests/tfm_tests_config.cmake` and
`PLATFORM_{FLIH,SLIH}_IRQ_TEST_SUPPORT` unset. All four are now done, on RA6M5:

| | |
|---|---|
| `plat_test.c` | AGT0 start / stop / underflow-ack, direct registers |
| `tfm_timer0_irq.c` | `TFM_TIMER0_IRQ_Handler` + `tfm_timer0_irq_init()` |
| `tfm_peripherals_def.{h,c}` | `TFM_PERIPHERAL_TIMER0` (0x400E8000-0x400E80FF), `TFM_TIMER0_IRQ` |
| `startup_ra6m5.c` | `__VECTOR_TABLE[16] = TFM_TIMER0_IRQ_Handler` |

**TF-M owns the vector, and there is no conflict to manage.** The secure image uses its own
`__VECTOR_TABLE`, not FSP's generated `g_vector_table` - that array is still linked, but only
so `bsp_irq_cfg()` can read `g_interrupt_event_link_select[]` beside it and program IELSR,
ITNS and ICUSARG before `main()`. So the RA half of the wiring is entirely configurator-driven,
exactly as [D061] described, and the port only supplies the one vector slot.

Verified in the shipped image rather than assumed - at `0xa0240`, slot 16:

```
a0238  d1520b00 d1520b00 49610b00 d1520b00
                         ^^^^^^^^ 0x000b6149 = TFM_TIMER0_IRQ_Handler | thumb
       neighbours       = 0x000b52d1 = Default_Handler
```

**`ext/common/tfm_interrupts.c` still cannot be used**, which is why `tfm_timer0_irq.c` exists.
That file is otherwise exactly right, but its init calls `NVIC_ClearTargetState()`, which is
plain CMSIS and knows only `NVIC->ITNS` - on RA that leaves ITNS saying non-secure while
`R_CPSCU->ICUSARG` still says secure. Nothing needs to replace it: the interrupt is already
secure because the SECURE project configured the AGT.

**Design notes worth keeping:**

- `plat_test.c` does **not** use `R_AGT_*`. `R_AGT_Open()` installs an FSP callback and expects
  `agt_int_isr()` at the vector, which TF-M has taken, so its IRQ plumbing would be dead
  weight; and tracking whether `g_timer0_ctrl` is open, from code the SPM calls in interrupt
  context, is more state than three register writes deserve.
- `AGTCR` is written as a **whole byte** in `_start()` (flags clear by writing 0, so a
  read-modify-write would preserve a set flag) and as a **read-modify-write** in
  `_clear_intr()` (the timer is running, so `TSTART` must survive). Both are deliberate.
- `TFM_TIMER0_IRQ` is a literal in the header because that header is included where
  `vector_data.h` is not. `plat_test.c` includes both and `_Static_assert`s they agree, so a
  RASC renumbering fails the build instead of routing the interrupt to `Default_Handler`.
  **`#if` does not work here** - both macros expand to `((IRQn_Type) n)` and a cast is not a
  valid preprocessor constant expression; the `#if` form fails to parse rather than comparing.
- **FLIH and SLIH are mutually exclusive.** Both claim TIMER0, so tf-m-tests enables one:
  this build got `TEST_NS_FLIH_IRQ ON`, `TEST_NS_SLIH_IRQ OFF`.

### Two silent defects in [D065], both found by building it under IAR

**1. The tool fallback never worked.** `CMAKE_OBJCOPY` is empty under IAR, and the guard's
long-standing idiom did not save it:

```cmake
set(VAR "${CMAKE_OBJCOPY}")     # creates an empty NORMAL variable
if(NOT VAR)
    find_program(VAR ...)       # writes the CACHE - which the normal variable SHADOWS
endif()
```

The cache proved it: no `OFS_OBJCOPY` **or** `OFS_READELF` entry existed. So the
**pre-existing readelf fallback has been dead under IAR since it was written** - inherited,
not introduced by D065, but copied into three more ports by it. Fixed with `unset(VAR)` before
the `find_program`.

**2. `--remove-section` on a name pattern is the wrong mechanism.** GCC emits
`.option_setting_ofs0` / `_ofs1_sec` / `_ofs1_sel`. **IAR's ILINK emits `P1`, `P7`, `P11`** -
positional names taken from the `.icf` block order. So `--remove-section=.option_setting*`
matched nothing, objcopy copied everything, and the strip **reported success while emitting
the full 16,818,820-byte brick**. Only `--check-flat-bin` caught it. Those names also move
whenever the `.icf` block order changes, so hardcoding them would be no better.

**Fix: `check_ofs.py --emit-safe-bin`.** The flat image is now written from the ELF's program
headers, excluding load segments by **address** - the same basis `--region` already gives the
check. No objcopy on either toolchain, and the `find_program`/`FATAL_ERROR` blocks are gone
again. Results: IAR 26,561 bytes, GCC 26,904 bytes, guard passing on both.

**The lesson is the same one [D058] taught and this missed:** a strip that cannot fail loudly
is not a safety measure. The name-based version had no way to report "I matched nothing", and
it took a second toolchain to expose that. Address-based emission cannot silently no-op,
because there is no name to fail to match.

### State

RA6M5 IAR: SPE and NS both build, FLIH suite linked (`irq_test_flih_case_1/2` in `tfm_ns.axf`),
`ra6m5_TFM_regression_iar` launch config generated. **Not yet run on hardware.**
RTT: `tfm_s` `0x2000A8A4`, `tfm_ns` `0x20043338`, bl2 none (`MCUBOOT_LOG_LEVEL=OFF`).

GCC projects are equally ready - `VECTOR_DATA_IRQ_COUNT 1`, same ICU slot 0 - but the GCC
FLIH build has not been attempted.

**Second occurrence, belongs in the build docs:** `cmake --install <spe>/build-spe` is NOT
enough for a regression NS build. `attest_token.h` is installed by the OUTER wrapper
(`cmake --install <spe>`), and without it four attestation translation units fail `Pe1696`.
The GCC leg hit this too.

---

## D069 — a weak symbol in a static library silently unrouted every secure interrupt

**Date:** 2026-09-30 · **Status:** Accepted · Completes [D068], extends [D061]

**Result first.** RA6M5 IAR, SFN, isolation 1: `TFM_NS_IRQ_TEST_FLIH_1101` and `_1102`
**PASS on hardware** - 7 non-secure suites and 8 secure, zero failures. First working
secure interrupt on this port.

### The bug was not in the timer

The FLIH test hung in its `while (flih_timer_triggered < 10)` loop. Two rounds of work on
the AGT register sequence changed nothing, because the interrupt was never routed at all:

```
g_interrupt_event_link_select[0] = 0x0000      symbol binding: V (weak)
```

`ra_gen/vector_data.c` holds the STRONG definition of that array - the table
`bsp_irq_cfg()` reads to program `R_ICU->IELSR` and the ITNS/ICUSARG attribution.
`bsp_irq.c:44` holds a `BSP_WEAK_REFERENCE` all-zero fallback of the same array. **Both are
members of `libfsp_bsp_s.a`.**

The linker extracts `bsp_irq.o` because something calls `bsp_irq_cfg()`. Its weak
definition then satisfies the reference, so the member holding the real table is never
extracted - **nothing else refers to it**, because the secure image uses TF-M's own
`__VECTOR_TABLE` instead of FSP's `g_vector_table`. The weak zeros win.

`bsp_irq_cfg()` guards both of its writes on a non-zero entry, so with the zeros:

- `R_ICU->IELSR[0]` is never programmed, and on RA the peripheral event reaches the NVIC
  only through IELSR - so the AGT underflow went nowhere
- the "this is a secure vector" branch never runs, leaving `ITNS[0]` and `ICUSARG` bit 0 at
  1, i.e. **non-secure**

Two failures from one cause, both silent, neither reachable by any amount of timer work.
`R_AGT_Open()` would not have helped either: `R_BSP_IrqCfg()` sets only NVIC priority and
ISR context, never IELSR.

**Fix.** A named anchor in `target_cfg.c` referencing `g_vector_table`, the one symbol only
`vector_data.c` defines, which forces the member out of the archive. Now `T` (strong) and
`[0] = 0x0040` = `ELC_EVENT_AGT0_INT`.

**Two dead ends, recorded so they are not retried.** Moving `vector_data.c` into
`platform_s` does nothing - that is a static library too, so the object is still an archive
member. And `list(REMOVE_ITEM _src ...)` against the glob silently did not match, leaving
two copies compiled.

### The second gap, which the first fix exposed

Pulling in `g_vector_table` drags a reference to `agt_int_isr`, and the link failed
`Error[Li005]: no definition`. **FSP's AGT driver was never compiled** - there was no
`fsp_agt.cmake`, so `R_AGT_Open()` had never been available to call. That is the real
reason the first version of `plat_test.c` poked registers directly; the justification
written into its header was a rationalisation after the fact.

Added `cmake/modules/fsp_agt.cmake` and rewrote `plat_test.c` around
`R_AGT_Open`/`R_AGT_Start`/`R_AGT_Stop` on the generated `g_timer0`. `agt_int_isr()` is now
linked and never called - TF-M owns the vector - which is the acceptable cost of keeping
the generated event-link table authoritative rather than transcribing IELSR values into the
port.

**What the driver still does not do, so `plat_test.c` must:** clear the ICU latch.
`R_ICU->IELSR[n].IR` holds the request until cleared, and FSP does it at the top of every
ISR via `R_BSP_IrqStatusClear()` - including in `agt_int_isr()`, which this port replaces.
Without it the interrupt fires exactly once.

### The part worth remembering

**The port had been printing the diagnosis in every single build:**

```
RA6M5 [s]: FSP module 'r_agt' is in the project but no module declares it,
           so it is NOT in the image.
```

That warning was added for exactly this failure mode and it worked. I read past it through
two failed hardware runs and two rewrites of the timer code. A warning nobody reads is
worth nothing; the cost here was measured in hardware cycles, not minutes.

The general hazard is broader than FSP: **a weak definition in an already-extracted object
silences the strong one in an un-extracted archive member, with no diagnostic from any
tool.** Nothing in the build, the map file, or the guard suite can see it. The only tell was
reading the symbol binding (`V` vs `T`) and the array's actual contents out of the linked
image - which is now the first thing to check whenever a configured RA interrupt does not
arrive.

---

## D070 — FLIH verified on both toolchains; the fixture is portable, and RTT addresses are per-build

**Date:** 2026-09-30 · **Status:** Accepted · Confirms [D068], [D069]

**Hardware results.** RA6M5, SFN, isolation 1, `TFM_NS_IRQ_TEST_FLIH_1101` and `_1102`:

| Build | Suites | Result |
|---|---|---|
| RA6M5 **IAR** FLIH | 8 secure + 7 non-secure | **PASS**, zero failures |
| RA6M5 **GCC** FLIH | 8 secure + 7 non-secure | **PASS**, zero failures |

Both on `TF-M v2.2.0+ca55cf5c1`. The [D069] fix is therefore not toolchain-specific: the
weak-symbol extraction failure and the ICU latch were real on both, and the one anchor plus
one `R_BSP_IrqStatusClear()` fixes both.

**Built but NOT yet run on hardware:** RA6M5 IAR SLIH, RA6M5 GCC SLIH, RA8M2 GCC FLIH,
RA8M2 GCC SLIH.

**The RA8M2 fixture needed almost nothing beyond the RA6M5 one.** `plat_test.c`,
`tfm_timer0_irq.c` and `fsp_agt.cmake` port verbatim because `plat_test.c` reaches the
timer through `R_AGT0` and `g_timer0`, never an address. Only two things differ, and both
are data rather than code:

- `TFM_PERIPHERAL_TIMER0` is AGT0 at **0x40221000**, not RA6M5's 0x400E8000. The device
  header defines it as `0x40221000UL + BASE_NS_OFFSET`, and that offset is 0 for a secure
  build - this part aliases peripherals the way it aliases memory.
- The ICU event number is **0x0086**, against RA6M5's 0x0040. Both come from the generated
  table, so neither is written into the port.

Using the FSP driver rather than raw registers is what made that portability free. A
hand-rolled register sequence would have had to be re-verified per part.

### RTT control-block addresses are PER BUILD, and a wrong one is silent

The first GCC run "printed nothing" on both channels, because it was given the IAR build's
addresses. Same source, same part, different toolchain:

```
RA6M5 IAR FLIH   tfm_s 0x2000A8A4   tfm_ns 0x20043338
RA6M5 GCC FLIH   tfm_s 0x2000ABC0   tfm_ns 0x200434A4
```

Nothing in the e2 launch configuration carries the RTT address - it is a J-Link viewer
setting - so a stale or cross-toolchain address presents as a dead console, not an error,
and looks exactly like a hung target. The six current addresses and the `arm-none-eabi-nm`
command to re-read them are now in the MACHINE_HANDOFF pre-flash checklist, which already
warned they move on every relink but did not say they also differ between toolchains.

**Corollary worth stating:** every "prints nothing" during this work - including the one
that sent me looking at the AGT for a second time - should have been checked against the
address before anything else. Two of the three were the address, not the firmware.

---

## D071 — SLIH passes too; both FF-M handling models work, with one fixture

**Date:** 2026-09-30 · **Status:** Accepted · Completes the arc from [D061] to [D070]

**Result.** RA6M5 GCC, SFN, isolation 1, `TF-M v2.2.0+ca55cf5c1`:
`TFM_NS_IRQ_TEST_SLIH_1001` **PASSES**, alongside all 8 secure and the other 6 non-secure
suites. Zero failures.

| Build | FLIH | SLIH |
|---|---|---|
| RA6M5 IAR | **PASS** | built, not run |
| RA6M5 GCC | **PASS** | **PASS** |
| RA8M2 GCC | built, not run | built, not run |

**The fixture is handling-model agnostic, and that was not guaranteed.** SLIH required NO
port change: the same `plat_test.c` and `tfm_timer0_irq.c` serve both, and only the test
partition and the two `TEST_NS_*_IRQ` switches differ. The two models are quite different
at the SPM - FLIH runs the handler in the exception context and may return a signal, SLIH
defers the work to the partition thread - so a port could plausibly have needed separate
handling. It did not, because the port's half of the contract is only: route the event,
clear the ICU latch, start and stop the timer. Everything model-specific lives above that
line, in `spm_handle_interrupt()`.

That also means [D069]'s two fixes - the vector-table anchor and the
`R_BSP_IrqStatusClear()` - were the complete set. Nothing further was needed for the second
model.

**Asymmetry worth knowing:** the SLIH suite has ONE case (`SLIH_1001`), FLIH has two
(`FLIH_1101`, `FLIH_1102`, the latter exercising the signal-returning path). So FLIH is the
stronger test of the two despite both now passing, and the FLIH pass on both toolchains is
the more load-bearing result.

**Still unrun:** RA6M5 IAR SLIH, and both RA8M2 builds. The RA8M2 pair also has no e2 launch
configuration - the generator is RA6M5-specific and RA8M2's slots are at 0x68000 (secure
primary) and 0xB0000 (non-secure primary), not 0xA0000/0x120000.

---

## D072 — RA6M5 interrupt matrix complete; and an RTT capture can truncate silently

**Date:** 2026-10-01 · **Status:** Accepted · Closes [D071]

**The matrix is full.** RA6M5, SFN, isolation 1, `TF-M v2.2.0+ca55cf5c1`, 15 suites each,
zero failures:

| | FLIH | SLIH |
|---|---|---|
| RA6M5 **IAR** | **PASS** | **PASS** |
| RA6M5 **GCC** | **PASS** | **PASS** |
| RA8M2 GCC | built, not run | built, not run |

Two toolchains x two FF-M handling models, on one fixture, with no per-combination code.
[D069]'s two fixes and [D068]'s fixture are complete and portable across both axes.

### The first IAR SLIH run looked like a hang and was not

Its non-secure log stopped mid-suite, after `TFM_NS_ITS_TEST_1002 - PASSED!`, with no
summary. A re-run of the same binaries completed normally, so the target was fine and the
RTT capture was short.

**The tell, which is worth reusing:** the output ended immediately after a PASSING test and
there was no `> Executing` / `Description:` line for the next one. A target that hangs
inside a test prints that test's header first - the test framework emits it before the body
runs. So:

- output stops **after** a result line, next test never announced -> suspect the CAPTURE
- output stops **after** a `Description:` line -> suspect the TARGET, and the named test is
  where to look

The non-secure RTT up-buffer is 4 KB against roughly 15 KB of log, so a viewer that
attaches late or stops draining loses the tail with no error anywhere. Re-run before
investigating.

**What was NOT done, deliberately:** nothing was changed and no pass was recorded on the
strength of the first run. The build was compared against the IAR FLIH one that had
completed - byte-identical NS image, 116 bytes apart in secure text, same configuration -
which established there was no build-level reason for ITS to differ, and that is what made
"re-run it" the right next step rather than a code change.


---

## D073 — one MRAM alias is not enough: the RA8M2 flash driver must pick it per offset

**Date:** 2026-10-01 · **Status:** Accepted

**Symptom.** First ever boot of BL2 on RA8M2 hardware, immediately after programming the
TrustZone boundaries with RDPM: HardFault inside `memcpy()`, called from
`ARM_Flash_ReadData()` <- `flash_area_read()` <- `boot_read_image_header()` <-
`boot_read_image_headers()` <- `boot_prepare_image_for_update()`.

**Cause.** `Driver_Flash.c` formed every MRAM address as `FLASH_BASE_ADDRESS + offset`, one
fixed secure base for all four MCUboot areas. On RA8M2 `BSP_FEATURE_TZ_NS_OFFSET` is
`0x10000000`: MRAM answers at `0x02000000` secure and `0x12000000` non-secure, and **which
alias reaches a given byte is decided by the RDPM boundary** - below it the secure alias
only, at or above it the non-secure alias only. The programmer writes the NS image at
`0x120B0000`; BL2 read it back at `0x020B0000`, an alias that does not answer there.

The fault address is the proof, not an inference: BL2 read the secure primary slot at
`0x02068000` without trouble and faulted on the first access at or above `0x0B0000`, which
is exactly the Code Secure boundary (704 KB) programmed minutes earlier.

**Why it survived every build and every static check.** It needs a *partitioned* part to
appear. On a virgin device the whole of MRAM is secure, the secure alias reaches all four
areas, and the bug is invisible. RA8M2 had never been through RDPM before, so BL2 had never
run on it.

**Why the code was written that way.** It was derived from the RA6M5 driver, where
`BSP_FEATURE_TZ_NS_OFFSET` is 0 and there genuinely is one alias. The RA8M2 header even
recorded the mistake as a design note - "Both aliases give the same physical offset, which
is what makes one Driver_FLASH0 able to serve all four slots." That is true of *offsets* and
false of *addresses*, and the sentence read as a reason not to look further. Both that
sentence and the "not a fault, it is a wild access" note have been corrected in place.

**Fix.** `MRAM_ADDR()` chooses the alias from the offset, thresholded on
`FLASH_AREA_1_OFFSET` - the NS primary slot header, the lowest non-secure offset, derived
from `BSP_PARTITION___BL_1_P_H_START` so a repartition in e2 moves it with it:

```c
#define MRAM_ADDR(off)                                                   \
    ((uint32_t)(off) +                                                   \
     ((uint32_t)(off) >= (uint32_t)(FLASH_AREA_1_OFFSET)                 \
      ? (uint32_t)(FLASH_NS_ALIAS_BASE)                                  \
      : (uint32_t)(FLASH_BASE_ADDRESS)))
```

Covers read, program and erase, which all go through the macro. Safe for the write path:
`R_MRAM_Write()` and `R_MRAM_Erase()` mask the address with `~BSP_FEATURE_TZ_NS_OFFSET`
before range-checking (`r_mram.c:335, 374`) and pass the unmasked address on, i.e. FSP
accepts either alias by design.

A single threshold is only sound while the secure areas all lie below it and the non-secure
ones all at or above it. `ra8m2_layout_checks.c` now asserts that for all four areas; the
pre-existing contiguity asserts (`FLASH_AREA_0 + size == FLASH_AREA_1_OFFSET`,
`FLASH_AREA_1 + size == FLASH_AREA_3_OFFSET`, `FLASH_AREA_3 + size == FLASH_TOTAL_SIZE`)
already pinned the ordering.

**Scope.** RA8M2 only. RA6M5, RA6E1 and RA6M4 have `BSP_FEATURE_TZ_NS_OFFSET = 0`, one
alias, and their drivers are correct as written. The `PLATFORM_HAS_BOOT_DMA` path in
`bl2/src/flash_map.c:147` forms the same fixed-base address and would need the same
treatment - it is OFF on this port and was not touched.

**Rebuilt and statically verified**, all four RA8M2 GCC images. The compiled read path is
now `cmp.w r4, #0xb0000 / ite cc / movcc.w r1, #0x2000000 / movcs.w r1, #0x12000000`. Slot
occupancy unchanged - `tfm_s_signed.bin` 294,912 B and `tfm_ns_signed.bin` 163,840 B, both
exact fits; `bl2.bin` 27,552 -> 27,584 B. RTT addresses unchanged. **Not yet run on
hardware.**

**RDPM values for this layout**, recorded here because no `RA8M2_SOLUTION.md` exists yet and
the RA6M5 table does not transfer: Code Secure **703**, Code NSC **1**, Data Secure **0**,
SRAM Secure **935**, SRAM NSC **1**, SiP Flash Secure **0**, all KB. Code 703+1 = 704 KB =
22 x 32 KB; SRAM 935+1 = 936 KB = 117 x 8 KB. Data Secure is 0 because the part has no data
flash at all - ITS/PS live in the 64 KB `DF_EMULATION` region inside MRAM.

**The IAR solution still disagrees and is now a provisioning hazard, not just a build note.**
`ra8m2_iar_CPU0_secure` still has `RAM_CPU0_C` at `0x220E9F80` size `0x80`; the GCC set has
it at `0x220E9C00` size `0x400`. RDPM cannot express 128 B, so the six values above are the
GCC set. A board programmed with them puts an IAR-built secure image's NSC veneers inside
secure SRAM, and the first NS->S veneer call faults. Regenerate the IAR secure project with
the GCC RAM split before building that leg - needs RASC, not the IAR licence.

**Two wrong diagnoses preceded this one, both from reasoning instead of reading the
disassembly.** First `setTZBoundaries=true` in the new launch configuration - a real defect,
it must be `false` per DESIGN.md 7.2, and it is not what caused this. Then blank-MRAM ECC on
the never-programmed secondary slots - plausible, since RA8M2 code MRAM has an ECC decoder
and the launch erases all ROM, but wrong. What settled it was the user pointing at the
faulting address and one `objdump -d` of `ARM_Flash_ReadData`, which took under a minute and
should have been the first move. The `0xFF` filler images left in `C:\b\m2fill\` are from
the discarded ECC theory and are not needed.


---

## D074 — where MRAM_ADDR's two constants come from; refines [D073]

**Date:** 2026-10-01 · **Status:** Accepted · Refines [D073], which described the threshold
as `FLASH_AREA_1_OFFSET`

**Raised by the rm_psa_crypto owner:** why not use `BSP_FEATURE_TZ_NS_OFFSET`, which is fixed
per device family, instead of `FLASH_AREA_1_OFFSET`, which moves if the slots move?

**They are not interchangeable.** `MRAM_ADDR()` needs two different things:

| | What it is | Where it comes from | Moves? |
|---|---|---|---|
| **delta** | distance between the aliases, `0x10000000` | `BSP_FEATURE_TZ_NS_OFFSET` | no - family property |
| **boundary** | where secure MRAM ends | this device's partitioning | **yes, and it must** |

`BSP_FEATURE_TZ_NS_OFFSET` answers "how far apart are the aliases", never "is offset
`0xB0000` secure". The boundary is whatever RDPM programmed into `CFSAMONA`; a family-fixed
constant there would be wrong by construction, and the threshold tracking the layout is the
requirement, not a hazard.

**Taken anyway, for the delta.** The driver now derives the non-secure base as
`FLASH_BASE_ADDRESS + BSP_FEATURE_TZ_NS_OFFSET` rather than using `FLASH_NS_ALIAS_BASE`.
That literal stays in `flash_layout.h` only because the header is preprocessed into
`ra8m2_bl2.ld` and cannot reach `bsp_feature.h`; `ra8m2_layout_checks.c` now asserts the two
agree, so it cannot drift from FSP's value.

**And the boundary's source changed too**, for the reason behind the question.
`FLASH_AREA_1_OFFSET` gives the right number but names the wrong thing - it is where the
first non-secure *slot* starts, which coincides with the security boundary only while nobody
reorders the areas. The boundary is now the end of the NSC region
(`TFM_MRAM_S_OFF(BSP_PARTITION_FLASH_CPU0_C_START) + BSP_PARTITION_FLASH_CPU0_C_SIZE`),
which is the boundary by definition on this part: RDPM can only express a contiguous
Secure|NSC|NS triple, so the NSC is always the last secure thing. Already asserted equal to
`FLASH_AREA_1_OFFSET`.

**No functional change.** All four RA8M2 GCC images rebuilt; the generated code is identical
- `cmp.w r4, #0xb0000 / ite cc / movcc.w r1, #0x2000000 / movcs.w r1, #0x12000000` - and
every image size is unchanged. The value is that both constants now come from their
authoritative source and a wrong one fails the build instead of the board.


---

## D075 — BL2 must enable the SAU on RA8M2; the right alias is not enough

**Date:** 2026-10-01 · **Status:** Accepted · Completes [D073]/[D074], which were necessary
but not sufficient

**Symptom after [D073].** With `MRAM_ADDR()` fixed and verified in the disassembly, BL2
still HardFaulted at the same instruction. Register state at the fault, from the target:

```
r4 0x000b0000   offset                  r0 0x22002bac   dst
r1 0x120b0000   src - the NS alias      r2 0x120b0020   src end, 32 bytes
```

The address was now right. `ldrb.w r4, [r1], #1` still faulted. **Both aliases fault**, and
no partitioning makes that true, so the address was never the whole story.

**Cause.** The access was right; its *security attribute* was not. With the SAU disabled and
`SAU_CTRL.ALLNS` clear, Armv8-M attributes every address as Secure, and the combined
SAU/IDAU attribute takes the more secure of the two. BL2's load from `0x120B0000` therefore
went out as a **secure transaction to the non-secure alias** and was refused. The secure
alias was refused on the address, the non-secure one on the attribute - hence both.

**Why BL2 has no SAU.** FSP enables it in `R_BSP_SAUInit()`, reached from `SystemInit()` via
`R_BSP_SecurityInit()`, and that call sits inside `#if BSP_TZ_SECURE_BUILD`. BL2 is built as
the **flat** FSP role, deliberately (`fsp_bsp.cmake:56`), so it gets neither. The evidence is
one command:

```
arm-none-eabi-nm tfm_s.axf | grep SAU   ->  020a0b3c T R_BSP_SAUInit
arm-none-eabi-nm bl2.elf   | grep SAU   ->  (nothing)
```

Same root as [D073]: RA6M5 has `__SAUREGION_PRESENT = 0` - no SAU on the part at all - and
this port's BL2 came from it.

**Fix.** `bl2_boot_hal.c` enables **one** SAU region in `boot_platform_post_init()`, which
bl2_main.c calls before `boot_go_for_image_id()` reads the first header:

```c
SAU->RNR  = 0;
SAU->RBAR = 0x10000000U & SAU_RBAR_BADDR_Msk;          /* NS alias of code space */
SAU->RLAR = (0x1FFFFFFFU & SAU_RLAR_LADDR_Msk) | SAU_RLAR_ENABLE_Msk;
SAU->CTRL = SAU_CTRL_ENABLE_Msk;
__DSB(); __ISB();
```

One region, not FSP's five: BL2 has no veneers so neither NSC region applies, and MRAM is
the only non-secure alias it touches. Anything outside an enabled region stays Secure, which
is what it already was, so this changes exactly one thing. `tfm_s` installs the full set
moments later. The bounds are the IDAU's, restated from `BSP_PRV_SAU_NS_REGION_1_*` because
those are private to FSP's `bsp_security.c`; they are architectural for the part, not
layout-derived.

`bl2_boot_hal.c` is now built **unconditionally**. It was inside `if(CRYPTO_HW_ACCELERATOR)`
because its only previous job was the RSIP-E50D bring-up; that part moved behind a new
`RA8M2_BL2_SCE_INIT` compile definition. The weak default does nothing without
`CRYPTO_HW_ACCELERATOR`, so overriding it unconditionally loses nothing.

**Verified in the image**, all four RA8M2 GCC builds rebuilt:
`str.w r2,[r3,#0xd8]`=RNR 0, `#0xdc`=RBAR `0x10000000`, `#0xe0`=RLAR `0x1FFFFFE1`,
`#0xd0`=CTRL 1, then `dsb sy / isb sy`, then `ra_sce_init`. `bl2.bin` 27,584 -> 27,632 B.
Slot occupancy and RTT addresses unchanged. **Not yet run on hardware.**

**Still unconfirmed, and worth one read before the next attempt.** This diagnosis assumes the
RDPM boundary is currently programmed. If it is not, the non-secure alias has nothing behind
it and the fault will persist with the SAU correctly enabled. `CFSAMONA` at **0x40204030**
should read `0x000B0000` (CFS2 = 22, 704 KB). `0x00100000` means the part is wholly secure
and the boundaries were lost - most likely to a launch configuration still carrying
`setTZBoundaries = true`.

**Method note.** Three wrong diagnoses in this sequence, and the pattern in all three was
reasoning from the source rather than reading the target. What moved it each time was
hardware state: the backtrace, then the register dump. `objdump -d` on the faulting function
and the register file should be the first two steps on a HardFault, not the fourth.

---

## D076 — [D075] describes code that was reverted; BL2 still has no SAU

**Date:** 2026-10-01 · **Status:** Accepted · **Supersedes [D075]**

[D075] is marked Accepted and states that `bl2_boot_hal.c` enables an SAU region in
`boot_platform_post_init()`, with register writes, disassembly and a new `bl2.bin` size. That
change was reverted the same day (`299b03039`, reverted by `848f27180`) and **is not in the
tree**. A grep for `SAU->` across `platform/ext/target/renesas/` returns nothing.

**Why it was reverted.** The rm_psa_crypto owner pointed out that FSP's own MCUboot port
already does this, in `ra/fsp/src/rm_mcuboot_port/flash_map.c:214-226` - and does it better:
it derives the non-secure window at runtime from `R_PSCU->CFSAMONA_b.CFS2`, i.e. from what
RDPM actually programmed, rather than from a compile-time constant, and it tears the region
down again in `flash_on_chip_cleanup()` so the next image starts from a clean SAU. The port
excludes that whole module (`ra8m2/CMakeLists.txt:102`), which is why none of it is linked
and why the SAU gap existed at all.

**What stands from [D075].** The diagnosis, which the register dump confirms: with the SAU
disabled and `SAU_CTRL.ALLNS` clear, Armv8-M attributes every address Secure, so BL2's load
from `0x120B0000` goes out as a secure transaction to the non-secure alias and is refused.
Both aliases then fault - the secure one on the address, the non-secure one on the
attribute. **That fault is live again.** [D073] and [D074] remain correct and in the tree;
they were necessary and are not sufficient.

**Open.** How to get FSP's SAU programming into BL2 - adopt `rm_mcuboot_port/flash_map.c`,
fork it into the port, or replicate the mechanism in `Driver_Flash.c`. Blocker found while
scoping the first option: FSP's generated `flash_map[]` gives the secure primary slot
`.fa_size = BSP_PARTITION___BL_0_P_H_SIZE + BSP_PARTITION___BL_0_S_T_SIZE` = **0x200**,
omitting `FLASH_CPU0_S` (0x47A00) and `FLASH_CPU0_C` (0x400). The generator walks forward
from `___BL_0_P_H` and stops at `___BL_0_S_T` - the *secondary* trailer, size 0, which sits
at the same address `0x02068000` the primary header starts at. The other three entries are
correct. This is the defect `TFM_SLOT_SPAN` in `flash_layout.h` was written to work around,
and it regenerates on every e2 build.

**Also noted, not in [D074]:** the port's `MRAM_NS_BOUNDARY` is a compile-time value from
`BSP_PARTITION_FLASH_CPU0_C_START + _SIZE`; FSP reads `CFSAMONA` at runtime. These agree only
while the provisioned boundary matches the solution the build was configured from. A device
partitioned to a different profile picks the wrong alias and nothing at build time can see
it. [D074] argued the threshold question without considering the runtime option.

---

## D077 — FSP replication audit: one live defect, three fixes that never reached the RA6 ports

**Date:** 2026-10-01 · **Status:** Accepted

Audit of every place the port states, computes or implements something FSP already provides,
run against `ra8m2`, `ra6m5`, `ra6e1`, `common` and the two accelerator packs. The port's own
inventory in `DOCUMENTATION_PLAN.md:142-173` was accurate as far as it went; what follows is
what it did not cover. `PROJECT_PLAN.md:265` already carried "Audit the port for values that
override FSP-generated configuration" as an open task - this closes it.

**FIXED NOW - the one live defect.** `ra8m2/tfm_peripherals_def.c` had
`tfm_peripheral_std_uart` at **0x40118000**, which is RA6M5's SCI0. RA8M2's is **0x40358000**
(`R7KA8M2JF_core0.h:52985`), and 0x40118000 appears nowhere in that header. The file was
derived from `ra6m5/tfm_peripherals_def.c` and only the comment's part name was changed.
Latent at the shipping default - isolation 1, `RA8M2_STDOUT_RTT` - where no MPU region is
created from the entry; at isolation 2 or 3 `tfm_hal_bind_boundary()` maps a region over
addresses that decode to nothing and leaves the real SCI0 unmapped. The sibling AGT0 entry
(0x40221000) was checked against the device header when it was added and is correct. Fixed,
with both literals now cross-checked.

**STALE - ra8m2 fixes that were never back-ported.** Each of these is recorded in the log as
*resolved*, and the surviving RA6 instances are named nowhere:

| | ra8m2 has | ra6m5 / ra6e1 have | Recorded as fixed in |
|---|---|---|---|
| OFS addresses | generated from `Debug/memory_regions.*` into `option_settings.h` at configure time | 13 groups hand-transcribed in `region_defs.h` | [D056] |
| Enabled-but-unplaced OFS words | 22 `#error` guards, one per `BSP_CFG_OPTION_SETTING_*` | 0 guards, a "keep it in sync" comment | [D056] |
| `BSP_FEATURE_*` agreement | `_Static_assert` on `FLASH_NS_ALIAS_BASE` | "Confirm against `BSP_FEATURE_FLASH_HP_CF_REGION1_BLOCK_SIZE` if the device is ever changed" | [D074] pattern |

The first is the brick path. A regenerated RA6M5 bootloader project that moves an option word
leaves `ra6m5_bl2.ld` placing `.option_setting_pbps` at a stale address, and that is silent:
the linker is content, the srec is clean, and `check_ofs.py --ra6-default` validates against a
hardcoded RA6 window that still contains the stale address, so it prints CLEAN. PBPS is the
one-time Permanent Block Protect word that killed two EK-RA6M4 boards ([D002]).

**NEW - comments that assert guards which do not exist.**

- `ra8m2/flash_layout.h:131` says `ra8m2_layout_checks.c` asserts that
  `FLASH_AREA_IMAGE_SECTOR_SIZE` "still agrees with FSP's header". It does not - that file
  has exactly one FSP-value assertion, on `FLASH_NS_ALIAS_BASE`. So the literal the log
  singles out as the archetypal drift case ([D054]: slots 9.875 sectors long, `BOOT_EFLASH`
  on hardware only) carries a claim of a check that was never written.
- `ra8m2/config.cmake:90-98` justifies `MCUBOOT_ALIGN_VAL 32` with a trailer-fit argument
  built on four numbers that are all now wrong: sector size `0x1000` (is `0x8000`),
  `__BL_0_P_T` reserving `0x100` (is 0), NSC `0x300` at `0x60C00` (is `0x400` at
  `0x020AFC00`), `FLASH_CPU0_S` `0x4EA00` (is `0x47A00`). Same defect as [D066], in a file
  [D066] did not touch - and [D066] itself says "Only the prose drifted". The comment also
  points at `RA8M2_SOLUTION.md`, which does not exist.
- `ra8m2/startup_ra8m2.c:114` restates `BSP_VECTOR_TABLE_MAX_ENTRIES` as the literal 112 with
  "re-check these two macros if the device ever changes" and no assertion, although the
  comment itself records the prior failure (it was 496, RA6M4's table, and overflowed
  `.TFM_VECTORS` into `.ER_UNPRIV_CODE`).

**JUSTIFIED and mechanically guarded**, confirmed accurate, listed so they are not re-audited:
`FLASH_NS_ALIAS_BASE` ([D074]), `TFM_TIMER0_IRQ` vs `VECTOR_NUMBER_AGT0_INT` (`#error` plus
`_Static_assert` in `plat_test.c`), `S_MSP_STACK_SIZE` vs `BSP_CFG_STACK_MAIN_BYTES`,
`ra8m2_ddsc.c`'s `gp_ddsc_*` with `#error`s on empty partitions, and the surviving
`AGTCR_b.TUNDF` write (no FSP API exists for it).

**JUSTIFIED but unguarded**, accepted as-is: the five `check_ofs.py` `--region` literals
(a CMake custom command cannot read a generated header; `--require-segments` catches the
total-miss case but not partial staleness), `bsp_init_stub.c`'s empty zero/copy/nocache
tables, `rsip_e50d_fsp_cfg.h`'s restated `PSA_CRYPTO_CFG_*`, and the RDPM KB figures in
`region_defs.h:170` - which have the highest consequence in the audit and no possible
build-time check, since provisioning does not come back.

**The five FSP modules the port shadows wholesale** - `rm_mcuboot_port`, `rm_psa_crypto` +
`ra/arm/mbedtls`, `r_sce`, `bsp_linker.c`, and `startup.c`/`ra_gen/main.c` - all carry stated
reasons and remain justified. `bsp_linker.c` is the most split: four port files plus two
linker scripts, and the two stale RA6 findings above both live inside that split.
`rm_mcuboot_port` is the one whose exclusion has a running cost - it is what forced the
re-derivation in [D073]/[D074] and the loss of FSP's `CFSAMONA`-based boundary and its BL2
SAU programming ([D076]).

**Not acted on.** Everything above except the SCI0 fix. The back-ports to ra6m5/ra6e1 and the
three missing assertions are real work, not edits, and are recorded here rather than done.

---

## D078 — the RA8M2 secure primary slot generated as 0x200; cause was partition ORDER, not geometry

**Date:** 2026-10-02 · **Status:** Accepted · Unblocks the open question in [D076]

**What was wrong.** FSP's generated `flash_map[]` in `<project>/Debug/bsp_linker_info.h` gave
the secure primary slot

```c
.fa_id   = FLASH_AREA_0P_ID,
.fa_size = BSP_PARTITION___BL_0_P_H_SIZE + BSP_PARTITION___BL_0_S_T_SIZE,   /* 0x200 */
```

omitting `FLASH_CPU0_S` (0x47A00) and `FLASH_CPU0_C` (0x400). A 512-byte secure primary slot.
The other three areas were correct. Identical in all three RA8M2 projects, because the table
is generated from the **solution**, not configured per project.

**Found only because the port carries its own map.** `flash_layout.h` computes slot sizes
with `TFM_SLOT_SPAN` - header start to trailer end - which is address-based and immune to
this, so nothing in the TF-M build ever noticed. It surfaced while scoping whether to adopt
`rm_mcuboot_port/flash_map.c` ([D076]).

**The diagnosis that worked: compare against RA6M5.** First hypothesis was that the generator
cannot cope with a zero-size trailer coincident with the next slot's header -
`___BL_0_S_T` and `___BL_0_P_H` both sit at 0x68000. **Wrong.** RA6M5 has exactly the same
coincidence at 0xA0000 and generates correctly. What differs is the order the two are emitted
in:

```
RA6M5   ... S_I,  S_T(0x0),  P_H(0x200),  CPU0_S, CPU0_C, P_T     correct
RA8M2   ... S_I,  P_H(0x200), S_T(0x0),   CPU0_S, CPU0_C, P_T     truncated
```

The generator walks its ordered partition list and sums until it meets a `_T`. With `S_T`
first it closes the secondary slot and `P_H` then opens the primary cleanly. With `P_H` first
it opens the primary and the next entry is `S_T` - the *other* slot's terminator - which
closes it at 0x200. `S_T` also went missing from the `0S` sum, harmless only because it is
zero. Addresses and sizes were identical in both solutions; it is purely a tie-break at a
shared address, reflecting the order the partitions were created or last edited in RASC.

**Fix.** In `ra8m2_gcc/solution.xml`, reorder the two `<memory>` elements at offset 0x68000 so
`__BL_0_S_T` precedes `__BL_0_P_H`, matching RA6M5. Sizes stay with their own partitions -
the first attempt exchanged the whole lines and carried the sizes across, leaving `P_H` at 0
and `S_T` at 0x200, which overruns the secondary slot into the primary and leaves the primary
with no MCUboot header.

`Debug/bsp_linker_info.h` is written by the **e2 build**, not by Generate Project Content, so
the projects must be rebuilt in e2 before the change appears.

**Verified after regeneration**, all three projects, all four areas complete and whole 32 KB
sectors:

| area | offset | size | expression |
|---|---|---|---|
| 0P secure primary | 0x02068000 | 0x48000 | `P_H + FLASH_CPU0_S + FLASH_CPU0_C + P_T` |
| 0S secure secondary | 0x02020000 | 0x48000 | `S_H + S_I + S_T` |
| 1P NS primary | 0x120B0000 | 0x28000 | `P_H + FLASH_CPU0_N + P_T` |
| 1S NS secondary | 0x120D8000 | 0x28000 | `S_H + S_I + S_T` |

FSP's table and `flash_layout.h` now describe identical geometry. `tfm_s_signed.bin` 294,912 B
and `tfm_ns_signed.bin` 163,840 B remain exact slot fits, and TF-M rebuilds clean, so
`ra8m2_layout_checks.c`'s span-vs-sum assertions agree with the new partition data.

**Consequence for [D076].** The objection to adopting `rm_mcuboot_port/flash_map.c` was that
it brings a broken table. It no longer does. What remains is `DEFAULT_MCUBOOT_FLASH_MAP=OFF`
(already supported upstream - corstone1000 and rse both set it) plus one upstream change to
make `bl2/src/flash_map.c` overridable, recorded as item 13 in `UPSTREAM_CHANGES.md`.
`bl2/src/security_cnt.c` stays TF-M's either way; `rm_mcuboot_port` does not provide NV
rollback counters (DESIGN.md 5).

**Worth keeping as method.** Two FSP-generated outputs from the same generator, one correct
and one not, with identical geometry - the diff between them was the whole diagnosis. Reach
for the other port before theorising about the tool.
