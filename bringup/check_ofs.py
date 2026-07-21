#!/usr/bin/env python3
"""
check_ofs.py - BRICK GUARD. Fail if a firmware image contains ANY RA6M4
option/config-memory content (0x0100A100-0x0100A2CF).

WHY THIS EXISTS (read DESIGN.md 8.4): flashing an image that carries even a
partial option region via J-Link/Ozone drives the flash Configuration-Set
command to zero the rest of the config block, which clears the one-time FSPR
permanence bit and PERMANENTLY BRICKS the part. This destroyed two EK-RA6M4
boards. No BL2/secure/NS image may ever contain these sections; option memory
is programmed ONLY by RFP, separately, verified by reading FAWMON back.

This check makes that a build/CI gate: it inspects the ELF (or any objdump-able
image) and exits non-zero if a single byte lands in 0x0100A100-0x0100A2CF.

Usage:
    python check_ofs.py [IMAGE_ELF ...]
    (defaults to the three build_ra6m4_boot images if no args)
Exit: 0 = all clean, 1 = an image carries option memory (DO NOT FLASH), 2 = tool error.
"""
import os, re, shutil, subprocess, sys

OFS_START = 0x0100A100
OFS_END   = 0x0100A2D0            # exclusive (covers ...A2CF)
OBJDUMP   = os.environ.get("OBJDUMP", "arm-none-eabi-objdump")

def default_images():
    here = os.path.dirname(os.path.abspath(__file__))
    binp = os.path.normpath(os.path.join(here, "..", "..", "trusted-firmware-m",
                                          "build_ra6m4_boot", "bin"))
    out = []
    for n in ("bl2.elf", "tfm_s.axf", "tfm_ns.axf"):
        p = os.path.join(binp, n)
        if os.path.isfile(p):
            out.append(p)
    return out

def option_bytes(elf):
    """Return sorted list of (addr, byte) that fall inside the config window."""
    try:
        out = subprocess.run([OBJDUMP, "-s", elf], capture_output=True, text=True,
                             check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit(f"ERROR: objdump failed on {elf}: {e}")
    hits = {}
    for line in out.splitlines():
        t = re.match(r"\s*([0-9a-fA-F]{4,8})\s+((?:[0-9a-fA-F]{2,8}\s+){1,4})", line)
        if not t:
            continue
        addr = int(t.group(1), 16)
        if addr + 16 < OFS_START or addr >= OFS_END:
            continue
        blob = "".join(t.group(2).split())
        for i in range(0, len(blob), 2):
            a = addr + i // 2
            if OFS_START <= a < OFS_END:
                hits[a] = int(blob[i:i+2], 16)
    return sorted(hits.items())

def main():
    if not shutil.which(OBJDUMP):
        sys.exit(f"ERROR: objdump '{OBJDUMP}' not on PATH (set $OBJDUMP)")
    images = sys.argv[1:] or default_images()
    if not images:
        sys.exit("ERROR: no images given and no default build images found")

    print(f"Brick guard: no image may contain option memory 0x{OFS_START:08X}-0x{OFS_END-1:08X}\n")
    bad = 0
    for elf in images:
        if not os.path.isfile(elf):
            print(f"  {os.path.basename(elf):<14} MISSING ({elf})"); continue
        hits = option_bytes(elf)
        if not hits:
            print(f"  {os.path.basename(elf):<14} CLEAN")
        else:
            bad += 1
            addrs = ", ".join(f"0x{a:08X}" for a, _ in hits[:8])
            print(f"  {os.path.basename(elf):<14} *** CONTAINS OPTION MEMORY - DO NOT FLASH *** "
                  f"({len(hits)} bytes @ {addrs}{'...' if len(hits) > 8 else ''})")

    print()
    if bad:
        print(f"FAIL: {bad} image(s) carry option memory. Flashing them via J-Link/Ozone will")
        print("permanently brick the part (FSPR=0). Remove the .option_setting_* sections. DESIGN.md 8.4.")
        return 1
    print("PASS: no image carries option memory - safe to flash via debugger.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
