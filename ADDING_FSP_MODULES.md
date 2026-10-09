# Adding an FSP module to the TF-M build

**Audience:** someone who has enabled a driver in the e2 project and now needs TF-M to compile
and link it.
**Scope:** the CMake side only. Enabling the module in RASC is a prerequisite, not covered here.

> **Provenance.** This replaces `archive/ra6m4/TFM_INTEGRATION_COMPLETE.md` §"Adding New FSP
> Modules", which describes the superseded RA6M4 arrangement (`FSP_Project_ra6m4`,
> `GeneratedSrc_Modular.cmake`, an `fsp_uart` module) and matches nothing in the live ports.
> Nineteen source files pointed at `fsp_cmake/TFM_INTEGRATION_COMPLETE.md`, a path that does not
> exist; they now point here.

---

## 1. The model, in one paragraph

FSP drivers are **opt-in, per role**. Nothing from `ra/fsp/src/` reaches an image unless a
`cmake/modules/fsp_<name>.cmake` declares it *and* the platform lists it in `FSP_MODULES_S` or
`FSP_MODULES_BL2`. The secure image and the bootloader come from **different e2 projects**, so
each module builds twice under distinct target names — `fsp_bsp_s` and `fsp_bsp_bl2` — which also
stops the two images' FSP configurations leaking into each other.

The deliberate consequence: **adding a driver in RASC does not add it to TF-M.** The build warns
when that happens (§5).

---

## 2. Where everything lives

```
platform/ext/target/renesas/<part>/
    CMakeLists.txt                      FSP_MODULES_S / FSP_MODULES_BL2, fsp_add_modules()
    cmake/modules/
        fsp_module_common.cmake         the shared scaffolding — read this first
        fsp_bsp.cmake                   BSP, startup, clocks, IOPORT
        fsp_flash.cmake                 code/data flash, behind CMSIS Driver_Flash
        fsp_sce.cmake                   the crypto engine
        fsp_agt.cmake                   the timer — the best worked example
```

Current module sets on RA8M2:

```cmake
set(FSP_MODULES_S    bsp flash sce agt)
set(FSP_MODULES_BL2  bsp flash)            # + sce when BL2 needs crypto
set(FSP_MODULES_NEVER_BUILT r_sce rm_psa_crypto rm_mcuboot_port)
```

`FSP_MODULES_NEVER_BUILT` is not a mistake list — it names directories the port deliberately
replaces. TF-M supplies its own MCUboot flash backend ([D091]) and its own crypto integration, so
FSP's `rm_mcuboot_port` and `rm_psa_crypto` must stay out of the link.

---

## 3. Writing the module file

A complete module is about ten lines. `fsp_agt.cmake` in full, minus its comments:

```cmake
fsp_module_library(FSP_AGT_TARGET agt)          # creates fsp_agt_<role>, applies common flags

fsp_module_glob(_src "ra/fsp/src/r_agt")        # globs the generated sources
if(NOT _src)
    message(FATAL_ERROR
        "RA8M2: the AGT module is not in ${FSP_MODULE_BASE_DIR}.\n"
        "The FLIH/SLIH interrupt suites need a secure timer. Add the Timer (r_agt) module "
        "to the SECURE project in e2 studio with a real Interrupt Priority - not Disabled, "
        "which is also what makes the interrupt secure on RA - regenerate, and build the "
        "project once. See DECISIONS D061.")
endif()

target_sources(${FSP_AGT_TARGET} PRIVATE ${_src})
target_link_libraries(${FSP_AGT_TARGET} PUBLIC fsp_bsp_${FSP_MODULE_ROLE})
```

Four obligations, and the third is the one people skip:

| | |
|---|---|
| **`fsp_module_library(<OUT_VAR> <base>)`** | Never `add_library()` directly. The macro applies the include paths, `FSP_COMPILE_DEFS`, the TrustZone defines **and the FP/ABI flag** — see §4. |
| **`fsp_module_glob(<out> <subdir>)`** | Glob *within* a declared module. The module is opt-in; naming each generated `.c` inside it would drift on every FSP bump. |
| **A `FATAL_ERROR` when the glob is empty** | The module is in the port but the driver is not in the project. Say so, name the RASC step, and cite the decision. [D089] records a case where a guard that named its own fix cost one log read against one that did not. |
| **Link `fsp_bsp_${FSP_MODULE_ROLE}`** | Every module needs the BSP, and the role suffix is not optional — `fsp_bsp` alone does not exist. |

