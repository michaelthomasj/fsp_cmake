# Adding an FSP module to the TF-M build

For a driver enabled in e2 that the secure image or BL2 must compile and link. Enabling it in
RASC is a prerequisite.

---

## 1. The model

**Secure image and BL2: drivers are opt-in.** A driver reaches them only if a
`cmake/modules/fsp_<name>.cmake` declares it and the platform lists it in `FSP_MODULES_S` or
`FSP_MODULES_BL2`; it builds once per role (`fsp_<name>_s`, `fsp_<name>_bl2`). The build warns
about drivers enabled in e2 but not declared (§5).

**Non-secure image: nothing to do.** It builds every module its project enables (§2).

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

Three separate mechanisms are easy to confuse here:

| Mechanism | Where | Effect |
|---|---|---|
| `FSP_MODULES_S` / `_BL2` | `ra6m5/CMakeLists.txt:234`, `:238` | the only thing that builds FSP sources for the secure and BL2 images |
| `FSP_MODULES_NEVER_BUILT` | `:266` | suppresses the §5 unclaimed-directory warning; excludes no source |
| `FSP_EXCLUDED_MODULES` | `:112`, used by `fsp_collect_sources()` at `:1023` | **reaches nothing in a normal build.** Its only caller is guarded on `<PART>_NS_IN_SPE_BUILD`, which is `OFF` by default |

The non-secure image takes its FSP sources from `platform_ns`, which globs `bsp`, `r_*`, `rm_*`
and `ra_gen` and removes only `ra_gen/main.c`; `--gc-sections` drops what is unreferenced.
`r_sce` is listed in `FSP_MODULES_NEVER_BUILT` for the BL2-without-accelerator role, which
declares no `sce` module. Why `rm_psa_crypto` and `rm_mcuboot_port` are excluded:
[BUILD_ARCHITECTURE.md](BUILD_ARCHITECTURE.md) §4.

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

Four obligations:

| | |
|---|---|
| `fsp_module_library(<OUT_VAR> <base>)` | Never `add_library()` directly. The macro applies the include paths, `FSP_COMPILE_DEFS`, the TrustZone defines and the FP/ABI flag — see §4. |
| `fsp_module_glob(<out> <subdir>)` | Glob within a declared module. The module is opt-in; naming each generated `.c` inside it would drift on every FSP bump. |
| A `FATAL_ERROR` when the glob is empty | The driver is not in the project. Say so and name the RASC step that fixes it. |
| Link `fsp_bsp_${FSP_MODULE_ROLE}` | Every module needs the BSP, and the role suffix is not optional — `fsp_bsp` alone does not exist. |

Set `FSP_MODULE_DIRS_<base>` if the module claims directories beyond the one it globs; §5 uses it.

---

## 4. Why `fsp_module_library()` and not `add_library()`

The macro applies the per-role FP/ABI flag (`COMPILER_CP_FLAG`; `BL2_COMPILER_CP_FLAG` for the
soft-float BL2) and `COMPILER_CMSE_FLAG`. Without it, IAR on Cortex-M85 refuses the link
(`Error[Lt006]: Incompatible object(s) ... use VFP instructions incompatible with No vfp`); on
Cortex-M33 it links silently.

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

---

## 6. Procedure

1. Enable the driver in the project for the role: the secure project, or
   `<part>_<toolchain>_mcuboot` for BL2. Interrupt-driven peripherals need a real Interrupt
   Priority, which also makes the interrupt secure.
2. Regenerate and build that project ([GETTING_STARTED.md](GETTING_STARTED.md) §4).
3. Write `cmake/modules/fsp_<base>.cmake` (§3).
4. Add `<base>` to `FSP_MODULES_S` / `FSP_MODULES_BL2`.
5. Reconfigure TF-M and check for the §5 warning.
6. Repeat for each part: module files are per-part copies, and nothing detects drift between
   them.

---

## 7. Using an FSP driver from a secure partition

At isolation 1 (the shipped default), and in PSA RoT partitions at any level, FSP drivers work
unmodified. An Application RoT partition at isolation 2 or 3 runs unprivileged, and three things
a driver call touches are then out of reach:

| What | Where it lands | Fault |
|---|---|---|
| driver code in `platform_s` | `PT_PSA_ROT_CODE`, privileged | IACCVIOL (`MMFSR` 0x01) |
| the control block in `ra_gen/hal_data.c` | `PT_PSA_ROT_DATA`, privileged | DACCVIOL (`MMFSR` 0x82) |
| the NVIC, written by `R_XXX_Open()` | PPB, privileged by architecture | BusFault; no MPU region can grant it |

The simplest answer is to drive the peripheral from a PSA RoT partition. If an ARoT partition
must drive it:

1. Declare the register block as an `mmio_region` in the manifest and add a matching
   `platform_data_t` to `tfm_peripherals_def.c`, using the secure alias.
2. Declare the interrupt as `irqs` in the manifest; use `psa_irq_enable()` / `psa_irq_disable()`,
   never `NVIC_*`.
3. Call `R_XXX_Open()` from privileged init, the `<irq>_init` hook the manifest tooling
   generates.
4. Declare the control block inside the partition, not in `ra_gen/`.
5. Compile the driver's operational sources into `tfm_sprt`, with the include path scoped to
   those files. Code in `tfm_sprt` must be stateless: its `.bss` lands in `PT_PSA_ROT_DATA`, so a
   `static` faults when read from an ARoT partition.

**FLIH handlers.** At isolation 1, and for PSA RoT partitions, `flih_func()` runs privileged in
Handler mode. For an ARoT partition at isolation 2 or 3 it runs in Thread mode at the partition's
privilege, so it may touch only its own `mmio_region`. Clear the ICU `IELSR.IR` latch and the
NVIC pending bit in the platform's vector entry before `spm_handle_interrupt()`, and the
peripheral's own flag in the partition handler, in that order.

---

## 8. Traps

| Trap | Symptom |
|---|---|
| Driver added in RASC, no module file | the §5 warning, then an undefined symbol at link |
| Module file written, not listed in `FSP_MODULES_*` | nothing happens at all — the file is never included |
| `add_library()` instead of `fsp_module_library()` | `Error[Lt006]` on Cortex-M85, silence on M33 |
| `fsp_bsp` instead of `fsp_bsp_${FSP_MODULE_ROLE}` | CMake cannot find the target |
| Added to the secure project, needed by BL2 | BL2's glob is empty — hence the `FATAL_ERROR` in §3 |
| Added to one part only | builds on that part, breaks on the other, nothing warns |
| FSP driver called from an Application RoT partition | works at isolation 1, `MMFSR` 0x01 or 0x82 from isolation 2 — see §7 |
| `static` in a file compiled into `tfm_sprt` | the `.bss` lands in `PT_PSA_ROT_DATA`; unprivileged reads fault (§7) |
| Generated file links for a symbol you do not use | intended, sometimes. `vector_data.o` is linked for its ICU event-link table, which drags in `agt_int_isr()` — see the comment in `fsp_agt.cmake` |

---

## 9. See also

[GETTING_STARTED.md](GETTING_STARTED.md), [DESIGN.md](DESIGN.md) §1,
[FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md).
