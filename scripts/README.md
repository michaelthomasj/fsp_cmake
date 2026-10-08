# Test builds and debug launches — RA6M5 and RA8M2

How the test images are built and flashed, for both toolchains and both parts. Reasoning is in
`DECISIONS.md` (D046 for the arrangement, D084 for why the options are stated rather than
defaulted, D101 for the RA8M2 IAR project parity); layouts and board settings are in
`RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md`.

## Three configurations, on purpose

| | PSA Arch suites | Regression suites | User application |
|---|---|---|---|
| NS side | the PSA Arch suite | tf-m-tests `tests_reg` | the port's `ns_app` |
| Profile | profile_large | default | default |
| Isolation | 3 | 1 | 1 |
| SPM backend | IPC | SFN | SFN |
| SPM trace | off (required at L3 + IPC) | on | on |
| Build type | MinSizeRel | MinSizeRel | Debug |
| Secure-side logging | on | **off** | on |

Secure-side logging is the one that cannot be shared. It costs ~3,785 B, and the regression
secure image has 960 B spare on RA8M2 — so it is set per script, not in the platform
`config.cmake`. **MinSizeRel is mandatory on RA8M2**: `Debug` is ~414 KB against a 293 KB
slot (D059).

## Build trees

One SPE serves all three PSA Arch suites — profile_large enables crypto, ITS, PS, attestation
and platform — and each suite gets its own NS app. The regression SPE is separate because its
configuration differs in every row of the table above.

| | PSA SPE | NS crypto | NS attest | NS storage | Reg SPE | Reg NS |
|---|---|---|---|---|---|---|
| RA6M5 GCC | `m5cry` | `m5cryns` | `m5att` | `m5sto` | — | — |
| RA6M5 IAR | `m5icry` | `m5icryns` | `m5iatt` | `m5isto` | — | — |
| RA8M2 GCC | `m2cry` | `m2cryns` | `m2att` | `m2sto` | `m2gflih` | `m2gflihns` |
| RA8M2 IAR | `m2icry` | `m2icryns` | `m2iatt` | `m2isto` | `m2iflih` | `m2iflihns` |

All under `C:\b\`. Short paths on purpose: a deep one overruns Windows' path limit partway
through the Mbed TLS overlay clone, and reports `Filename too long` on
`3rdparty/everest/...` rather than anything about length.

## Building

```bat
rem  PSA Arch. Third argument selects the part; omitted means ra6m5.
scripts\psa_arch_spe.bat      C:\b\m2cry   CRYPTO ra8m2
scripts\psa_arch_spe_iar.bat  C:\b\m2icry  CRYPTO ra8m2
scripts\psa_arch_ns.bat       C:\b\m2iatt  C:\b\m2icry\api_ns INITIAL_ATTESTATION iar

rem  Regression. Fourth argument picks the IRQ suite: flih (default), slih, or none —
rem  they are mutually exclusive in tf-m-tests.
scripts\reg_build_iar.bat     C:\b\m2iflih C:\b\m2iflihns ra8m2 flih

rem  Application chain.
scripts\app_build_ra8m2_gcc.bat C:\b\m2app  C:\b\m2appns
scripts\app_build_ra8m2_iar.bat C:\b\m2iapp C:\b\m2iappns
```

Suites: `CRYPTO`, `INITIAL_ATTESTATION`, `STORAGE` (runs ITS and PS), `PROTECTED_STORAGE`,
`INTERNAL_TRUSTED_STORAGE`.

Rebuild the SPE before the NS apps whenever the secure side changes — the NS build links
against the interface the SPE installs into `api_ns\`. **Regenerating an FSP project in RASC
counts as the secure side changing**, and a stale tree carries the old generated values with no
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

RA6M5 launches live in `ra6m5_gcc_nonsecure/`, RA8M2's in `ra8m2_gcc_mcuboot/` — **both
toolchains' launches share one host project**, because a launch only downloads prebuilt images
and the hosting project is incidental. Names carry the toolchain: `_gcc` or `_iar`.

`mk_iar_launches.py` derives each IAR launch from its GCC twin by swapping build-tree names;
nothing else differs, verified against the RA6M5 pair. It refuses to write a launch that still
names a GCC tree or that has `setTZBoundaries` true anywhere.

**Two attributes are safety-critical in every launch:**

- `setTZBoundaries` = **false**. The debugger writing the TrustZone boundaries is a brick
  hazard (`DESIGN.md` §7.2). RA8M2 launches carry the key **twice** — `...arm.jlink.` and
  `...arm.e2lite.` — and e2 defaults the e2lite one to `true`. Only the namespace matching the
  selected probe is read, so the J-Link launches here are safe, but set both.
- `ueraseRomOnDownload` and `ueraseDataRomOnDownload` = **1**. Otherwise a stale ITS/PS area
  survives a reflash and the storage suites fail in ways that look like code faults.

Flash `bl2.elf` or `bl2.hex`, **never `bl2.bin`** — the OFS words land at their link addresses
only in a format that carries them.

## RTT

Each image has its own control block and the address moves on every rebuild, so read it rather
than reusing a remembered value:

```sh
arm-none-eabi-nm <build>/bin/tfm_ns.axf | grep ' _SEGGER_RTT$'
```

**BL2's block cannot be recovered after the chainload.** `region_defs.h` gives BL2 and the SPE
the same RAM, so the SPE's `.bss` zeroing wipes BL2's control block microseconds after the
jump, and a viewer that auto-detects after reset always finds the SPE's. To capture BL2, halt
in it first (`RA8M2_BL2_HALT_AT_MAIN=ON`, or a breakpoint), point the viewer at BL2's address
while halted, then run. D100.

The test builds set `RA6M5_RTT_BLOCKING` / `RA8M2_RTT_BLOCKING` = ON, which makes RTT wait for
the host instead of dropping writes when its buffer fills. Without it a suite out-runs the
host's polling and whole tests vanish from the transcript while the run itself is fine. Off by
default in the port, because with no viewer attached the first write past 4 KB blocks forever.
