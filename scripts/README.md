# Test builds and debug launches — RA6M5 and RA8M2

How the test images are built and flashed, for both toolchains and both parts. Reasoning is in
`DECISIONS.md` (D046 for the arrangement, D084 for why the options are stated rather than
defaulted, D101 for the RA8M2 IAR project parity); layouts and board settings are in
`RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md`.

## Environment variables

Every variable below is read as `if "%VAR%"=="" set VAR=<default>`, so setting it in the
environment overrides the default and setting nothing uses it.

The four repository roots default to a side-by-side layout, resolved from the script's own
location rather than written as absolute paths. With the repositories cloned as siblings no
variable has to be set at all.

| Variable | Default | What it is |
|---|---|---|
| `TFM_SRC` | `<parent of this repository>\trusted-firmware-m` | the TF-M fork carrying the RA platform ports |
| `FSP_CMAKE` | this repository, located from the script itself | its directory may be named anything. Forward slashes, because it reaches CMake |
| `TFM_TESTS` | `<parent of this repository>\tf-m-tests` | `tf-m-tests`, for the regression and PSA Arch non-secure builds |
| `PSA_TESTS` | `<parent of this repository>\psa-arch-tests` | `psa-arch-tests`, for the PSA Arch suites |
| `GCC_BIN` | per script | the GNUARM `bin` directory |
| `IAR_BIN` | per script | the IAR `arm\bin` directory |
| `VS_VCVARS` / `MSVC_VARS` | per script | `vcvars64.bat`, needed only by the PSA Arch builds, which compile a host tool with `cl.exe` |

So a layout like this needs nothing set:

```
<anywhere>\
  ra_fsp_cmake_tfm\
  trusted-firmware-m\
  tf-m-tests\
  psa-arch-tests\
```

and a different layout needs only the roots that moved:

```
set TFM_SRC=D:\src\trusted-firmware-m
set TFM_TESTS=D:\src\tf-m-tests
```

The toolchain variables have no sensible default and will need setting on any machine but the
one these scripts were written on. `GETTING_STARTED.md` §2 is the authority for which tool
versions the port is built and tested with.

## Three configurations, on purpose

| | PSA Arch suites | Regression suites | User application |
|---|---|---|---|
| NS side | the PSA Arch suite | tf-m-tests `tests_reg` | the port's `ns_app` |
| Profile | profile_large | default | default |
| Isolation | 3 | 1 | 1 |
| SPM backend | IPC | SFN | SFN |
| `TFM_SPM_DEBUG_TRACE` | off — passed explicitly | on (platform default) | on (platform default) |
| `TFM_SPM_LOG_LEVEL` | `_DEBUG`, passed | `_DEBUG`, passed | `_DEBUG` passed (GCC); from `Debug` (IAR) |
| `TFM_PARTITION_LOG_LEVEL` | `_INFO`, passed | build-type default | build-type default |
| `CONFIG_TFM_HALT_ON_CORE_PANIC` | `ON`, passed | default | default |
| Build type | MinSizeRel | MinSizeRel, both toolchains | MinSizeRel (GCC) / Debug (IAR) |

Line references: `psa_arch_spe.bat:67-71` (and `psa_arch_spe_iar.bat:77-81`),
`reg_build_gcc.bat:145,158-159`, `reg_build_iar.bat:89,103-104`,
`app_build_ra8m2_gcc.bat:45,54`, `app_build_ra8m2_iar.bat:45`.

Why `TFM_SPM_LOG_LEVEL` is passed at all. Not a trace requirement — a *log-level* one.
Both platform configs set `TFM_SPM_DEBUG_TRACE=ON`, and `MinSizeRel` sets `TFM_SPM_LOG_LEVEL`
to `_SILENCE` (`config/build_type/minsizerel.cmake:9`). `check_config.cmake:119` rejects that
pair outright:

```
INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND TFM_SPM_LOG_LEVEL = TFM_SPM_LOG_LEVEL_SILENCE
```

so every MinSizeRel script passes `_DEBUG` to get past configure. `-DTFM_SPM_DEBUG_TRACE=OFF`
is the other way out of the same conflict, and is what the PSA Arch scripts do. The
constraint has nothing to do with isolation 3 or the IPC backend — the comment heads in
`psa_arch_spe*.bat` that say otherwise are wrong on the reason, right on the action.

Secure-side logging is the one setting that cannot be shared. The three options together — SPM
log, partition log and halt-on-panic — cost ~3,785 B of secure text, so they are set per script
rather than in the platform `config.cmake`. That is a diagnostics decision, not a space one:
both parts have tens of kilobytes of secure-region spare
([CONFIGURATION.md](../CONFIGURATION.md) §6). MinSizeRel is mandatory on
RA8M2 under GNUARM (IAR `Debug` fits, [D055]): `Debug` is ~414 KB against a secure code region
of 293,376 B ([CONFIGURATION.md](../CONFIGURATION.md) §6 defines the region and the two larger
figures that circulate for it).

## Build trees

One SPE serves all three PSA Arch suites — profile_large enables crypto, ITS, PS, attestation
and platform — and each suite gets its own NS app. The regression SPE is separate because its
configuration differs in every row of the table above.

| | PSA SPE | NS crypto | NS attest | NS storage | Reg SPE | Reg NS |
|---|---|---|---|---|---|---|
| RA6M5 GCC | `m5cry` | `m5cryns` | `m5att` | `m5sto` | `m5gflih` | `m5gflihns` |
| RA6M5 IAR | `m5icry` | `m5icryns` | `m5iatt` | `m5isto` | `m5iflih` | `m5iflihns` |
| RA8M2 GCC | `m2cry` | `m2cryns` | `m2att` | `m2sto` | `m2gflih` | `m2gflihns` |
| RA8M2 IAR | `m2icry` | `m2icryns` | `m2iatt` | `m2isto` | `m2iflih` | `m2iflihns` |

