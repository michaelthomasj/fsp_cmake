# Bricking evidence — RA6M4 un-erasable boards (cause UNKNOWN)

These files are the **exact BL2 image flashed to two EK-RA6M4 boards** that then became un-erasable on
2026-07-20, preserved for forensic reference. Do **not** flash them to any board. (An earlier title
called this an "FSPR=0 permanent lock" — that diagnosis was wrong; see below.)

- `bl2_BRICKED.elf` — the exact `build_ra6m4_boot/bin/bl2.elf` (built 14:31:26), copied with its
  original timestamp.
- `bl2_BRICKED.srec` / `bl2_BRICKED.hex` — same image, S-record / Intel-hex.

## Status: root cause NOT established

The image contains three data records in the RA6M4 **option/config memory** region
(`0x0100A100–0x0100A2CF`):

```
S3 09 0100A100 FFFFFFFF 58    OFS0     = 0xFFFFFFFF
S3 09 0100A200 FFFDFFFF 59    OFS1_SEC = 0xFFFFFDFF
S3 09 0100A280 F8F8FFFF E5    OFS1_SEL = 0xFFFFF8F8
```

These were **initially blamed** for the brick. That was **disproven**: the field-proven
`ra6m4_der_conversion` image carries **byte-identical** records in this region (SREC diff) yet is a
working, reprogrammable board. So the option-memory *content* is not the differentiator.

What is known: both boards won't erase and RDPM `Initialize` returns `0xDA` (RES_PROTECTION_ERROR),
while `DLMMON @0x400E002C = 0x2` = **SSD** (open dev state, NOT locked). **The cause and reversibility
are UNKNOWN.** An earlier "permanent FSPR/FAW brick" diagnosis was WRONG — RA6M4 does not implement the
Flash Access Window (`BSP_FEATURE_FLASH_SUPPORTS_ACCESS_WINDOW = 0`), so `FAWMON/FSPR` are meaningless
here; do not read them. The variable that differs from the working der board is the **flashing path**
(Ozone/raw-JLink vs e2 studio RA-aware) and/or the relink to `0x0` at `be511be17` — untested (no
hardware left). Correct check on a suspect board: read `DLMMON @0x400E002C`, attempt RDPM Initialize,
and compare Ozone vs e2 studio/RFP flashing.

### Observed post-brick state (read over J-Link)  — with corrected interpretation
```
DLMMON @0x400E002C = 0x2  -> DLM state SSD (open dev state, NOT locked)  [correct lock register]
Boot firmware Initialize -> "Boot error code: 0xDA" (RES_PROTECTION_ERROR)
0x0100A130 / 0x0100A160  = 0x00000000  (config-area words; addresses NOT verified vs HW manual)

# INVALID readings from the withdrawn theory (RA6M4 has no Flash Access Window):
FAWMON @0x407FE0DC = 0x00000000   -> FSPR is not a feature on RA6M4; meaningless here
FBPROT0/1 @0x407FE078/7C = 0x0000 -> write-only cancel bits, always read 0; meaningless
```

No valid register read proves a permanent lock. `DLMMON` says SSD; the `0xDA` on Initialize is real but
unexplained. **Reversibility is unknown**, not "irreversible / RMA only" as previously stated.

## The mitigation (not a proven fix)

Option-setting sections were removed from **all** TF-M images (linker + source + CMake) — per the
project requirement that BL2 never link OFS, and as a precaution that takes a security-sensitive region
out of every debugger-flashed image. This is **not confirmed** to be the cause (see above). Prefer the
**e2 studio / RFP** flashing flow over Ozone/raw-JLink for RA6M4, and verify state on hardware after any
option/protection programming. See `../../DESIGN.md` §8.4 and `../check_ofs.py`.
