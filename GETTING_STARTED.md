# Getting started

Clone to a running board — bootloader, secure and non-secure images — on an EK-RA8M2 or CK-RA6M5
V2, with either toolchain. Allow about an hour, mostly tool installation.

> **This builds a development configuration; do not deploy it unchanged.** [README.md](README.md)
> §"Security status" lists why; [DESIGN.md](DESIGN.md) §13 gives each remedy.

---

## 1. What you are building

Three images, flashed to one part:

| Image | What it is |
|---|---|
| `bl2` | MCUboot. Verifies and chainloads the other two. Lives at the base of flash. |
| `tfm_s` | The secure image — TF-M itself plus the crypto, storage and attestation services. |
| `tfm_ns` | The non-secure application. Either the port's demo app or a test suite. |

The two repositories are described in [README.md](README.md); why the e2 projects are generated
rather than edited is [DESIGN.md](DESIGN.md) §1.

---

## 2. Prerequisites

Tested versions:

| Tool | Version | Notes |
|---|---|---|
| e2 studio + RASC | FSP 6.7.0-beta0 | needed even for command-line builds (§4) |
| Arm GNU Toolchain | 13.2.rel1 | `set GCC_BIN=<install>\bin` |
| IAR EWARM | 10.10.2 | optional; `set IAR_BIN=<install>\arm\bin` |
| CMake / Ninja | 4.1.1 / 1.13.1 | |
| Python | 3.13 | `python -m pip install -r trusted-firmware-m\tools\requirements.txt` |
| J-Link | current | on-board on both boards |
| VS Build Tools | 2019 | PSA Arch builds only; `set MSVC_VARS=<path>\vcvars64.bat` |

Other variables: [scripts/README.md](scripts/README.md) §"Environment variables". Hardware:
EK-RA8M2 or CK-RA6M5 V2 and a USB cable.

---

## 3. Clone

Build trees must sit on a short path - the scripts use `C:\b\`. A deep one fails partway
through the Mbed TLS overlay clone with `Filename too long` (§8).

```bat
cd C:\Users\<you>\Documents\GitHub

git clone https://github.com/renesas/trusted-firmware-m.git
git clone https://github.com/renesas/ra_fsp_cmake_tfm.git

rem  Only needed for the test-suite builds in §7
git clone https://git.trustedfirmware.org/TF-M/tf-m-tests.git
git clone https://github.com/renesas/psa-arch-tests.git
```

Check out the revisions the results were produced on. A release tag, once cut, replaces the
two branch names:

```bat
cd trusted-firmware-m && git checkout ra8m2_gen_6_7_TFM     && cd ..
cd ra_fsp_cmake_tfm   && git checkout ra8m2_gen_6_7_TFM     && cd ..
cd tf-m-tests         && git checkout e0a433c               && cd ..
cd psa-arch-tests     && git checkout renesas-ra-tfm-2.2.0  && cd ..
```

Use the Renesas `psa-arch-tests` fork at that tag: upstream lacks the `renesas_ra` target and the
patches the results depend on.

TF-M downloads MCUboot and Mbed TLS on the first configure, so the first build needs network
access and is slower.

---

## 4. Build the e2 solution first — this is not optional

The TF-M build reads two files that only an e2 studio build produces:

- `<project>/Debug/bsp_linker_info.h` — the `BSP_PARTITION_*` addresses the whole memory map
  derives from
- `<project>/Debug/memory_regions.*`

Regenerating is not enough: build the projects in e2 studio, which writes these files to `Debug/`
(the standalone Smart Configurator does not). This prerequisite is planned to go;
[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §7.

1. In e2 studio, `File → Import → Existing Projects into Workspace`, and select the
   **repository root**. The solution folders hold only `solution.xml`; the projects themselves
   are siblings of them. Tick your part's solution and its three sub-projects, and **untick
   everything under `e2_baseline/`** — those carry the same project names and e2 will not
   import both.

   | Part | GNU solution | Sub-projects | IAR solution |
   |---|---|---|---|
   | RA8M2 | `ra8m2_gcc` | `ra8m2_gcc_mcuboot`, `ra8m2_gcc_CPU0_secure`, `ra8m2_gcc_CPU0_nonsecure` | `ra8m2_iar` |
   | RA6M5 | `ra6m5_gcc` | `ra6m5_gcc_mcuboot`, `ra6m5_gcc_secure`, `ra6m5_gcc_nonsecure` | `ra6m5_iar` |

   **Import and build the GNU solution even if you build with IAR.** Every debug launch lives
   in a GNU project — 19 in `ra6m5_gcc_nonsecure/`, 17 in `ra8m2_gcc_mcuboot/`, none in an IAR
   project — and the RA6M5 launches load their debug symbols from
   `ra6m5_gcc_nonsecure/Debug/ra6m5_gcc_nonsecure.elf`.

2. Build each sub-project (`Project → Build All`). Ignore the resulting `.elf` files; only the
   generated headers matter here.

3. Confirm the file exists before going on:

   ```bat
   dir <secure project>\Debug\bsp_linker_info.h    rem  ra6m5_gcc_secure, ra8m2_gcc_CPU0_secure, or the _iar_ equivalent
   ```

If it is missing, the e2 build did not finish; every later step fails without saying why.

---

## 5. Build the firmware

Each script builds BL2 + the secure image, installs the SPE interface into `api_ns\`, then
builds the non-secure image against it. There is one script per part and toolchain:

```bat
cd C:\Users\<you>\Documents\GitHub\ra_fsp_cmake_tfm

