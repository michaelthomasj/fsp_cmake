# Getting started

**Audience:** someone who has not seen this port before and wants a board running TF-M.
Follow it top to bottom and you will have the full chain — bootloader, secure image, non-secure
image — built and running on an EK-RA8M2 or EK-RA6M5. Everything deeper is linked at the end.

**Expect ~1 hour** the first time, most of it tool installation.

---

## 1. What you are building

Three images, flashed to one part:

| Image | What it is |
|---|---|
| `bl2` | MCUboot. Verifies and chainloads the other two. Lives at the base of flash. |
| `tfm_s` | The secure image — TF-M itself plus the crypto, storage and attestation services. |
| `tfm_ns` | The non-secure application. Either the port's demo app or a test suite. |

Two repositories, and the relationship between them is the thing to understand first:

| Repository | Holds |
|---|---|
| **`trusted-firmware-m`** | The TF-M fork. The RA ports live in `platform/ext/target/renesas/<part>/`. |
| **`fsp_cmake`** | The e2 studio / RASC projects, the build scripts, and the design record. |

> **RASC is the source of config truth.** The TF-M build *consumes* the generated FSP projects;
> it does not fork them. Pin numbers, clock settings, the memory partitioning and the
> TrustZone boundaries all come from the e2 solution. See [DESIGN.md](DESIGN.md) §1.

---

## 2. Prerequisites

Versions below are the ones this port is built and tested with. Others may work; these are
what the results in [DECISIONS.md](DECISIONS.md) were produced on.

| Tool | Version | Notes |
|---|---|---|
| **e2 studio** + **RASC** | with FSP **6.7.0-beta0** | Required even for command-line builds — see §4 |
| **Arm GNU Toolchain** | 13.2.rel1 | `arm-none-eabi-gcc` on `PATH` |
| **IAR EWARM** | 10.10.2 | Optional — only for the IAR trees |
| **CMake** | 4.1.1 | |
| **Ninja** | 1.13.1 | |
| **Python** | 3.13 | Needs `imgtool`'s dependencies; TF-M installs them |
| **J-Link** | current | The on-board debugger on both EK boards |
| **Visual Studio Build Tools** | 2019 | **Only** for PSA Arch builds — they compile a host tool with `cl.exe` ([D083](DECISIONS.md)) |

Hardware: **EK-RA8M2** or **EK-RA6M5**, and a USB cable to the on-board J-Link.

---

## 3. Clone

Keep paths short. Build directories under a deep path overrun Windows' path limit partway
through the Mbed TLS clone and fail with `Filename too long` on `3rdparty/everest/...`, which
does not mention length.

```bat
cd C:\Users\<you>\Documents\GitHub

git clone https://github.com/renesas/trusted-firmware-m.git
git clone https://github.com/michaelthomasj/fsp_cmake.git

rem  Only needed for the test-suite builds in §7
git clone https://git.trustedfirmware.org/TF-M/tf-m-tests.git
git clone https://github.com/ARM-software/psa-arch-tests.git
```

Both repositories track the same branch:

```bat
cd trusted-firmware-m && git checkout ra8m2_gen_6_7_TFM && cd ..
cd fsp_cmake        && git checkout ra8m2_gen_6_7_TFM && cd ..
```

**You do not clone MCUboot or Mbed TLS.** TF-M fetches both during the first configure
(`MCUBOOT_PATH` and `MBEDCRYPTO_PATH` default to `DOWNLOAD`). The first build is therefore
slower and needs network access.

---

## 4. Build the e2 solution first — this is not optional

The TF-M build reads two files that **only an e2 studio build produces**:

- `<project>/Debug/bsp_linker_info.h` — the `BSP_PARTITION_*` addresses the whole memory map
  derives from
- `<project>/Debug/memory_regions.*`

Regenerating the project in RASC is **not** enough; the project must be *built*.

