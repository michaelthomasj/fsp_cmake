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

`FSP_MODULES_NEVER_BUILT` excludes nothing. It names the directories the §5 audit should not
warn about, and that is its only effect ([D127]).

Three separate mechanisms are easy to confuse here:

| Mechanism | Where | Effect |
|---|---|---|
| `FSP_MODULES_S` / `_BL2` | `ra6m5/CMakeLists.txt:234`, `:238` | the only thing that **builds** FSP sources for the secure and BL2 images |
| `FSP_MODULES_NEVER_BUILT` | `:266` | suppresses the §5 unclaimed-directory warning; excludes no source |
| `FSP_EXCLUDED_MODULES` | `:112`, used by `fsp_collect_sources()` at `:1023` | filters sources out of the **non-secure** glob only |

So `r_sce` appears in `FSP_MODULES_NEVER_BUILT` yet is built by the `sce` module for the secure
and BL2 roles ([D129]). It is listed there for the BL2-without-accelerator role, which declares
no `sce` module and would otherwise trip the audit. `FSP_EXCLUDED_MODULES` removes it from the
non-secure image, which is a different build.

`rm_mcuboot_port` does stay out of the link: TF-M supplies its own MCUboot flash backend
([D091]). `rm_psa_crypto` is narrower — the port excludes FSP's PSA core module and its mbedTLS
config, while FSP's `*_ALT` sources still reach the image through
`platform/ext/accelerator/renesas/{sce9,rsip_e50d}` and its library through the
`fsp_mbedtls.cmake` overlay.

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

## 7. Using an FSP driver from a secure partition

Everything above puts driver code in `platform_s`. That is correct for the SPM and for
**PSA RoT** partitions, and if that is your case you can stop reading — FSP works unmodified
at every isolation level.

It is **not** correct for an **Application RoT** partition from isolation 2 onward, and the
failure is invisible at isolation 1, which is what this port ships.

### Why

From isolation 2 the SPM runs ARoT partitions **unprivileged** (`tfm_hal_bind_boundary()`
sets `privileged = IS_PSA_ROT(p_ldinf)`). Three things an FSP driver call normally touches are
then out of reach:

| What | Where it lands | Result |
|---|---|---|
| Driver code in `platform_s` | `PT_PSA_ROT_CODE`, marked `ARM_MPU_PRIVILEGED` | **IACCVIOL** on the branch (`MMFSR` 0x01) |
| The control block, e.g. `g_timer0_ctrl` | `ra_gen/hal_data.c` → `PT_PSA_ROT_DATA`, `ARM_MPU_PRIVILEGED` | **DACCVIOL** on first use (`MMFSR` 0x82) |
| The NVIC, written by `R_XXX_Open()` | PPB, `0xE000E000` | **BusFault**, and no MPU region can grant it |

The third is the one with no workaround. **Every interrupt-driven FSP driver configures the
NVIC inside `_Open()`** — `R_AGT_Open()` calls `R_BSP_IrqCfgEnable()`, and the pattern repeats
across the driver set (`r_spi` 12 call sites, `r_iic_master` 7, `r_sci_uart` 5, `r_canfd` 5,
`r_gpt`, `r_adc`, `r_dmac`). The PPB is privileged-only *by architecture*, not by MPU policy,
so `_Open()` can never be called from an unprivileged partition.

This is a genuine collision of models rather than an FSP defect. TF-M deliberately takes NVIC
ownership away from partitions: a partition declares `irqs` in its manifest, the SPM programs
the NVIC on its behalf, and the partition uses `psa_irq_enable()` / `psa_irq_disable()`, which
are SVCs into the SPM. FSP assumes the driver owns the interrupt controller. The two disagree
at `_Open()` and nowhere else — the operational calls are clean. `R_AGT_Start()` and
`R_AGT_Stop()` touch only `p_ctrl->p_reg->…`.

### The pattern that works

Split the driver's lifetime by privilege:

| Phase | Runs where | Why |
|---|---|---|
| `_Open()`, NVIC and ICU setup | privileged init — the SPM's partition-init hook | PPB is privileged-only |
| `_Start()`, `_Stop()`, operational calls | the partition, unprivileged | registers only |
| interrupt enable/disable | `psa_irq_enable()` / `psa_irq_disable()` | SVC into the SPM, which owns the NVIC |

Concretely, for a peripheral an ARoT partition drives:

1. Declare the register block as an `mmio_region` in the partition manifest, and add a matching
   `platform_data_t` to `tfm_peripherals_def.c` — the MPU region comes from that. Use the
   **secure** alias of the address on parts that alias peripherals.
2. Declare the interrupt as `irqs` in the manifest. The SPM then owns it; the partition uses
   `psa_irq_enable()`, never `NVIC_*`.
