# PSA Arch test builds for RA6M5

How the PSA Arch suites are built and flashed on RA6M5, for both toolchains. Results and the
reasoning behind the arrangement are in `DECISIONS.md` D046; the layout and board settings are
in `RA6M5_SOLUTION.md`.

## Two configurations, on purpose

| | PSA Arch suites | User application |
|---|---|---|
| NS side | the test suite itself | the port's `ns_app` |
| Profile | profile_large | default |
| Isolation | 3 | 1 |
| SPM backend | IPC | SFN |
| SPM trace | off (required at L3 + IPC) | on |
| Build type | MinSizeRel (NS) | Debug |

The suites need the larger profile and the stricter isolation; the application build is the
one to debug in. `psa_arch_*.bat` build the first, `app_build_iar.bat` the second.

## The arrangement

One SPE per toolchain serves all three suites — profile_large enables crypto, ITS, PS,
attestation and platform, which is everything the suites need — and each suite gets its own
non-secure app.

| | SPE | NS crypto | NS attestation | NS storage |
|---|---|---|---|---|
| GCC | `C:\b\m5cry` | `C:\b\m5cryns` | `C:\b\m5att` | `C:\b\m5sto` |
| IAR | `C:\b\m5icry` | `C:\b\m5icryns` | `C:\b\m5iatt` | `C:\b\m5isto` |

Short build paths on purpose: the full ones overrun Windows' path limit partway through the
build, and the failure is a confusing missing-file error rather than a length complaint.

## Building

```bat
scripts\psa_arch_spe.bat      C:\b\m5cry  CRYPTO
scripts\psa_arch_ns.bat       C:\b\m5att  C:\b\m5cry\api_ns  INITIAL_ATTESTATION

scripts\psa_arch_spe_iar.bat  C:\b\m5icry CRYPTO
scripts\psa_arch_ns.bat       C:\b\m5isto C:\b\m5icry\api_ns STORAGE iar
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE` (runs ITS and PS), `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`.

Rebuild the SPE before the NS apps whenever the secure side changes: the NS build links against
the interface the SPE installs into `api_ns\`.

Toolchain and repository locations are variables at the top of each script; set them in the
environment to override.

## Launches

```bat
python scripts\make_psa_arch_launch.py ra6m5_TFM_test_storage_gcc C:\b\m5cry C:\b\m5sto
```

Writes `<name>.launch` and `<name>.jlink` into `ra6m5_gcc_nonsecure/`, which is the e2 project
the launches attach to for both toolchains. The six current ones are committed.

Launch names carry the toolchain: `_gcc` or `_iar`. `swCrypto` is the software-crypto
comparison build (`CRYPTO_HW_ACCELERATOR=OFF`); `sce9` is the accelerated one.


## RTT

Each image has its own control block, and the address differs per build — read it from the map
rather than reusing a remembered value:

```sh
grep _SEGGER_RTT <build>/bin/tfm_ns.map
```

BL2 and the secure image share their blocks across the suites of one toolchain, since the SPE
is shared. BL2's block sits in SRAM the secure image later reuses, so watch it during boot and
reconnect afterwards.

The test builds set `RA6M5_RTT_BLOCKING=ON`, which makes RTT wait for the host instead of
dropping writes when its buffer fills. Without it a suite out-runs the host's polling and whole
tests disappear from the transcript while the run itself is fine. It is off by default in the
port because with no viewer attached the first write past 4 KB blocks forever.
