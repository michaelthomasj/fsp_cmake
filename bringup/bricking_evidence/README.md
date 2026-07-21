# Bricking evidence — RA6M4 FSPR=0 permanent lock

These files are the **exact BL2 image that permanently bricked two EK-RA6M4 boards** on
2026-07-20, preserved for forensic reference. Do **not** flash them to any board.

- `bl2_BRICKED.elf` — the exact `build_ra6m4_boot/bin/bl2.elf` (built 14:31:26), copied with its
  original timestamp.
- `bl2_BRICKED.srec` / `bl2_BRICKED.hex` — same image, S-record / Intel-hex.

## What caused the brick

The image contains three data records in the RA6M4 **option/config memory** region
(`0x0100A100–0x0100A2CF`):

```
S3 09 0100A100 FFFFFFFF 58    OFS0     = 0xFFFFFFFF
S3 09 0100A200 FFFDFFFF 59    OFS1_SEC = 0xFFFFFDFF
S3 09 0100A280 F8F8FFFF E5    OFS1_SEL = 0xFFFFF8F8
```

The RA6M4 programs option/config memory through the flash **FCU Configuration-Set** command as **one
block** covering OFS **+ Security-MPU + FAW** (including the one-time-programmable **FSPR** permanence
bit). When a debugger (J-Link/Ozone) flashes an image that contains only a **partial** option region,
the flash algorithm supplies **zeros** for the rest of the config block. That drives **`FSPR → 0`**,
which permanently locks the Flash Access Window and disables erase for the life of the part.

### Observed post-brick state (both boards, read over J-Link)
```
FAWMON @0x407FE0DC = 0x00000000   -> FSPR (bit15) = 0   PERMANENT
FSTATR @0x407FE080 = 0x00008000   -> peripheral clocked, read is valid
0x0100A130 / 0x0100A160 = 0x00000000  -> Security-MPU block zeroed by the config-set
Boot firmware Initialize -> "Boot error code: 0xDA" (RES_PROTECTION_ERROR)
```

`FSPR = 0` is irreversible — no RFP / RDPM / J-Link recovery. RMA only.

## The fix

Option-setting sections were removed from **all** TF-M images (linker + source + CMake). Option memory
must be programmed **only** by an RA-aware tool (RFP) with a **complete, FSPR-preserving** config, and
verified by reading `FAWMON` back afterward. See `../../DESIGN.md` §8.4 and `../check_ofs.py`.