3. Call `R_XXX_Open()` from privileged init — the `<irq>_init` hook the manifest tooling
   generates is the natural home, since the SPM calls it during partition load.
4. **Declare the control block inside the partition**, not in `ra_gen/`. A partition's own
   globals land in its data region, which is unprivileged-RW for that partition; the generated
   instance in `hal_data.c` does not.
5. Compile the driver's operational sources into `tfm_sprt` so the code is fetchable from the
   unprivileged code region. Scope the include path to those files — `tfm_sprt` is linked into
   every partition, so putting the FSP tree on the whole target invites a header collision.

With those five, `R_AGT_Start(&my_ctrl)` works normally from the partition. No register poking.

### FLIH handlers can be unprivileged — it depends on the partition and the level

Worth stating because it is the opposite of what "interrupt handler" suggests: **an ARoT
partition's FLIH handler at isolation 2 or 3 runs in Thread mode at that partition's
privilege**, so it is unprivileged and bound by everything above — it may touch its
`mmio_region` peripherals and nothing else.

Measured, not assumed: an ARoT FLIH handler clearing the RA ICU latch faulted with
`MMFSR 0x82`, `MMFAR 0x40006300`, and the dump reported *"came from secure FW in thread
mode"*.

**It is not a general rule about FLIH, and this section used to state it as one.**
`interrupt.c:195-209` picks one of three dispatches:

| Condition | How `flih_func()` is called | Mode |
|---|---|---|
| `TFM_ISOLATION_LEVEL == 1` | directly | Handler — privileged |
| above 1, `tfm_hal_boundary_need_switch()` false (PSA-RoT) | directly | Handler — privileged |
| above 1, boundary switch needed (ARoT) | `tfm_flih_deprivileged_handling()` | Thread — partition's privilege |

So Handler mode is the common case and the unprivileged one is specific. Write a handler to
the narrowest of the three — its own `mmio_region` only — and it is correct in all of them.

That matters on RA specifically, because an interrupt latches in **two** places — the
peripheral's own flag and the ICU's `IELSR.IR` — and the ICU sits outside the peripheral's
MMIO region. The NVIC pending bit is worse: PPB, privileged-only by architecture, so no
region can grant it.

The split that works:

| Clear | Where | Privilege |
|---|---|---|
| ICU `IELSR.IR`, NVIC pending | the platform's own vector entry, before it calls `spm_handle_interrupt()` | Handler mode — privileged |
| the peripheral's own flag | the partition's FLIH handler | unprivileged, covered by its `mmio_region` |

Keep the ICU-then-peripheral order that FSP's own ISRs use.

### `tfm_sprt` must be stateless

`tfm_sprt`'s **code** is placed in the unprivileged region but its **`.bss` is not** — it lands
in `PT_PSA_ROT_DATA`. A `static` in a file compiled into `tfm_sprt` is therefore privileged
data, and reading it from an ARoT partition faults. Arm's own sprt timer driver has zero
statics for exactly this reason.

That is why `plat_test.c` in this port is stateless and drives AGT0 through bare `AGTCR`
writes: it is a test fixture called by upstream's ARoT partitions, so it cannot follow step 4
above — it does not own the partition and has nowhere to put a control block. **A real
partition you write is in a better position than that fixture**, because it owns its own data.

### The escape hatch

If none of this is appealing: **put the peripheral in a PSA RoT partition.** PSA RoT is
privileged at every isolation level, so FSP drivers work there completely unmodified, `_Open()`
included. The split above is only needed when an Application RoT partition must drive the
hardware itself.

### Provenance

Measured on RA6M5 at isolation 2 on 2026-10-20, with the FLIH test service as the ARoT caller.
The IACCVIOL came first at `PC 0x000BA964` (`tfm_plat_test_secure_timer_start`, inside
`PT_PSA_ROT_CODE`); moving the file to `tfm_sprt` turned it into a DACCVIOL at
`MMFAR 0x20011493` (a `static bool`, inside `PT_PSA_ROT_DATA`). Upstream platforms place
`plat_test.c` in `platform_s` and only the low-level timer driver in `tfm_sprt`, which does not
actually work above isolation 1 — the FLIH/SLIH suites appear never to have been run there.

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

- [GETTING_STARTED.md](GETTING_STARTED.md) — the build itself
- [DESIGN.md](DESIGN.md) §1 — why the e2 projects are consumed rather than forked
- [BRIDGING_FILES.md](BRIDGING_FILES.md) — files that carry FSP code but do not move with it
- [DECISIONS.md](DECISIONS.md) — [D061] secure timer, [D089] per-part drift, [D091] why the MCUboot port is excluded
