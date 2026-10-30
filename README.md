# fsp_cmake

RASC/e2 studio project set and build glue for the TF-M port to Renesas RA. The port itself
lives in the companion repository, `trusted-firmware-m`, under
`platform/ext/target/renesas/<part>/`; this repository holds the generated FSP projects it
consumes, the build scripts, and the design record.

Supported parts: RA6M5 and RA8M2, on FSP 6.7.0-beta0, GNUARM 13.2 or IAR 10.10, and
TF-Mv2.2.0. RA6E1 is included for reference only.

Both supported parts have passed the full `tf-m-tests` regression suite on hardware, at
isolation 1 with the SFN backend (2026-10-05 on RA6M5, 2026-10-06 on RA8M2) and again at
isolation 2 and 3. **The isolation 1 runs predate a later change to the isolation HAL, and the
configuration the build scripts produce has not been re-tested on hardware since.** Isolation 2
and 3 were re-run after that change. `TEST_RESULTS.md` records every run, what it covered and
what it did not.

**TF-M base.** The port is built and tested on TF-Mv2.2.0, the base every test result in
`DECISIONS.md` was measured on. Upstream TF-Mv2.2.2 adds the TFMV-9 fix (CVE-2025-53022,
an unchecked TLV payload length in the Firmware Update partition). The shipped
configuration is not affected, because `TFM_PARTITION_FIRMWARE_UPDATE` is OFF on all three
parts and FWU is untested here. **Turn FWU on and the advisory applies: move to TF-Mv2.2.2
first.** That move is mechanical and touches 6 of the 24 common files this port modifies
(DECISIONS D139).

---

## Security status: development configuration, not for production

Do not deploy devices built from this port unchanged. Each item below must be addressed first.
`DESIGN.md` §13 "Production hardening" says how to address each one; `KNOWN_LIMITATIONS.md`
carries the full list of what is and is not covered.

1. **Signing keys and provisioning are development values.** BL2 trusts the public TF-M sample
   keys compiled into `bl2/ext/mcuboot/keys.c`, because `MCUBOOT_HW_KEY` is `OFF` in every
   part's `config.cmake`. `TFM_DUMMY_PROVISIONING` is `ON`, which supplies dummy HUK and IAK
   values; TF-M's own default marks it "NOT to be used in production". **Changing
   `MCUBOOT_KEY_S` and `MCUBOOT_KEY_NS` alone is not sufficient.** You must also regenerate
   `keys.c`, or enable `MCUBOOT_HW_KEY` with provisioned ROTPK hashes, and supply a real
   provisioning flow.
2. **Anti-rollback is inactive.** `MCUBOOT_SECURITY_COUNTER_S` and `_NS` are both left at the
   upstream default of `1`, and the counters live in emulated OTP. Set a counter per release and
   test that a downgrade is rejected.
3. **Clock, wait-state and low-power registers are writable from the non-secure world.** RASC
   generates `BSP_CFG_CLOCKS_SECURE (0)`, and setting Clocks to Secure in the Security tab does
   not change it. Override the individual security attribution registers through
   `FSP_COMPILE_DEFS` and validate on hardware. Do not instead force
   `BSP_CFG_CLOCKS_SECURE=1`: the generated BSP still reads `0`, and on RA8 parts the port
   relies on that value through its `BSP_TZ_CFG_MSAR=0` workaround (`DESIGN.md` §1.1).
4. **Secure debug and the device lifecycle are not enforced.** The firmware never reads the DLM
   state, and the attested lifecycle comes from emulated OTP. Debug authentication and the DLM
   transition belong to your provisioning flow.
5. **Known issue, from code analysis and not observed at runtime.** While a multi-part AES, GCM
   or CMAC operation is open it holds the SCE9 or RSIP engine, and until that operation
   completes or is aborted `psa_generate_random` fails for every caller.
6. **The scripts build development images.** SPM trace and exception-info dump are on, logging
   is verbose, IAR application builds are `Debug`, and the console is SEGGER RTT.
   `CONFIGURATION.md` describes a release build.
7. **The shipped default configuration has not been re-tested since the isolation-HAL change.**
   Isolation 1 with the SFN backend is what the scripts build, and its last hardware regression
   predates that change. Isolation 2 and 3 were re-run after it. Re-run `tf-m-tests` against
   your own build. Firmware Update is off and untested. `TEST_RESULTS.md` is the single record
   of what has and has not run.
