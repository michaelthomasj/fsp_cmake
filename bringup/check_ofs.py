#!/usr/bin/env python3
"""
check_ofs.py - flag any option-setting (OFS) memory value in a built BL2 image
that differs from a KNOWN-GOOD reference image.

Why: the OFS region (0x0100A100-0x0100A2CF: OFS0/OFS1/_SEC/_SEL/BPS/PBPS/SECMPU...)
programs security attribution, watchdogs, clocks, and flash protection. A wrong
word here can misconfigure or (with FAW/permanent bits) permanently brick a part.
The RA6M4 ra6m4_der_conversion project is a trusted, field-proven image, so we
diff our BL2's OFS bytes against it and fail the build if anything diverges.

Compares the effective programmed option memory over 0x0100A100..0x0100A2CF:
for each 4-byte slot, the value is the image's section content where present,
else 0xFFFFFFFF (unprogrammed option memory reads as erased = all-ones).

Usage:
    python check_ofs.py [TARGET_ELF] [--ref REFERENCE_ELF] [--objdump OBJDUMP]
Defaults:
    TARGET_ELF = trusted-firmware-m/build_ra6m4_boot/bin/bl2.elf
    REFERENCE  = ra6m4_der_conversion/Debug/ra6m4_der_conversion.elf
Exit code: 0 = all match, 1 = a difference was found, 2 = usage/tool error.
"""
import argparse, os, re, shutil, subprocess, sys

OFS_START = 0x0100A100
OFS_END   = 0x0100A2D0          # exclusive (covers ...A2CF)
ERASED    = 0xFF                # unprogrammed option flash reads all-ones

# Human labels for the known region addresses (from ra6m4_bl2.ld).
REGION_NAMES = {
    0x0100A100: "OFS0", 0x0100A110: "DUALSEL", 0x0100A180: "OFS1",
    0x0100A190: "BANKSEL", 0x0100A1C0: "BPS", 0x0100A1E0: "PBPS",
    0x0100A200: "OFS1_SEC", 0x0100A210: "BANKSEL_SEC", 0x0100A240: "BPS_SEC",
    0x0100A260: "PBPS_SEC", 0x0100A280: "OFS1_SEL", 0x0100A290: "BANKSEL_SEL",
    0x0100A2C0: "BPS_SEL",
    # 0x0100A120-0x0100A17F is the Security MPU (SECMPU) config block.
}

def find_default(*rel):
    here = os.path.dirname(os.path.abspath(__file__))
    for base in (here, os.path.join(here, ".."), os.path.join(here, "..", "..")):
        p = os.path.normpath(os.path.join(base, *rel))
        if os.path.isfile(p):
            return p
    return os.path.normpath(os.path.join(here, "..", "..", *rel))

def ofs_bytes(elf, objdump):
    """Return {addr: byte} for every byte in [OFS_START, OFS_END) present in elf."""
    try:
        out = subprocess.run([objdump, "-s", elf], capture_output=True, text=True,
                             check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit(f"ERROR: objdump failed on {elf}: {e}")
    m = {}
    # Lines look like: " 100a100 ffffffff fffdffff ....  ...."
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
                m[a] = int(blob[i:i+2], 16)
    return m

def word(m, a):
    return sum(m.get(a + i, ERASED) << (8 * i) for i in range(4))  # little-endian

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("target", nargs="?",
                    default=find_default("trusted-firmware-m", "build_ra6m4_boot", "bin", "bl2.elf"))
    ap.add_argument("--ref",
                    default=find_default("..", "..", "e2_studio", "workspace64_1",
                                         "ra6m4_der_conversion", "Debug", "ra6m4_der_conversion.elf"))
    ap.add_argument("--objdump", default=os.environ.get("OBJDUMP", "arm-none-eabi-objdump"))
    a = ap.parse_args()

    if not shutil.which(a.objdump):
        sys.exit(f"ERROR: objdump '{a.objdump}' not on PATH (set --objdump or $OBJDUMP)")
    for label, p in (("target", a.target), ("reference", a.ref)):
        if not os.path.isfile(p):
            sys.exit(f"ERROR: {label} ELF not found: {p}")

    ref, tgt = ofs_bytes(a.ref, a.objdump), ofs_bytes(a.target, a.objdump)
    print(f"OFS diff  0x{OFS_START:08X}..0x{OFS_END-1:08X}")
    print(f"  target   : {a.target}")
    print(f"  reference: {a.ref}\n")
    print(f"  {'addr':<12}{'region':<14}{'reference':<12}{'target':<12}status")

    diffs = 0
    for addr in range(OFS_START, OFS_END, 4):
        rv, tv = word(ref, addr), word(tgt, addr)
        name = REGION_NAMES.get(addr, "")
        # Only print programmed slots or mismatches (keep the erased sea quiet).
        interesting = (rv != 0xFFFFFFFF) or (tv != 0xFFFFFFFF) or (rv != tv)
        if not interesting:
            continue
        if rv == tv:
            print(f"  0x{addr:08X}  {name:<14}{rv:08x}    {tv:08x}    OK")
        else:
            diffs += 1
            print(f"  0x{addr:08X}  {name:<14}{rv:08x}    {tv:08x}    *** DIFF ***")

    print()
    if diffs:
        print(f"FAIL: {diffs} OFS word(s) differ from the known-good reference.")
        print("Investigate before flashing - a wrong OFS word can brick the part (DESIGN.md 8.2/8.4).")
        return 1
    print("PASS: all programmed OFS words match the known-good reference.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
