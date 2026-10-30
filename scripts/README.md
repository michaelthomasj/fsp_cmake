# Test builds and debug launches — RA6M5 and RA8M2

Arguments, environment variables and build trees for every build script.

## Environment variables

Every variable is read as `if "%VAR%"=="" set VAR=<default>`. Repository roots default to sibling
clones, located from the script, so set one only if that root moved.

| Variable | Default | What it is |
|---|---|---|
| `TFM_SRC` | `<parent of this repository>\trusted-firmware-m` | the TF-M fork carrying the RA platform ports |
| `FSP_CMAKE` | this repository, located from the script itself | its directory may be named anything. Forward slashes, because it reaches CMake |
| `TFM_TESTS` | `<parent of this repository>\tf-m-tests` | `tf-m-tests`, for the regression and PSA Arch non-secure builds |
| `PSA_TESTS` | `<parent of this repository>\psa-arch-tests` | `psa-arch-tests`, for the PSA Arch suites |
| `GCC_BIN` | per script | the GNUARM `bin` directory |
| `IAR_BIN` | per script | the IAR `arm\bin` directory |
| `VS_VCVARS` / `MSVC_VARS` | per script | `vcvars64.bat`, needed only by the PSA Arch builds, which compile a host tool with `cl.exe` |

Example, for roots that moved:

```
set TFM_SRC=D:\src\trusted-firmware-m
```

The three toolchain variables must be set on every machine
([GETTING_STARTED.md](../GETTING_STARTED.md) §2).

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

Why the scripts pass `TFM_SPM_LOG_LEVEL`, why RA8M2 GNU must build `MinSizeRel`, and what the
logging options cost: [CONFIGURATION.md](../CONFIGURATION.md) §6 and §9.

## Build trees

One PSA Arch SPE serves all three suites; each suite has its own NS tree. The regression SPE is
separate.

| | PSA SPE | NS crypto | NS attest | NS storage | Reg SPE | Reg NS |
|---|---|---|---|---|---|---|
| RA6M5 GCC | `m5cry` | `m5cryns` | `m5att` | `m5sto` | `m5gflih` | `m5gflihns` |
| RA6M5 IAR | `m5icry` | `m5icryns` | `m5iatt` | `m5isto` | `m5iflih` | `m5iflihns` |
| RA8M2 GCC | `m2cry` | `m2cryns` | `m2att` | `m2sto` | `m2gflih` | `m2gflihns` |
| RA8M2 IAR | `m2icry` | `m2icryns` | `m2iatt` | `m2isto` | `m2iflih` | `m2iflihns` |

Application defaults (each matches its [GETTING_STARTED.md](../GETTING_STARTED.md) §6
launch): RA6M5 `m5g`/`m5gns` (GNU),
`m5i`/`m5ins` (IAR); RA8M2 `m2g`/`m2gns` (GNU), `m2app`/`m2appns` (IAR). All trees are under
`C:\b\`: short paths avoid `Filename too long`, and launches use absolute paths.

## Building

```bat
rem  PSA Arch. Third argument = part (default ra6m5).
scripts\psa_arch_spe.bat      C:\b\m2cry   CRYPTO ra8m2
scripts\psa_arch_spe_iar.bat  C:\b\m2icry  CRYPTO ra8m2
scripts\psa_arch_ns.bat       C:\b\m2iatt  C:\b\m2icry\api_ns INITIAL_ATTESTATION iar

rem  Regression: <spe> <ns> [part] [flih|slih|none] [level] [SFN|IPC]
scripts\reg_build_gcc.bat     C:\b\m2gflih C:\b\m2gflihns ra8m2 flih 1 SFN
scripts\reg_build_iar.bat     C:\b\m2iflih C:\b\m2iflihns ra8m2 flih

rem  Application chain; run bare for the defaults.
scripts\app_build_ra6m5_gcc.bat & scripts\app_build_iar.bat
scripts\app_build_ra8m2_gcc.bat & scripts\app_build_ra8m2_iar.bat

rem  Retarget a launch to other trees; rebuild a PSA Arch tree by hand
python scripts\mk_level_launch.py <launch> <old-spe> <old-ns> <new-spe> <new-ns> <new-name>
scripts\vs_build.bat <build-dir>
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE` (runs ITS and PS), `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`.

Rebuild the SPE before its NS trees whenever the secure side changes, including any RASC
regeneration; a stale `api_ns\` gives no diagnostic.

## The MCUboot upgrade test

```bat
python scripts\sign_secondary.py C:\b\m2iflih\build-spe C:\b\m2iflihns
```

Re-signs both images at a bumped version into `*_signed_secondary.bin`, reusing the build's exact
imgtool command. Run it after every rebuild; the `*_TFM_update_*` launches flash the secondaries.

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

Every launch keeps `setTZBoundaries` false and erase-on-download on; the rules are in
[GETTING_STARTED.md](../GETTING_STARTED.md) §6.

## RTT

Reading the RTT address and capturing BL2's log:
[GETTING_STARTED.md](../GETTING_STARTED.md) §"Seeing the output".

Test builds set `<PART>_RTT_BLOCKING=ON` so long transcripts are not dropped; leave it off
otherwise, because with no viewer attached output blocks once the 4 KB buffer fills.
