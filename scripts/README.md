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
  fsp_cmake\
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
log, partition log and halt-on-panic — cost ~3,785 B against 670 B spare on RA8M2 ([D087];
the 960 B this line used to quote was the retracted figure), so they are set per script rather
than in the platform `config.cmake`. MinSizeRel is mandatory on
RA8M2 under GNUARM (IAR `Debug` fits, [D055]): `Debug` is ~414 KB against a 293 KB slot
([D057]).

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
| RA6M5 GCC | `trusted-firmware-m\build_ra6m5_sce9` | `trusted-firmware-m\build_ra6m5_sce9_ns` |
| RA6M5 IAR | `trusted-firmware-m\build_ra6m5_iar` | `trusted-firmware-m\build_ra6m5_iar_ns` |
| RA8M2 GCC | `m2g` | `m2gns` |
| RA8M2 IAR | `m2app` | `m2appns` |

The suite trees above and the RA8M2 application trees are all under `C:\b\`. Short paths on
purpose: a deep one overruns Windows' path limit partway through the Mbed TLS overlay clone,
and reports `Filename too long` on `3rdparty/everest/...` rather than anything about length.
The RA6M5 application pairs sit inside the TF-M clone, whose path is short enough to build in.

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

The host project in `PROJECT_ATTR` differs between the two parts, on purpose:

| | host project |
|---|---|
| RA6M5, both toolchains | `ra6m5_gcc_nonsecure` |
| RA8M2 GCC | `ra8m2_gcc_CPU0_nonsecure` |
| RA8M2 IAR | `ra8m2_iar_CPU0_nonsecure` |

`serverParam` builds the J-Link settings path from `${ProjName}`:

```
-uJLinkSetting= "${workspace_loc:/${ProjName}}/${LaunchConfigName}.jlink"
```

so hosting both toolchains in one project makes them share a directory for those sidecars. Giving
each toolchain its own host keeps them apart. Nothing is built either way —
`ATTR_BUILD_BEFORE_LAUNCH_ATTR` is `2`, which in Eclipse CDT is `USE_WORKSPACE_SETTING`, not
`DISABLED` (`0`) - so whether the host project is built depends on the workspace preference — so
the host project supplies only that name and the debug context. Keep `MAPPED_RESOURCE_PATHS` in
step with `PROJECT_ATTR`.

`PROJECT_BUILD_CONFIG_AUTO_ATTR` is `false` in every IAR launch, which is what all six
working RA6M5 IAR launches use. Only the RA8M2 GCC launches have `true`; every RA6M5 GCC
launch has `false`, so it cannot be inherited either way.

`mk_iar_launches.py` derives each IAR launch from its GCC twin by swapping build-tree names and
the three project attributes above, and rewriting `e2lite.setTZBoundaries` from `true` to
`false` - so that key differs too. It
refuses to write a launch that still names a GCC tree or the GCC project, or that has
`setTZBoundaries` true anywhere. Run `--check` first: it reports `same` when the generator
reproduces what is on disk, which is how a hand edit gets folded back in rather than lost.

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

## Documentation checks — maintainer tooling

```sh
python scripts/check_docs.py     # verify every D-citation and .md reference resolves
sh scripts/install_hooks.sh      # install it as a pre-commit hook (once per clone)
```

Checks nine things, in two groups. **References:** every `D###` cited anywhere exists in
`DECISIONS.md`; every relative `.md` link resolves; every `.md` filename named in a `.cmake` or
`CMakeLists.txt` comment resolves; a cited *section* exists in the document the citation names
(`FILE.md §6`, `FILE.md §"Some heading"`); and the course's links resolve, both within
`docs/learning/` and into the generated pages under `ref/`. **Customer readiness:** no local
user path; every link target tracked in git rather than merely present on disk; decision-ID
density under 15 per 1000 words; no launch setting `setTZBoundaries` true for any probe. Pass
`--no-customer` to skip the second group.

`DECISIONS.md` is exempt from the link checks because it is append-only - a reference there to
a since-retired file is a historical fact, not a defect.
Review snapshots under `docs/artifacts*/` are exempt from all three checks: they cite entries a
review proposes before anyone has written them.

Bypass with `git commit --no-verify` when a commit breaks a reference on purpose, such as the
first half of a rename spanning both repositories.

```sh
python scripts/check_arch_lines.py          # BUILD_ARCHITECTURE.md's line citations
python scripts/check_arch_lines.py --list   # show what each cited line holds
```

73 citations, each paired with a regex the cited line must match: the RA port `CMakeLists.txt`
and module files, upstream TF-M, and this repository's own build scripts. The table covers
`BUILD_ARCHITECTURE.md`'s citations only. Line citations in the other documents - `DESIGN.md`,
the solution documents, the course pages - are not checked, which is why `DESIGN.md` §8.4 cites
`ra6m5_add_ofs_check()` by function name rather than by line. `check_docs.py`
cannot catch this class: the file exists and the D-numbers resolve, so a reference stays
"valid" while pointing at the wrong line.

The port citations went stale twice in one day, both times from a comment edit above the
block with no CMake change. The table keeps them in two lists for that reason: `CITES` and
`PORT_PATHS` are port files and move with a port commit, `UPSTREAM` is TF-M's own code and
moves only on a TF-M uprev.

Fail-on-stale, not regenerate: the numbers sit in prose that explains each block, so a human
has to look. The pre-commit hook skips it when `trusted-firmware-m` is not beside this repo;
run by hand in that case it exits 2. `scripts/pre-commit-tfm` runs the same check from the
TF-M side, where the drift originates. Adding a citation to `BUILD_ARCHITECTURE.md` means
adding a row to the table in the script.

`install_hooks.sh` installs two hooks, not one: `scripts/pre-commit` into this repository and
`scripts/pre-commit-tfm` into `../trusted-firmware-m/.git/hooks/pre-commit`. An existing hook
is copied to `<name>.bak` first. It is safe to re-run, and it has to be re-run after either
hook script changes, because the hooks are copies rather than symlinks.

### Rendered documents for the course — maintainer tooling

```sh
python scripts/build_doc_html.py           # regenerate docs/learning/ref/ from the working tree
python scripts/build_doc_html.py --check   # exit 1 if ref/ is stale, orphaned, or the course links raw .md
```

The course in `docs/learning/` links to HTML renderings of every root `*.md` and this file, in
`docs/learning/ref/`. **The Markdown is the source; never edit `ref/*.html`.** That directory is
generated and is not committed: run the command above once per clone to make the course links
resolve, and again at packaging time. It also fails when a course page links a raw `.md` instead
of `ref/<NAME>.html`, which is worth running after editing the course.

- Stdlib only - a small renderer for the subset these documents use. Raw HTML in Markdown is
  escaped, not passed through.
- `[D113]` becomes a link to `DECISIONS.html#d113`; a numbered heading (`### 8.4 ...`) gets the
  id `s8-4`, so the course can link `DESIGN.html#s8-4` for "DESIGN.md §8.4". Renumbering a
  section therefore breaks inbound course links. `--check` here does not catch that;
  `check_docs.py` does, by computing the same anchors from the Markdown and resolving every
  course link against them.
- Output is deterministic, so `--check` is a byte comparison and diffs show only real changes.
- Adding or removing a document rewrites every page, because each sidebar lists them all.
- `--no-verify` skips the render too. Run the script by hand afterwards, or the next
  documentation commit will pick it up.

