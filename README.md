# fsp_cmake

RASC/e2 studio project set and build glue for the **TF-M port to Renesas RA**. The port itself
lives in the companion repository, `trusted-firmware-m`, under
`platform/ext/target/renesas/<part>/`; this repository holds the generated FSP projects it
consumes, the build scripts, and the design record.

Active parts: **RA6M5** and **RA8M2**. RA6E1 and RA6M4 are in-tree but dormant (both EK-RA6M4
boards are bricked — see DECISIONS D002).

---

## The two repositories

| | |
|---|---|
| `fsp_cmake` (here) | e2 studio solutions and generated FSP projects, `scripts/`, the docs below |
| `trusted-firmware-m` | the TF-M fork carrying the RA platform ports and a small patch queue against upstream |

The core principle, and the one worth reading before anything else: **RASC is the source of
config truth — the TF-M build consumes the generated projects, it does not fork them.**
`DESIGN.md` §1. Deliberate exceptions are listed in §1.1; anything else that diverges is a
defect, not a choice.

## Shortest path to a build

1. Open the solution for your part in e2 studio (`ra6m5_gcc`, `ra8m2_gcc`) and **build it**.
   This is a prerequisite, not an optional step: the TF-M build reads `Debug/bsp_linker_info.h`
   and `Debug/memory_regions.*`, which only an e2 build produces. Regenerating alone is not
   enough.
2. Run the matching script from `scripts/` — `app_build_ra8m2_gcc.bat`, `app_build_iar.bat`, and
   so on. Each builds BL2 + secure, installs the SPE, then builds the non-secure image.
3. Flash with the e2 debug launch configurations in `<part>_gcc_nonsecure/`.

**PSA Arch builds additionally need `scripts\vs_build.bat`** — they compile a host tool with
`cl.exe`, which needs a Visual Studio developer environment. See DECISIONS D083.

Two rules that have cost hardware:

- **Flash `bl2.elf` or `bl2.hex`, never `bl2.bin`.** The option-setting words live in discrete
  segments a flat binary cannot express. D002, D065.
- **Keep `setTZBoundaries` = `false`** in every launch configuration. The debugger derives
  boundaries from the launched project's symbols, and launched against BL2 it gets them wrong.
  `DESIGN.md` §7.2.

## Freeing space in the secure image

The secure slot is nearly full on both active parts, so this is the first place to look when
something no longer fits:

```
RA6M5   522,304 of 524,288 B    1,984 B spare
RA8M2   293,952 of 294,912 B      960 B spare
```

The PSA Arch builds turn several diagnostics **on** deliberately — a user running those suites
wants them out of the box, and `profile_large` at isolation 3 has the room. The ordinary
regression and FLIH/SLIH builds do **not** have the room and leave them off. Measured on RA6M5,
GCC 13.2:

| Option | Cost | Set by |
|---|---|---|
| `MCUBOOT_LOG_LEVEL=INFO` | **BL2** text +5,960 B, bss +4,284 B | `psa_arch_spe*.bat` |
| `TFM_SPM_LOG_LEVEL=..._DEBUG`<br>`TFM_PARTITION_LOG_LEVEL=..._INFO`<br>`CONFIG_TFM_HALT_ON_CORE_PANIC=ON` | **secure** text +3,785 B (the three together) | `psa_arch_spe*.bat` |
| `TFM_EXCEPTION_INFO_DUMP=ON` | secure text ~3.4 KB | `<part>/config.cmake` — on everywhere |
| `TFM_SPM_DEBUG_TRACE` | a handful of bytes | off; must stay off at isolation 3 + IPC |

Turning the first two groups off recovers roughly **3.7 KB of secure flash and 6 KB of BL2
flash**. They are passed on the command line by the PSA Arch scripts rather than set in
`<part>/config.cmake`, precisely so they do not reach the builds that cannot afford them —
3,785 B against 1,984 B of headroom would not link.

`TFM_EXCEPTION_INFO_DUMP` is the one worth considering for a production image: it is on for
every build today and is pure diagnostics.

## The documents

| | |
|---|---|
| `DESIGN.md` | how the port works. §1 the core principle, §1.1 documented deviations, §7 TrustZone |
| `DECISIONS.md` | why, append-only, D001–D084. Superseded entries stay; later ones say so |
| `RA6M5_SOLUTION.md`, `RA6E1_SOLUTION.md` | per-part layout, RDPM boundary values, what the e2 projects must provide |
| `UPSTREAM_CHANGES.md` | the patch queue against upstream TF-M, with the rationale for each |
| `RA6E1_TEMPLATE_CHECKLIST.md` | what a new RA part has to supply |
| `RA8x2_DUAL_CORE_DESIGN.md` | forward design for the dual-core parts |
| `DOCUMENTATION_PLAN.md` | the target document set; several below are scheduled to be folded in |

Status files, ageing but with useful resolved-issue narratives: `TFM_INTEGRATION_COMPLETE.md`,
`BUILD_TEST_RESULTS.md`, `MACHINE_HANDOFF.md`, `TFM_RA6M4_STATUS.md`.
