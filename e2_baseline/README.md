# e2 baseline projects

The RA6M5 and RA8M2 GCC solutions as e2 studio first creates them, before any port change.

Not built or flashed: the left-hand side of a diff, so the port's RASC choices can be checked
rather than trusted. The port's projects are one directory up, under the same names.

Generated with FSP pack `Renesas.RA.6.7.0-beta0+20260925.818e720c`, which is exactly the pack
the port uses. A diff therefore shows decisions, not a pack version difference.

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

`ra/`, `ra_gen/` and `ra_cfg/` are omitted because RASC regenerates them; generate in e2 studio
before building.

**Do not flash or debug from here.** The two `Debug_SSD` launches keep e2's default
`setTZBoundaries=true` (GETTING_STARTED §6).

## How to read the difference

Both trees are in this checkout, so compare the committed files by path:

```
git diff HEAD:e2_baseline/ra6m5_gcc_secure/.secure_azone \
         HEAD:ra6m5_gcc_secure/.secure_azone
```

Compare committed content with `git diff` as above; a disk-level `diff` can report every line
changed because of line endings (or use `--strip-trailing-cr`).

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

## Limits

- No IAR baseline; the GCC comparison covers the decisions.
- A baseline regenerated on a later pack is not comparable.
- A generated file that differs from what this baseline would produce is a hand edit and belongs
  in [DESIGN.md](../DESIGN.md) §1.1.
