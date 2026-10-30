# ra_fsp_cmake_tfm

The e2 studio/RASC projects, build scripts and documents for the TF-M port to Renesas RA. The
port itself is in `trusted-firmware-m` under `platform/ext/target/renesas/<part>/`.

| | |
|---|---|
| Parts | RA6M5 and RA8M2 (single-core; RA8M2's CPU1 is unused). RA6E1 is present for reference only and is not maintained against the current build |
| FSP | 6.7.0-beta0 |
| Toolchains | Arm GNU 13.2, IAR EWARM 10.10.2 |
| TF-M base | v2.2.0 |

Before committing to this port, read the security status below,
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md), and [TEST_RESULTS.md](TEST_RESULTS.md) for what has
run on hardware.

---

## Security status: development configuration, not for production

Do not deploy devices built from this port unchanged. [DESIGN.md](DESIGN.md) §13 gives the remedy
for each item.

1. **Signing keys and provisioning are development values.** BL2 trusts the TF-M sample keys in
   `bl2/ext/mcuboot/keys.c`, and `TFM_DUMMY_PROVISIONING` is `ON`. Changing `MCUBOOT_KEY_S`/`_NS`
   alone is not enough (§13.1).
2. **Anti-rollback is inactive.** `MCUBOOT_SECURITY_COUNTER_S` and `_NS` are both left at the
   upstream default of `1`, and the counters live in emulated OTP. Set a counter per release and
   test that a downgrade is rejected.
3. **Clock, wait-state and low-power registers are writable from the non-secure world.** RASC
   always generates `BSP_CFG_CLOCKS_SECURE (0)`; §13.3 gives the override and why not to force
   the macro.
4. **Secure debug and the device lifecycle are not enforced.** The firmware never reads the DLM
   state, and the attested lifecycle comes from emulated OTP. Debug authentication and the DLM
   transition belong to your provisioning flow.
5. **Known issue, from code analysis and not observed at runtime.** While a multi-part AES, GCM
   or CMAC operation is open it holds the SCE9 or RSIP engine, and until that operation
   completes or is aborted `psa_generate_random` fails for every caller.
6. **The scripts build development images.** SPM trace and exception-info dump are on, logging
   is verbose, IAR application builds are `Debug`, and the console is SEGGER RTT.
   [CONFIGURATION.md](CONFIGURATION.md) §9 describes a release build.
7. **The shipped default (isolation 1, SFN) has not been re-run on hardware since the
   isolation-HAL change.** Re-run `tf-m-tests` on your build. Firmware Update is off and
   untested.
8. **TF-M base is v2.2.0.** If you enable Firmware Update, advisory TFMV-9 (CVE-2025-53022)
   applies and you should move to v2.2.2 first.

---

## Start here

[GETTING_STARTED.md](GETTING_STARTED.md) takes you from clone to a running board, both parts and
both toolchains. Read its §6 safety rules before the first flash.

## The two repositories

| | |
|---|---|
| `ra_fsp_cmake_tfm` (here) | the e2 studio solutions and generated FSP projects, `scripts/`, and the documents below |
| `trusted-firmware-m` | the TF-M fork carrying the RA platform ports, and a small patch queue against upstream |

RASC is the source of configuration truth: the build consumes the generated projects and never
forks them ([DESIGN.md](DESIGN.md) §1). The TF-M side has one part card per part:
`trusted-firmware-m/platform/ext/target/renesas/README.md`.

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
| [MAINTAINERS.md](MAINTAINERS.md) | the launch generator, the documentation checkers, the hooks and the reference renderer. Needed to maintain the scripts, not to use them |
| [DECISIONS.md](DECISIONS.md) | why, append-only, with [SETTLED.md](SETTLED.md) as its generated index |
| [e2_baseline/README.md](e2_baseline/README.md) | reading the port's RASC choices as a diff |
| [bringup/bricking_evidence/README.md](bringup/bricking_evidence/README.md) | the preserved image behind the option-memory brick |
| [docs/learning/README.md](docs/learning/README.md) | a course on privilege, TrustZone and TF-M on RA. Optional background |