scripts\app_build_ra6m5_gcc.bat
scripts\app_build_iar.bat
scripts\app_build_ra8m2_gcc.bat
scripts\app_build_ra8m2_iar.bat
```

`app_build_iar.bat` is RA6M5's. Run each bare: the defaults below are the trees the §6 launches
flash.

| Part | Toolchain | Secure build | Non-secure build |
|---|---|---|---|
| RA6M5 | GNU | `C:\b\m5g` | `C:\b\m5gns` |
| RA6M5 | IAR | `C:\b\m5i` | `C:\b\m5ins` |
| RA8M2 | GNU | `C:\b\m2g` | `C:\b\m2gns` |
| RA8M2 | IAR | `C:\b\m2app` | `C:\b\m2appns` |

All trees are under `C:\b\` because a launch names every image by absolute path; delete a tree to
force a clean build. The build type is fixed per part and toolchain, and the scripts set it
([CONFIGURATION.md](CONFIGURATION.md) §1).

**Read the build output, not only the exit code:** the install step prints the option-memory
brick guard's result.

Where the images land, with RA8M2 GNU as the example:

```
C:\b\m2g\bin\bl2.elf                   the bootloader  (flash THIS, see §6)
C:\b\m2g\bin\tfm_s_signed.bin          the secure image
C:\b\m2gns\bin\tfm_ns_signed.bin       the non-secure image
```

---

## 6. Flash and run

### Program the TrustZone boundaries first — once per board

Once per board, before the first flash, set the boundaries with the Renesas Device Partition
Manager (e2 studio, `Run → Renesas Debug Tools`). Enter the six per-part values, in KB, from:

| Part | Values |
|---|---|
| RA6M5 | [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) |
| RA8M2 | [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) |

The part must be in the SSD lifecycle state for RDPM to write the boundaries; a part in a
locked state refuses, and the recovery is a lifecycle transition rather than a retry.

**RDPM erases both code flash and data flash.** Reflash all three images afterwards. The step
repeats only if you change the layout, which is
[RECONFIGURING_THE_LAYOUT.md](RECONFIGURING_THE_LAYOUT.md).

### The launches

In e2: `Run → Debug Configurations…`, pick a launch, `Debug`. RA6M5 launches are in
`ra6m5_gcc_nonsecure/`, RA8M2 launches in `ra8m2_gcc_mcuboot/`.

| Runs | RA6M5 | RA8M2 |
|---|---|---|
| the application §5 builds | `ra6m5_TFM_sce9_{gcc,iar}` | `ra8m2_TFM_app_{gcc,iar}` |
| the application with software ciphers | `ra6m5_TFM_swCrypto_gcc` | — |
| the regression suite, no interrupt tests | `ra6m5_TFM_regression_{gcc,iar}` | — |
| the regression suite with FLIH interrupt tests | `ra6m5_TFM_flih_gcc` | `ra8m2_TFM_flih_{gcc,iar}` |
| the same with SLIH | `ra6m5_TFM_slih_{gcc,iar}` | — |
| FLIH at isolation 2 and 3 | `ra6m5_TFM_flih_L{2,3}_{gcc,iar}` | `ra8m2_TFM_flih_L{2,3}_{gcc,iar}` |
| FLIH at isolation 1 on the IPC backend | `ra6m5_TFM_flih_L1ipc_gcc` | `ra8m2_TFM_flih_L1ipc_gcc` |
| PSA Arch crypto, attestation, storage | `ra6m5_TFM_test_{crypto,attestation,storage}_{gcc,iar}` | `ra8m2_TFM_test_{crypto,attestation,storage}_{gcc,iar}` |
| the MCUboot secondary-slot upgrade | — | `ra8m2_TFM_update_{gcc,iar}` |

Gaps in the table are real coverage gaps ([TEST_RESULTS.md](TEST_RESULTS.md) §9).

> **Only the first row flashes what §5 builds.** Every other launch expects its own tree; build
> it with the script in §7 (for the FLIH row:
> `scripts\reg_build_gcc.bat C:\b\m2gflih C:\b\m2gflihns ra8m2 flih 1 SFN`), or retarget a launch
> with `scripts\mk_level_launch.py`.

### Two safety rules

> **Flash `bl2.elf`, `.hex` or `.srec`, never `bl2.bin`:** a flat binary writes the option words
> at the wrong addresses and can brick the part ([DESIGN.md](DESIGN.md) §8.4).

> **Keep `setTZBoundaries` false** for every probe key (`...jlink.` and `...e2lite.`), or the
> debugger reprograms the boundaries from the launched project's symbols and gets them wrong
> against BL2. Every shipped launch does; never launch from `e2_baseline/`
> ([DESIGN.md](DESIGN.md) §7.2).
> Check an unfamiliar launch with `findstr setTZBoundaries <launch>`.

Also leave the J-Link options to erase code flash and data flash **on download** enabled
(`eraseRomOnDownload`, `eraseDataRomOnDownload`). **A stale ITS/PS area survives a reflash** and makes the storage suites fail in ways that look like code faults.

### Pre-flash verification — run on every new build

Run both checks on every image you are about to flash; a clean `.srec` proves neither
([DESIGN.md](DESIGN.md) §8.4 explains the failure). Check one — the option words are in discrete
segments:

```bat
set READELF=arm-none-eabi-readelf
set GUARD=..\trusted-firmware-m\platform\ext\target\renesas\common\check_ofs.py

