# Bricking evidence — two un-erasable EK-RA6M4 boards

The exact BL2 image that was flashed to two EK-RA6M4 boards, after which neither would erase.
Kept as forensic reference and as the regression fixture for the option-setting brick guard.
**Do not flash these files to any board.**

Each carries the `.UNSAFE` suffix, which is also what `check_ofs.py --quarantine` renames a
rejected image to. **Strip the suffix only to feed one to a tool that reads it; never to a
programmer.**

| File | What it is |
|---|---|
| `bl2_BRICKED.elf.UNSAFE` | the exact `build_ra6m4_boot/bin/bl2.elf`, built 14:31:26, copied with its original timestamp |
| `bl2_BRICKED.srec.UNSAFE` | the same image as an S-record |
| `bl2_BRICKED.hex.UNSAFE` | the same image as Intel hex |

## What the image did

GNU ld coalesced the option-setting words into one `PT_LOAD` segment spanning
`0x0100A100`–`0x0100A284` and zero-filled the gaps between them. A debugger programs by
program header, so flashing it wrote `0x00` across that whole span: eight defined option
registers — DUALSEL, OFS1, BANKSEL, BPS, PBPS and the `_SEC` copies of the last three — and
the reserved bytes between them. Measured gap fill is `0x00` × 376, not `0xFF`
([D133](../../DECISIONS.md)).

**Which of those eight registers made the boards un-erasable is not established.** Neither is
whether the state is reversible. Both boards are gone and there is no RA6M4 hardware left to
test on.

The three records the image carries in the option region are not themselves the cause:

```
S3 09 0100A100 FFFFFFFF 58    OFS0     = 0xFFFFFFFF
S3 09 0100A200 FFFDFFFF 59    OFS1_SEC = 0xFFFFFDFF
S3 09 0100A280 F8F8FFFF E5    OFS1_SEL = 0xFFFFF8F8
```

The field-proven `ra6m4_der_conversion` image carries byte-identical records in this region, by
S-record diff, on a board that still works and still reprograms. The values are not the
differentiator; the span between them is.

## What was read off the dead boards

```
DLMMON @0x400E002C  = 0x2    DLM state SSD - an open development state, not locked
Boot firmware Initialize     "Boot error code: 0xDA" (RES_PROTECTION_ERROR)
0x0100A130, 0x0100A160 = 0   config-area words; these two addresses were never checked
                             against the hardware manual
```

No register read here proves a permanent lock. `DLMMON` reports an open state, and the `0xDA`
from Initialize is real but is not explained by anything in this list.

**Do not read `FAWMON` or `FSPR` on an RA6M4.** The part does not implement the Flash Access
Window (`BSP_FEATURE_FLASH_SUPPORTS_ACCESS_WINDOW = 0`), so those addresses hold no such
register and whatever they return is meaningless. An earlier diagnosis of a permanent FSPR/FAW
lock rested on exactly that mistake and has been withdrawn ([D094](../../DECISIONS.md)).
`FBPROT0` and `FBPROT1` are write-only cancel bits that always read `0`, so they say nothing
either.

Two variables between the dead boards and the working `der_conversion` board were never
isolated: the flashing path, Ozone and raw J-Link against e2 studio's RA-aware flow, and the
relink of BL2 to `0x0` in TF-M commit `be511be17`. On RA6M4, prefer the e2 studio or RFP path,
and read the state back on hardware after any option or protection programming.

## What the port does now

OFS emission was first removed from every TF-M image ([D001](../../DECISIONS.md)) and then
restored, with one linker `MEMORY` region per option *group* and a `> REGION` assignment on each,
so the linker cannot produce a spanning segment ([D002](../../DECISIONS.md)). Removing the
words had meant every board needed them programmed externally for ever; the discrete regions
are what FSP's own generated linker does.

`check_ofs.py`, in the TF-M tree at `platform/ext/target/renesas/common/check_ofs.py`,
enforces that outcome on the linked ELF. The ELF is the only artifact the mistake is visible
in: it does not show in the srec, and a plausible-looking linker script can still emit a
spanning segment. [DESIGN.md](../../DESIGN.md) §8.4 has the design and
[KNOWN_LIMITATIONS.md](../../KNOWN_LIMITATIONS.md) §4 the hazard as it stands.

**`bl2_BRICKED.elf.UNSAFE` is that guard's regression fixture — do not delete it.** The guard rejects
it with `0x0100A100+388B` (388 = `0x184`, the span itself), which is how the check is verified
to fire rather than only to pass.
