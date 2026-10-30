# fsp_cmake

The RASC/e2 studio project set and build glue for the TF-M port to Renesas RA. The port itself
lives in the companion repository, `trusted-firmware-m`, under
`platform/ext/target/renesas/<part>/`. This repository holds the generated FSP projects that
build consumes, the build scripts, and the design record.

| | |
|---|---|
| Parts | RA6M5 and RA8M2. RA6E1 is present for reference only and is not maintained against the current build |
| FSP | 6.7.0-beta0 |
| Toolchains | Arm GNU 13.2, IAR EWARM 10.10.2 |
| TF-M base | v2.2.0 |

[TEST_RESULTS.md](TEST_RESULTS.md) is the only record of what has run on hardware and what has
not. Read it with the security status below before committing to this port.

---

## Security status: development configuration, not for production

Do not deploy devices built from this port unchanged. Each item below must be addressed first.
[DESIGN.md](DESIGN.md) §13 "Production hardening" says how to address each one;
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) carries the full list of what is and is not covered.

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
   relies on that value through its `BSP_TZ_CFG_MSAR=0` workaround ([DESIGN.md](DESIGN.md) §1.1).
4. **Secure debug and the device lifecycle are not enforced.** The firmware never reads the DLM
   state, and the attested lifecycle comes from emulated OTP. Debug authentication and the DLM
   transition belong to your provisioning flow.
5. **Known issue, from code analysis and not observed at runtime.** While a multi-part AES, GCM
   or CMAC operation is open it holds the SCE9 or RSIP engine, and until that operation
   completes or is aborted `psa_generate_random` fails for every caller.
6. **The scripts build development images.** SPM trace and exception-info dump are on, logging
   is verbose, IAR application builds are `Debug`, and the console is SEGGER RTT.
   [CONFIGURATION.md](CONFIGURATION.md) §9 describes a release build.
7. **The shipped default configuration has not been re-tested since the isolation-HAL change.**
   Isolation 1 with the SFN backend is what the scripts build, and its last hardware regression
   predates that change. Isolation 2 and 3 were re-run after it. Re-run `tf-m-tests` against
   your own build. Firmware Update is off and untested. [TEST_RESULTS.md](TEST_RESULTS.md) is the single record
   of what has and has not run.
8. **TF-M base is v2.2.0.** If you enable Firmware Update, advisory TFMV-9 (CVE-2025-53022)
   applies and you should move to v2.2.2 first.

---

## Start here

[GETTING_STARTED.md](GETTING_STARTED.md) takes you from `git clone` to a board running the test
suite: versions, environment variables, the e2 build, TrustZone partitioning, the build and
flash steps for both parts and both toolchains, the pre-flash brick checks, and a table of
first-build failures.

Two rules it will repeat, because neither failure is recoverable:

> **Flash `bl2.elf`, `bl2.hex` or `bl2.srec` — never `bl2.bin`.** The option-setting words live in discrete
> segments that a flat binary cannot express. [D002](DECISIONS.md), [D065](DECISIONS.md).

> **Keep `setTZBoundaries` = `false`** in every launch configuration. The debugger otherwise
> derives the TrustZone boundaries from the launched project's symbols, and launched against
> BL2 it gets them wrong. [DESIGN.md](DESIGN.md) §7.2.

## The two repositories

| | |
|---|---|
| `fsp_cmake` (here) | the e2 studio solutions and generated FSP projects, `scripts/`, and the documents below |
| `trusted-firmware-m` | the TF-M fork carrying the RA platform ports, and a small patch queue against upstream |

RASC is the source of configuration truth: the TF-M build consumes the generated projects and
does not fork them. [DESIGN.md](DESIGN.md) §1 states the principle and §1.1 lists every
documented exception. Anything else that diverges is a defect rather than a choice.

`e2_baseline/` holds both GCC solutions as e2 studio first creates them, on the same FSP pack,
so every RASC choice the port makes is readable as a diff rather than taken on trust.
[e2_baseline/README.md](e2_baseline/README.md) lists the comparisons worth making and what each
one shows.

## The documents

**Main path, in order.**

| | |
|---|---|
| [GETTING_STARTED.md](GETTING_STARTED.md) | clone to running board. Every procedure, for both parts and both toolchains |
| [DESIGN.md](DESIGN.md) | how the port works, and §13 how to harden it for production |
| [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md), [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) | per part: the layout, the TrustZone boundary values the partition manager asks for, and what the e2 projects must provide |
| [CONFIGURATION.md](CONFIGURATION.md) | every option you may change, its default, and the constraint that bites. §6 owns the secure-slot space budget |
| [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) | what the port does not do, what is untested, and what is known to be broken |
| [TEST_RESULTS.md](TEST_RESULTS.md) | every hardware run, and every suite that has never run |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | indexed by the symptom you are looking at. The brick hazards come first |

**Task reference.**

| | |
|---|---|
| [RECONFIGURING_THE_LAYOUT.md](RECONFIGURING_THE_LAYOUT.md) | resizing a slot, moving the storage area, growing the non-secure-callable window |
| [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) | you enabled a driver in RASC and TF-M does not link it |
| [E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md) | the contract a part's generated projects must satisfy |
| [FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md) | before an FSP pack uprev: every file that carries FSP code or restates a generated value |
| [scripts/README.md](scripts/README.md) | what each build script does, its arguments, and its output trees |

**Appendix.** Shipped, outside the main path.

| | |
|---|---|
| [PORTING.md](PORTING.md) | adding a new RA part |
| [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) | the modifications this port makes to common TF-M code |
| [BUILD_ARCHITECTURE.md](BUILD_ARCHITECTURE.md) | the CMake target graph, and the `api_ns/` handoff between the two builds |
| [DECISIONS.md](DECISIONS.md) | why, append-only, with [SETTLED.md](SETTLED.md) as its generated index |
| [e2_baseline/README.md](e2_baseline/README.md) | reading the port's RASC choices as a diff |
| [bringup/bricking_evidence/README.md](bringup/bricking_evidence/README.md) | the preserved image behind the option-memory brick |
| [docs/learning/README.md](docs/learning/README.md) | a course on privilege, TrustZone and TF-M on RA. Optional background |