1. Open e2 studio, `File → Import → Existing Projects into Workspace`, and select the
   `fsp_cmake` folder. Import the solution for your part and all its sub-projects:

   | Part | Solution | Sub-projects |
   |---|---|---|
   | RA8M2 | `ra8m2_gcc` | `ra8m2_gcc_mcuboot`, `ra8m2_gcc_CPU0_secure`, `ra8m2_gcc_CPU0_nonsecure` |
   | RA6M5 | `ra6m5_gcc` | `ra6m5_gcc_mcuboot`, `ra6m5_gcc_secure`, `ra6m5_gcc_nonsecure` |

2. Build each sub-project (`Project → Build All`). Ignore the resulting `.elf` files — only the
   generated headers matter here.

3. Confirm the file exists before going on:

   ```bat
   dir ra8m2_gcc_CPU0_secure\Debug\bsp_linker_info.h
   ```

   Missing means the e2 build did not complete, and every later step will fail in a way that
   does not point here.

---

## 5. Build the firmware

Each script builds BL2 + the secure image, installs the SPE interface into `api_ns\`, then
builds the non-secure image against it.

```bat
cd C:\Users\<you>\Documents\GitHub\fsp_cmake

rem  RA8M2, GNU
scripts\app_build_ra8m2_gcc.bat C:\b\m2app C:\b\m2appns

rem  RA8M2, IAR
scripts\app_build_ra8m2_iar.bat C:\b\m2iapp C:\b\m2iappns
```

Build directories live under `C:\b\` for the path-length reason in §3. They are disposable;
delete one to force a clean build.

**Read the output, do not just check the exit code.** The install step runs the option-setting
brick guard over `bl2` and `tfm_s`, and it reports by printing.

Where the images land:

```
C:\b\m2app\bin\bl2.elf                 the bootloader  (flash THIS, see §6)
C:\b\m2app\bin\tfm_s_signed.bin        the secure image
C:\b\m2appns\bin\tfm_ns_signed.bin     the non-secure image
```

---

## 6. Flash and run

Use the e2 debug launch configurations — they already carry the correct addresses and the two
safety settings below. For RA8M2 they are in `ra8m2_gcc_mcuboot/`:

| Launch | Runs |
|---|---|
| `ra8m2_TFM_flih_gcc` | the full regression suite, including interrupt tests |
| `ra8m2_TFM_test_crypto_gcc` | PSA Arch crypto conformance |
| `ra8m2_TFM_test_attestation_gcc` | PSA Arch attestation |
| `ra8m2_TFM_test_storage_gcc` | PSA Arch ITS + PS |
| `ra8m2_TFM_update_gcc` | the MCUboot secondary-slot upgrade test |

Each has an `_iar` twin. In e2: `Run → Debug Configurations…`, pick one, `Debug`.

### Two rules that have cost hardware

> **Flash `bl2.elf` or `bl2.hex` — never `bl2.bin`.** The option-setting words live in discrete
> segments that a flat binary cannot express; a `.bin` writes them at the wrong addresses and
> can permanently lock the part. [D002](DECISIONS.md), [D065](DECISIONS.md).

> **`setTZBoundaries` must be `false`** in every launch configuration. The debugger otherwise
> derives TrustZone boundaries from the launched project's symbols, and launched against BL2 it
> gets them wrong. On RA8M2 the key appears **twice** — `...arm.jlink.` and `...arm.e2lite.` —
> and e2 defaults the second to `true`. Set both. [DESIGN.md](DESIGN.md) §7.2,
> [D102](DECISIONS.md).

Also leave **erase code flash** and **erase data flash** enabled on connect. A stale ITS/PS area
survives a reflash and makes the storage suites fail in ways that look like code faults.

### Seeing the output

Console output goes over **SEGGER RTT**, not a UART. Each image has its own control block and
**the address moves on every rebuild**, so read it rather than reusing a remembered value:

```bat
arm-none-eabi-nm C:\b\m2appns\bin\tfm_ns.axf | findstr " _SEGGER_RTT$"
```

Point J-Link RTT Viewer at that address.

**BL2's log needs a halt.** BL2 and the secure image share RAM, so the secure image's startup
wipes BL2's control block microseconds after the chainload — a viewer that auto-detects after
reset always finds the secure image's. To capture BL2: breakpoint inside it, attach the viewer
at BL2's address *while halted*, then run. [D100](DECISIONS.md), [D110](DECISIONS.md).

### What a good run looks like

```
[INF] Starting bootloader
[INF] Bootloader chainload address offset: 0x68000
[INF] Image version: v2.2.0
Booting TF-M v2.2.0+...
[Sec Thread] Secure image initializing!
TF-M isolation level is: 0x00000003
[INF][Crypto] Init HW accelerator... complete.
Non-Secure system starting...
```

---

## 7. Test-suite builds

These use a different configuration from the application build — larger profile, isolation
level 3, the IPC backend — so they are separate scripts and separate build trees.

```bat
rem  PSA Arch. One secure image serves all three suites; each suite gets its own NS app.
rem  The third argument selects the part; omit it for RA6M5.
scripts\vs_build.bat
scripts\psa_arch_spe.bat  C:\b\m2cry   CRYPTO ra8m2
scripts\psa_arch_ns.bat   C:\b\m2cryns C:\b\m2cry\api_ns CRYPTO