rem  RA6M5
python %GUARD% --ra6-default --max-word 0x10 --require-segments ^
  C:\b\m5g\bin\bl2.axf

rem  RA8M2
python %GUARD% --max-word 4 --require-segments ^
  --region 0x02c9f040:0x02c9f280 --region 0x12c9f4c0:0x12c9f680 ^
  --region 0x02e07600:0x02e07698 --region 0x02e17700:0x02e17924 ^
  --region 0x12e17780:0x12e17800 C:\b\m2g\bin\bl2.axf
```

A pass names every segment it found:

```
bl2.axf        OK - 3 discrete OFS segment(s): 0x0100A100(4B), 0x0100A200(4B), 0x0100A280(4B)
PASS: OFS is in discrete per-word segments within the given region(s).
```

`--require-segments` makes a wrong-part argument set fail instead of printing `CLEAN`. The check
works for both toolchains.

Check two — the words hold the expected values. Dump by address; IAR renames the sections, so
`-j .option_setting_*` prints nothing.

```bat
rem  RA6M5
arm-none-eabi-objdump -s --start-address=0x0100a100 --stop-address=0x0100a2d0 bl2.axf

rem  RA8M2
arm-none-eabi-objdump -s --start-address=0x02c9f040 --stop-address=0x02c9f280 bl2.axf
```

`objdump -s` prints bytes in memory order, so each word reads reversed from its register
value. Both toolchains produce these bytes:

| Part | Address | Word | Bytes as dumped |
|---|---|---|---|
| RA6M5 | `0x0100A100` | OFS0 | `ffffffff` |
| RA6M5 | `0x0100A200` | OFS1_SEC | `fffdffff` |
| RA6M5 | `0x0100A280` | OFS1_SEL | `f8f8ffff` |
| RA8M2 | `0x02C9F040` | OFS0 | `ffffffff` |
| RA8M2 | `0x02C9F044` | OFS2 | `efffffff` |
| RA8M2 | `0x02C9F0C0` | OFS1_SEC | `fffffffd` |
| RA8M2 | `0x02C9F0C4` | OFS3_SEC | `ffffffff` |
| RA8M2 | `0x02C9F120` | OFS1_SEL | `00000000` |
| RA8M2 | `0x02C9F124` | OFS3_SEL | `00000000` |

Optional, on an unfamiliar board: `-D<PART>_BL2_HALT_AT_MAIN=ON` stops BL2 at `main()` (the image
does not boot) so you can read `DLMMON` — `0x400E002C` on RA6M5, `0x40204038` on RA8M2.
Reading the other part's address returns an unrelated register rather than an error.
`FAWMON`/`FSPR` are not implemented on these parts.

### Seeing the output

Console output goes over SEGGER RTT, not a UART. Each image has its own control block and
**the address moves on every rebuild**, so read it rather than reusing a remembered value:

```bat
arm-none-eabi-nm C:\b\m2gns\bin\tfm_ns.axf | findstr " _SEGGER_RTT$"
```

Point J-Link RTT Viewer at that address.

BL2's log: the secure image wipes BL2's control block at chainload, so set a breakpoint in BL2,
attach the viewer at BL2's address while halted, then run.

### What a good run looks like

RA8M2; RA6M5 prints a chainload offset of `0xa0000`.

```
[INF] Starting bootloader
[INF] Bootloader chainload address offset: 0x68000
[INF] Image version: v2.2.0
Booting TF-M v2.2.0+...
[Sec Thread] Secure image initializing!
TF-M isolation level is: 0x00000001
[INF][Crypto] Init HW accelerator... complete.
Non-Secure system starting...
```

---

## 7. Test-suite builds

Test builds use profile_large, isolation 3 and IPC, so they have their own scripts and trees:

```bat
rem  PSA Arch: one secure image, one NS app per suite. Third argument = part (default ra6m5).
scripts\psa_arch_spe.bat  C:\b\m2cry   CRYPTO ra8m2
scripts\psa_arch_ns.bat   C:\b\m2cryns C:\b\m2cry\api_ns CRYPTO