8. **TF-M base is v2.2.0.** If you enable Firmware Update, advisory TFMV-9 (CVE-2025-53022)
   applies and you should move to v2.2.2 first.

---

## The two repositories

| | |
|---|---|
| `fsp_cmake` (here) | e2 studio solutions and generated FSP projects, `scripts/`, the docs below |
| `trusted-firmware-m` | the TF-M fork carrying the RA platform ports and a small patch queue against upstream |

The core principle: RASC is the source of config truth. The TF-M build consumes the
generated projects; it does not fork them. `DESIGN.md` §1. Documented exceptions are listed
in §1.1. Anything else that diverges is a defect, not a choice.

## Start here

[GETTING_STARTED.md](GETTING_STARTED.md) takes you from `git clone` to a board running the
test suite, with commands, versions and the first-build failure table.

The condensed version follows.

## Shortest path to a build

1. Open the solution for your part in e2 studio (`ra6m5_gcc`, `ra8m2_gcc`) and build it.
   The build is a prerequisite: the TF-M build reads `Debug/bsp_linker_info.h`
   and `Debug/memory_regions.*`, which only an e2 build produces. Regenerating alone is not
   enough.
2. Run the matching script from `scripts/` — `app_build_ra6m5_gcc.bat`, `app_build_iar.bat`
   (RA6M5 IAR), `app_build_ra8m2_gcc.bat`, `app_build_ra8m2_iar.bat`. Each builds BL2 +
   secure, installs the SPE, then builds the non-secure image.
3. Flash with the e2 debug launch configurations. RA6M5's are in `ra6m5_gcc_nonsecure/`,
   RA8M2's are in `ra8m2_gcc_mcuboot/`. One launch per part and toolchain loads what step 2
   builds: `ra6m5_TFM_sce9_{gcc,iar}` and `ra8m2_TFM_app_{gcc,iar}`. **Every other launch
   names a build tree of its own**, so read `GETTING_STARTED.md` §6 before flashing.

PSA Arch builds additionally need `scripts\vs_build.bat`. They compile a host tool with
`cl.exe`, which needs a Visual Studio developer environment. See DECISIONS D083.

Two hazards:

- **Flash `bl2.elf` or `bl2.hex`, never `bl2.bin`.** The option-setting words live in discrete
  segments a flat binary cannot express. D002, D065.
- **Keep `setTZBoundaries` = `false`** in every launch configuration. The debugger derives
  boundaries from the launched project's symbols, and launched against BL2 it gets them wrong.
  `DESIGN.md` §7.2.

## Freeing space in the secure image

The secure slot is nearly full on both active parts. Look here first when an image no longer
fits:

```
            raw tfm_s.bin   signed payload ends   slot        true spare
RA6M5           521,792             522,579    524,288         1,693 B
RA8M2           293,440             294,226    294,912           670 B
```

Measured 2026-10-04 by locating the 0xFF gap between the signed payload and the 16-byte
trailer at the top of the slot. Earlier figures here said 1,984 B and 960 B. Those were
`raw image + header` against the slot and omitted the ~275 B of imgtool TLVs (signature and
hashes) and the trailer, which overstated RA8M2's headroom by 30%.

The PSA Arch builds turn several diagnostics on. A user running those suites wants them
available, and `profile_large` at isolation 3 has the room. The ordinary regression and
FLIH/SLIH builds do not have the room and leave them off. Measured on RA6M5, GCC 13.2:

| Option | Cost | Set by |
|---|---|---|
| `MCUBOOT_LOG_LEVEL=INFO` | **BL2** text +5,960 B, bss +4,284 B | `psa_arch_spe*.bat` |
| `TFM_SPM_LOG_LEVEL=..._DEBUG`<br>`TFM_PARTITION_LOG_LEVEL=..._INFO`<br>`CONFIG_TFM_HALT_ON_CORE_PANIC=ON` | **secure** text +3,785 B (the three together) | `psa_arch_spe*.bat` |
| `TFM_EXCEPTION_INFO_DUMP=ON` | secure text ~3.4 KB | `<part>/config.cmake` — on everywhere |
| `TFM_SPM_DEBUG_TRACE` | a handful of bytes | ON in both platform `config.cmake`s. The constraint is not isolation or IPC: `check_config.cmake:119` rejects TRACE with a `_SILENCE` log level, which is what `MinSizeRel`/`Release` set ([D007]) |