rem  Regression suites (tf-m-tests). Fourth argument picks the IRQ suite.
scripts\reg_build_iar.bat C:\b\m2iflih C:\b\m2iflihns ra8m2 flih
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE`, `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`.

`scripts\vs_build.bat` must run first for PSA Arch — those builds compile a host tool with
`cl.exe`. Without it you get `C1083: stdio.h` and nothing explaining why.

Full detail, build-tree naming and the RTT guidance: [scripts/README.md](scripts/README.md).

---

## 8. When it does not work

[TROUBLESHOOTING.md](TROUBLESHOOTING.md) is indexed by symptom. The ones most likely to hit you
on a first build:

| Symptom | Cause |
|---|---|
| `bsp_linker_info.h: No such file` | §4 — the e2 solution was not *built* |
| `Filename too long` on `3rdparty/everest/...` | build directory path too deep; use `C:\b\` |
| `C1083: stdio.h` in a PSA Arch build | `scripts\vs_build.bat` not run |
| `INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND ... _SILENCE` | `CMAKE_BUILD_TYPE` omitted |
| Nothing on RTT | wrong control-block address (it moves every build), or BL2 — see §6 |
| `region CODE_RAM overflowed` | see [CONFIGURATION.md](CONFIGURATION.md) |

---

## 9. Where to go next

| Document | Read it when you want |
|---|---|
| [README.md](README.md) | the one-page orientation and repository map |
| [DESIGN.md](DESIGN.md) | **how the port works** — the config-truth principle, the flash map, the SAU, MCUboot integration |
| [CONFIGURATION.md](CONFIGURATION.md) | every knob you may legitimately change, with its constraints |
| [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) / [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) | the per-part memory map, board settings and open items |
| [scripts/README.md](scripts/README.md) | build trees, test configurations, RTT, the upgrade test |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | a symptom you are looking at right now |
| [DECISIONS.md](DECISIONS.md) | **why** something is the way it is. Append-only, numbered `D001`… — the rest of the docs cite it by number |
| [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) | you enabled a driver in RASC and TF-M does not link it |
| [BRIDGING_FILES.md](BRIDGING_FILES.md) | before an FSP package uprev — the files that carry FSP code but do not move with it |
| [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) | what this port changes outside `platform/ext/target/renesas/`, and why |
| [PROJECT_PLAN.md](PROJECT_PLAN.md) | milestones, phases and test-coverage gaps |
| [RA6E1_TEMPLATE_CHECKLIST.md](RA6E1_TEMPLATE_CHECKLIST.md) | you are adding a new RA part |
| [RSIP7_INTEGRATION_PLAN.md](RSIP7_INTEGRATION_PLAN.md) | the planned move to TF-PSA-Crypto (Mbed TLS 4.x) |
| [DOCUMENTATION_PLAN.md](DOCUMENTATION_PLAN.md) | you are adding to these documents |

**If you read one other document, make it `DESIGN.md` §1.** It explains why the e2 projects are
generated rather than edited, which is the constraint most newcomers trip over.