rem  Regression (tf-m-tests). Fourth argument = IRQ suite.
scripts\reg_build_iar.bat C:\b\m2iflih C:\b\m2iflihns ra8m2 flih
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE`, `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`. `psa_arch_ns.bat` loads the Visual Studio environment itself
(`MSVC_VARS`); use `scripts\vs_build.bat <dir>` only to rebuild an existing PSA Arch tree by
hand.

Full detail, build-tree naming and the RTT guidance: [scripts/README.md](scripts/README.md).

---

## 8. When it does not work

[TROUBLESHOOTING.md](TROUBLESHOOTING.md) is indexed by symptom. The ones most likely to hit you
on a first build:

| Symptom | Cause |
|---|---|
| `bsp_linker_info.h: No such file` | §4 — the e2 solution was not built |
| `Filename too long` on `3rdparty/everest/...` | build directory path too deep; use `C:\b\` |
| `C1083: stdio.h` in a PSA Arch build | Visual Studio environment not found: set `MSVC_VARS` (§2) |
| `INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND ... _SILENCE` | non-Debug build with SPM trace on: pass `-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG` or `-DTFM_SPM_DEBUG_TRACE=OFF` ([CONFIGURATION.md](CONFIGURATION.md)) |
| Nothing on RTT | wrong control-block address (it moves every build), or BL2 — see §6 |
| `region CODE_RAM overflowed` | RA6M5 only: raise `S_RAM_CODE_SIZE` ([CONFIGURATION.md](CONFIGURATION.md) §7) |

---

## 9. Where to go next

Read [DESIGN.md](DESIGN.md) §1, then [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).
[README.md](README.md) §"The documents" maps every other document to the task it serves.