Turning the first two groups off recovers roughly 3.7 KB of secure flash and 6 KB of BL2
flash. The PSA Arch scripts pass them on the command line rather than setting them in
`<part>/config.cmake`, so they do not reach the builds that cannot afford them: 3,785 B
against the real headroom of 1,693 B on RA6M5 and 670 B on RA8M2 ([D087]) would not link.

`TFM_EXCEPTION_INFO_DUMP` is the one worth considering for a production image. It is on for
every build today and is pure diagnostics.

## Reading the port as a diff

`e2_baseline/` holds the RA6M5 and RA8M2 GCC solutions as e2 studio first creates them, on
exactly the FSP pack the port uses. Every RASC decision the port makes is therefore readable
as a diff rather than taken on trust:

```
git diff HEAD:e2_baseline/ra6m5_gcc_secure/.secure_azone \
         HEAD:ra6m5_gcc_secure/.secure_azone
```

That one comparison carries the whole RA6M5 layout decision: both image slots doubled, the
NSC window moved, data flash made wholly secure, AGT0 and IRQ0 made secure.
`e2_baseline/README.md` lists the five other comparisons worth making and what each shows.

The same files are also on the orphan branch `e2-baseline`, which shares no history with the
port. The copy in this tree is byte-identical and is the one to use ([D140]).

## The documents

**Start here, in this order.**

| | |
|---|---|
| `README.md` (this file) | what the repo is, the shortest path to a build, the space budget |
| `DESIGN.md` | how the port works. §1 the core principle, §1.1 documented deviations, §4 flash geometry, §7 TrustZone and the SAU |
| `TROUBLESHOOTING.md` | indexed by the symptom you see. The two brick hazards are first |
| `CONFIGURATION.md` | every knob you may change: default, where it is defined, and the constraint that bites. Start with its "how the three layers interact" section |
| `RA6M5_SOLUTION.md`, `RA8M2_SOLUTION.md` | per-part: the layout, the RDPM boundary values, what the e2 projects must provide, and current status. The RDPM values live here and nowhere else |
| `KNOWN_LIMITATIONS.md` | **read before committing to this port.** What it does not do, what is untested, and what is known broken: crypto per part, boot and upgrade, the open hazards |
| `DECISIONS.md` | why, append-only. Superseded entries stay; later ones say so |

**Reference.**

| | |
|---|---|
| `TEST_RESULTS.md` | every hardware run, with its result and the DECISIONS entry that recorded it. Read it with `PROJECT_PLAN.md` §"Test coverage gaps", which lists what has never run |
| `BUILD_ARCHITECTURE.md` | the CMake target graph: the two projects and the `api_ns/` handoff, every link edge with its file and line, what the port adds to each upstream target, the FSP module registry, and the post-link checks |
| `FLASH_MAP_OWNERSHIP.md` | design review: what MCUboot's porting contract is, how TF-M narrows it, what other vendors do, and where this port diverges from the two standing objectives |
| `BRIDGING_FILES.md` | **read before any FSP pack uprev.** Every file that carries FSP code or restates an FSP-generated value, and the check that detects drift in each |
| `UPSTREAM_CHANGES.md` | the patch queue against upstream TF-M, with the rationale for each |
| `scripts/README.md` | what each build script does |
| `RECONFIGURING_THE_LAYOUT.md` | **read before changing the partitioning.** Resizing a slot, moving the storage area or growing the bootloader: what follows automatically, the four things that do not, and the 35 assertions |
| `RA6E1_TEMPLATE_CHECKLIST.md` | the contract a new part's RASC projects must satisfy |
| `RA8x2_DUAL_CORE_DESIGN.md` | forward design for the dual-core parts |
| [GETTING_STARTED.md](GETTING_STARTED.md) | clone to running board; §6 carries the **pre-flash verification** — the brick-safety steps to run on every new build |
| `RA6E1_SOLUTION.md` | the RA6E1 layout and resolved-issue log. Dormant part, but it is the port RA6M5 and RA8M2 are derived from |

**Planning and history.**

| | |
|---|---|
| `PROJECT_PLAN.md` | schedule and open tasks |
| `DOCUMENTATION_PLAN.md` | the target document set and the gap list; retire it once the set exists |
| `bringup/bricking_evidence/` | the preserved image behind [D133], the OFS coalescing brick |
| `e2_baseline/` | the two GCC solutions as e2 first creates them, for reading the port's RASC choices as a diff ([D140]) |

`DOCUMENTATION_PLAN.md` tracks the target document set and what is still outstanding.
