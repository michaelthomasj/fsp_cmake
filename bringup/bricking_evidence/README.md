# Bricking evidence — RA6M4 FSPR=0 permanent lock

These files are the **exact BL2 image that permanently bricked two EK-RA6M4 boards** on
2026-07-20, preserved for forensic reference. Do **not** flash them to any board.

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

What is known: both bricked boards read `FAWMON=0` / `FSPR=0` (permanent FAW lock), and `FSPR` is set
only by a flash Configuration-Set command. The variable that differs is the **flashing path**, not the
image: der is programmed by e2 studio's RA-aware Renesas J-Link flow; both bricks came via **Ozone /
raw `JLink.exe`** (generic flash path). Whether that path clears `FSPR` — and whether because of the
`0x0100A1xx` records or independently (erase/reset on a TZ-configured device) — is **untested** (no
hardware left). Falsifiable test when a board is available: flash the OFS-free `bl2.elf` via Ozone,
read `FAWMON`; `FSPR=1` ⇒ OFS+Ozone was the trigger, `FSPR=0` ⇒ the Ozone/raw-JLink path itself is
unsafe for RA6M4.

### Observed post-brick state (both boards, read over J-Link)
```
FAWMON @0x407FE0DC = 0x00000000   -> FSPR (bit15) = 0   PERMANENT
FSTATR @0x407FE080 = 0x00008000   -> peripheral clocked, read is valid
0x0100A130 / 0x0100A160 = 0x00000000  -> Security-MPU block zeroed by the config-set
Boot firmware Initialize -> "Boot error code: 0xDA" (RES_PROTECTION_ERROR)
```

`FSPR = 0` is irreversible — no RFP / RDPM / J-Link recovery. RMA only.

## The mitigation (not a proven fix)

Option-setting sections were removed from **all** TF-M images (linker + source + CMake) — per the
project requirement that BL2 never link OFS, and as a precaution that takes the dangerous region out of
every debugger-flashed image. This is **not confirmed** to be the brick cause (see above). Prefer the
**e2 studio / RFP** flashing flow over Ozone/raw-JLink for RA6M4, and read `FAWMON` back after any
option/protection programming. See `../../DESIGN.md` §8.4 and `../check_ofs.py`.