The application chain has defaults of its own, each chosen to match the launch that flashes
that pair:

| | Secure | Non-secure |
|---|---|---|
| RA6M5 GCC | `m5g` | `m5gns` |
| RA6M5 IAR | `m5i` | `m5ins` |
| RA8M2 GCC | `m2g` | `m2gns` |
| RA8M2 IAR | `m2app` | `m2appns` |

Every tree above is under `C:\b\`. Short paths on purpose: a deep one overruns Windows'
path limit partway through the Mbed TLS overlay clone, and reports `Filename too long` on
`3rdparty/everest/...` rather than anything about length. **A launch names every image by
absolute path**, so a default derived from the clone location would only ever match the
machine it was written on.

## Building

```bat
rem  PSA Arch. Third argument selects the part; omitted means ra6m5.
scripts\psa_arch_spe.bat      C:\b\m2cry   CRYPTO ra8m2
scripts\psa_arch_spe_iar.bat  C:\b\m2icry  CRYPTO ra8m2
scripts\psa_arch_ns.bat       C:\b\m2iatt  C:\b\m2icry\api_ns INITIAL_ATTESTATION iar

rem  Regression. Fourth argument picks the IRQ suite: flih (default), slih, or none —
rem  they are mutually exclusive in tf-m-tests.
scripts\reg_build_iar.bat     C:\b\m2iflih C:\b\m2iflihns ra8m2 flih

rem  Application chain. Run these bare to use the defaults, which are the trees the matching
rem  launch in GETTING_STARTED.md §6 flashes.
scripts\app_build_ra6m5_gcc.bat
scripts\app_build_iar.bat
scripts\app_build_ra8m2_gcc.bat
scripts\app_build_ra8m2_iar.bat
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE` (runs ITS and PS), `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`.

Rebuild the SPE before the NS apps whenever the secure side changes — the NS build links
against the interface the SPE installs into `api_ns\`. Regenerating an FSP project in RASC
counts as the secure side changing, and a stale tree carries the old generated values with no
diagnostic.

Toolchain and repository locations are variables at the top of each script; set them in the
environment to override.

## The MCUboot upgrade test

```bat
python scripts\sign_secondary.py C:\b\m2iflih\build-spe C:\b\m2iflihns
```

Re-signs both images at a bumped version into `*_signed_secondary.bin` beside the primaries.
It recovers the exact command the build used out of `build.ninja` and changes only the version
and the output name, so the key, alignment, header size and measured-boot record cannot drift
from the primary. Run it after every rebuild — the secondary must match the primary in
everything but version. The `*_TFM_update_*` launches add the two secondary slots as extra
download rows. Expected behaviour and the reverse slot order are in D100.

## Launches

```bat
rem  RA6M5, from scratch
python scripts\make_psa_arch_launch.py ra6m5_TFM_test_storage_gcc C:\b\m5cry C:\b\m5sto

rem  RA8M2 IAR, derived from the known-good GCC launches
python scripts\mk_iar_launches.py --check
python scripts\mk_iar_launches.py
```

The launch files live in `ra6m5_gcc_nonsecure/` (RA6M5) and `ra8m2_gcc_mcuboot/` (RA8M2).
Names carry the toolchain: `_gcc` or `_iar`.

Generate the IAR launches from their GCC twins with `mk_iar_launches.py --check`, then
without `--check`. It refuses to write a launch that still names a GCC tree or the GCC
project, or that sets `setTZBoundaries` true anywhere. What it rewrites, and why the two
parts use different host projects, is in [../MAINTAINERS.md](../MAINTAINERS.md).

Two attributes are safety-critical in every launch:

- `setTZBoundaries` = **false**. The debugger writing the TrustZone boundaries is a brick
  hazard (`DESIGN.md` §7.2). RA8M2 launches carry the key twice — `...arm.jlink.` and
  `...arm.e2lite.` — and e2 defaults the e2lite one to `true`. Only the namespace matching the
  selected probe is read, so the J-Link launches here are safe, but set both.
- `ueraseRomOnDownload` and `ueraseDataRomOnDownload` = 1. Otherwise a stale ITS/PS area
  survives a reflash and the storage suites fail in ways that look like code faults.

**Flash `bl2.elf`, `bl2.hex` or `bl2.srec` — never `bl2.bin`.** The option words land at their link addresses only in a format
that carries them one record at a time.

## RTT

Each image has its own control block and the address moves on every rebuild, so read it rather
than reusing a remembered value:

```sh
arm-none-eabi-nm <build>/bin/tfm_ns.axf | grep ' _SEGGER_RTT$'
```

BL2's block cannot be recovered after the chainload. `region_defs.h` gives BL2 and the SPE the
same RAM, so the SPE's `.bss` zeroing wipes BL2's control block microseconds after the jump, and a
viewer that auto-detects after reset always finds the SPE's. To capture BL2, halt in it first with
a breakpoint, point the viewer at BL2's address while halted, then run.
`RA8M2_BL2_HALT_AT_MAIN=ON` does not work for this: it is an unconditional `while(1)` at the top
of `main()` (`bl2_main.c:112-125`), before any init or print, so "then run" just spins and the
image is not bootable. D100's wording is the source of that error.

The test builds set `RA6M5_RTT_BLOCKING` / `RA8M2_RTT_BLOCKING` = ON, which makes RTT wait for
the host instead of dropping writes when its buffer fills. Without it a suite out-runs the
host's polling and whole tests vanish from the transcript while the run itself is fine. Off by
default in the port, because with no viewer attached the first write past 4 KB blocks forever.