Set `FSP_MODULE_DIRS_<base>` if the module claims directories beyond the one it globs; §5 uses it.

---

## 4. Why `fsp_module_library()` and not `add_library()`

It applies the FP/ABI flag per role, and leaving it out produces a link failure that names
nothing useful:

```
Error[Lt006]: Incompatible object(s): system.o(libfsp_bsp_s.a) and 195 other objects
  ... use VFP instructions incompatible with No vfp (provided as FPU option)
```

TF-M applies `COMPILER_CP_FLAG` **per target**, not through `CMAKE_C_FLAGS`. Module libraries are
created in these files, so nothing else gives it to them and they compile with the compiler's
default FPU for the `-mcpu`/`--cpu` in use. On Cortex-M33 that is invisible — iccarm defaults to
no FPU, which matches the link. **On Cortex-M85 it defaults to a present FPU and the link is
refused.** BL2 uses `BL2_COMPILER_CP_FLAG` because TF-M builds the bootloader soft-float
regardless of the secure image.

The macro also adds `COMPILER_CMSE_FLAG`: every module here is linked into a secure-side image.

---

## 5. Register it, and the warning that catches you forgetting

```cmake
set(FSP_MODULES_S    bsp flash sce agt)        # add your <base> here
```

`fsp_add_modules()` then includes `cmake/modules/fsp_<base>.cmake` and creates
`fsp_<base>_<role>`. Afterwards it globs `ra/fsp/src/*` in the generated project and warns about
every directory no module claimed and that is not in `FSP_MODULES_NEVER_BUILT`:

```
RA8M2 [s]: FSP module 'r_adc' is in the project but no module declares it, so it is
NOT in the image. Add a cmake/modules/fsp_<name>.cmake and list it in FSP_MODULES_S
```

**Read it.** The alternative is discovering the omission as an undefined symbol much later, with
nothing connecting it to RASC.

---

## 6. Procedure

1. **Enable the driver in e2 studio**, in the project for the role that needs it — the *secure*
   project for the secure image, `<part>_mcuboot` for BL2. Interrupt-driven peripherals need a
   real Interrupt Priority, **not Disabled**: on RA that is also what makes the interrupt secure
   ([D061], [D101]).
2. **Regenerate and build the project once.** Building is not optional — the port reads
   `Debug/bsp_linker_info.h`, which only a build produces. See [GETTING_STARTED.md](GETTING_STARTED.md) §4.
3. **Write `cmake/modules/fsp_<base>.cmake`** per §3.
4. **Add `<base>` to `FSP_MODULES_S` / `FSP_MODULES_BL2`.**
5. **Rebuild TF-M** and check the configure output for the §5 warning naming a directory you
   expected to be claimed.
6. **Do the same for every active part** that needs it. The module files are per-part copies;
   RA6M5 and RA8M2 each have their own. They drift, and nothing detects it — [D089] is the worked
   example, where a fix applied to one part was recorded as done and the other was still broken.

---

## 7. Traps

| Trap | Symptom |
|---|---|
| Driver added in RASC, no module file | the §5 warning, then an undefined symbol at link |
| Module file written, not listed in `FSP_MODULES_*` | nothing happens at all — the file is never included |
| `add_library()` instead of `fsp_module_library()` | `Error[Lt006]` on Cortex-M85, silence on M33 |
| `fsp_bsp` instead of `fsp_bsp_${FSP_MODULE_ROLE}` | CMake cannot find the target |
| Added to the secure project, needed by BL2 | BL2's glob is empty — hence the `FATAL_ERROR` in §3 |
| Added to one part only | builds on that part, breaks on the other, nothing warns |
| Generated file links for a symbol you do not use | intended, sometimes. `vector_data.o` is linked for its ICU event-link table, which drags in `agt_int_isr()` — see the comment in `fsp_agt.cmake` |

---

## 8. See also

- [GETTING_STARTED.md](GETTING_STARTED.md) — the build itself
- [DESIGN.md](DESIGN.md) §1 — why the e2 projects are consumed rather than forked
- [BRIDGING_FILES.md](BRIDGING_FILES.md) — files that carry FSP code but do not move with it
- [DECISIONS.md](DECISIONS.md) — [D061] secure timer, [D089] per-part drift, [D091] why the MCUboot port is excluded
