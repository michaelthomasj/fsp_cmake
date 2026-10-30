# e2 baseline projects

The RA6M5 and RA8M2 GCC solutions as e2 studio first creates them, before any port change.

Nothing here is built or flashed. This directory is the left-hand side of a comparison: it
exists so the port's RASC choices can be read as a diff instead of taken on trust. The port's
own projects are one directory up, under the same names.

Generated with FSP pack `Renesas.RA.6.7.0-beta0+20260925.818e720c`, which is exactly the pack
the port uses. A diff therefore shows decisions, not a pack version difference.

The same files are also on the orphan branch `e2-baseline`, which has no commit in common with the
port's history. The copy here is byte-identical and is the one to use. See
[D140](../DECISIONS.md).

## What is here

138 files: two solutions, three projects each, holding only the files that record a choice.

| | |
|---|---|
| `configuration.xml` | modules, clocks, stacks, pin configuration |
| `.secure_azone` | TrustZone address partitioning, and peripheral security assignment |
| `.secure_rzone` | TrustZone resource partitioning |
| `.secure_xml`, `.core_xml` | the secure/non-secure split as e2 records it |
| `.project`, `.cproject` | project and build settings |
| `ra_cfg.txt` | the pack and component list |
| `script/fsp.ld` | the linker script's source |
| `src/` | `hal_entry.c` and `hal_warmstart.c`, untouched |

Not here: `ra/`, `ra_gen/` and `ra_cfg/`. RASC regenerates all three from `configuration.xml`
and the pack version, so storing them again would add about 1,200 files and no information.
`.gitignore` in this directory keeps them out if you do generate here.

These projects do not build as they stand. Open the solution in e2 studio and generate first.

**Do not flash or debug from this directory.** The two `*_nonsecure Debug_SSD.launch` files
here carry `com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` = `true`, which
`DESIGN.md` §7.2 forbids: launched against BL2 the debugger derives the TrustZone
boundaries from the wrong symbols. They keep that value deliberately, because this
directory exists to show what e2 generates before any change. The equivalents were deleted
from the live project set.

## How to read the difference

Both trees are in this checkout, so compare the committed files by path:

```
git diff HEAD:e2_baseline/ra6m5_gcc_secure/.secure_azone \
         HEAD:ra6m5_gcc_secure/.secure_azone
```

Use that form rather than a `diff` of the two files on disk. Line endings in this repository
are whatever the tool that wrote each file produced, and `git diff` compares the committed
content, where they are normalised. A disk-level `diff` can report every line as changed when
only the line endings differ. Add `--strip-trailing-cr` if you need to compare on disk.

## Where to look first

Sizes are `git diff --numstat` between the committed files, added and removed lines.

| compare | size | what it shows |
|---|---|---|
| `ra6m5_gcc_secure/.secure_azone` | 20+/15- | the whole RA6M5 layout decision in one screen: both image slots doubled (`__BL_0_S_I` `0x3FE00` to `0x7FE00`), the NSC window moved to `0x11F800`, data flash made wholly secure (`0x1000`/`0x1000` to `0x2000`/`0x0`), a 32 KB scratch region added, AGT0 and IRQ0 made secure |
| `ra6m5_gcc_secure/ra_cfg.txt` | 347+/3- | the modules the port adds: `flash_on_flash_hp`, `psa_crypto`, `rm_psa_crypto`, `sce9.plaintext`, `timer_on_agt` |
| `ra6m5_gcc_mcuboot/.secure_azone` | 16+/15- | the same layout as the bootloader sees it. This project owns the option-setting choices behind the brick hazard in [D133](../DECISIONS.md) |
| `ra8m2_gcc_CPU0_secure/.secure_azone` | 5+/1- | that the RA8M2 layout is the template's, unchanged. One reordered line, then AGT0 and IRQ0 made secure |
| `ra8m2_gcc_CPU0_secure/ra_cfg.txt` | 343+/3- | `flash_on_mram`, `psa_crypto`, `rm_psa_crypto`, `rsip_e50d.plaintext`, `timer_on_agt`, with stack `0x400` to `0x1000` and heap `0` to `0x1500` |
| `ra6m5_gcc_nonsecure/configuration.xml` | 7+/275- | what the non-secure project drops relative to a stock one |

`.secure_rzone` is identical to the baseline in all six projects. The port assigns peripheral
security through `.secure_azone` and changes nothing in `.secure_rzone`.

## Known divergence this baseline surfaced

The RA6M5 GCC scratch region is named `UNUSED_SCRAtTCH` in all three `.secure_azone` files.
The IAR solution spells it `UNUSED_SCRATCH`. The name reaches three generated files as
`BSP_PARTITION_UNUSED_SCRAtTCH_START` and `_SIZE`: `bsp_linker_info.h`, `memory_regions.ld`
and `fsp_gen.ld`. Nothing reads either macro, so no build depends on the spelling and no
image changes if it is corrected. [D140](../DECISIONS.md) records the state and why it was
left.

## Limits

- The two IAR solutions have no baseline. `configuration.xml` should be near-identical to the
  GCC one, so the GCC comparison covers the decisions; a `.cproject` difference is the
  expected remainder.
- A baseline regenerated with a later pack is no longer directly comparable. Part of any diff
  would then be the pack version rather than a decision.
- [DESIGN.md](../DESIGN.md) §1 states the principle that RASC is the source of configuration
  truth, and §1.1 lists the documented exceptions. A generated file that differs from what
  this baseline's `configuration.xml` would produce is a hand edit, and belongs in that list
  or in a patch the build applies.
