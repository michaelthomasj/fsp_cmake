# Bricking evidence — two un-erasable EK-RA6M4 boards

The BL2 image flashed to two EK-RA6M4 boards that then would not erase, kept as evidence and as
the regression fixture for the option-memory guard. **Do not flash these files.** The `.UNSAFE`
suffix is the one `check_ofs.py --quarantine` gives a rejected image; strip it only to feed a
file to an analysis tool, never to a programmer.

| File | What it is |
|---|---|
| `bl2_BRICKED.elf.UNSAFE` | the BL2 ELF exactly as flashed |
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

A working board carries byte-identical values in these records; the span between them is the
differentiator.

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
register, and whatever they return is meaningless. `FBPROT0` and `FBPROT1` are write-only
cancel bits that always read `0`, so they say nothing either.

On RA6M4, prefer the e2 studio or RFP flashing path, and read the state back after any option or
protection programming.

## What the port does now

The port now gives each option-setting group its own linker `MEMORY` region, so the linker cannot
emit a spanning segment ([D002](../../DECISIONS.md)), and
`platform/ext/target/renesas/common/check_ofs.py` enforces this on the linked ELF. Mechanism:
[DESIGN.md](../../DESIGN.md) §8.4. Flashing rule: [GETTING_STARTED.md](../../GETTING_STARTED.md)
§6.

**`bl2_BRICKED.elf.UNSAFE` is the guard's regression fixture; do not delete it.** Verify the
guard fires:
`python <tfm>/platform/ext/target/renesas/common/check_ofs.py --ra6-default --require-segments bringup/bricking_evidence/bl2_BRICKED.elf.UNSAFE`
must FAIL with `0x0100A100+388B`.
