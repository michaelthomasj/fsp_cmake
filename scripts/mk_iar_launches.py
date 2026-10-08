#!/usr/bin/env python3
"""Derive the RA8M2 IAR debug launches from the working GCC ones.

    python mk_iar_launches.py [--check]

WHY DERIVE RATHER THAN HAND-WRITE
---------------------------------
An e2 launch is ~300 attributes, of which two matter for correctness and are easy to get
wrong by hand:

  * setTZBoundaries must be false. The debugger writing the TrustZone boundaries is a
    brick hazard (DESIGN.md 7.2). RA8M2 launches carry the key TWICE - once in the
    jlink namespace, once in e2lite - and e2's default for the latter is true. Only the
    namespace matching the selected probe is read, and these launches select J-Link, but
    this script forces BOTH to false so switching probe cannot arm it.
  * ueraseRomOnDownload / ueraseDataRomOnDownload must be 1, or a stale ITS/PS area
    survives a reflash and the storage suites fail in ways that look like code faults.

Both are inherited unchanged from the GCC launch, which is known good on hardware.

WHAT ACTUALLY DIFFERS BETWEEN A GCC AND AN IAR LAUNCH
----------------------------------------------------
Only the build directory paths. Verified against the RA6M5 pair, where
ra6m5_TFM_test_crypto_{gcc,iar}.launch differ in exactly 9 lines, all of them paths.
Image names are identical (bl2.elf, tfm_s_signed.bin, tfm_ns.axf, ...) because TF-M names
its outputs the same under both toolchains.

The host project stays the GCC one, which is also the RA6M5 convention: both toolchains'
launches live in ra6m5_gcc_nonsecure and name it in PROJECT_ATTR. A launch only downloads
prebuilt images, so the hosting project is incidental, and keeping one project means one
place to find every launch in e2.
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAUNCH_DIR = ROOT / "ra8m2_gcc_mcuboot"

# GCC build tree -> IAR build tree. LONGEST FIRST: m2cry is a prefix of m2cryns and
# m2gflih of m2gflihns, so a shorter match first would corrupt the longer name.
TREE_MAP = [
    ("m2gflihns", "m2iflihns"),
    ("m2gflih", "m2iflih"),
    ("m2cryns", "m2icryns"),
    ("m2cry", "m2icry"),
    ("m2att", "m2iatt"),
    ("m2sto", "m2isto"),
]

LAUNCHES = [
    "ra8m2_TFM_flih_gcc",
    "ra8m2_TFM_test_crypto_gcc",
    "ra8m2_TFM_test_attestation_gcc",
    "ra8m2_TFM_test_storage_gcc",
    "ra8m2_TFM_update_gcc",
]

TZ_E2LITE = 'key="com.renesas.hardwaredebug.arm.e2lite.setTZBoundaries" value="true"'
TZ_E2LITE_OFF = 'key="com.renesas.hardwaredebug.arm.e2lite.setTZBoundaries" value="false"'


def convert(text: str, gcc_name: str, iar_name: str) -> tuple[str, list[str]]:
    notes = []
    for gcc_tree, iar_tree in TREE_MAP:
        n = text.count("\\" + gcc_tree + "\\")
        if n:
            text = text.replace("\\" + gcc_tree + "\\", "\\" + iar_tree + "\\")
            notes.append(f"{gcc_tree}->{iar_tree} x{n}")
    text = text.replace(gcc_name, iar_name)

    if TZ_E2LITE in text:
        text = text.replace(TZ_E2LITE, TZ_E2LITE_OFF)
        notes.append("e2lite setTZBoundaries true->false")
    return text, notes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report what would change without writing")
    a = ap.parse_args()

    rc = 0
    for gcc_name in LAUNCHES:
        src = LAUNCH_DIR / f"{gcc_name}.launch"
        if not src.is_file():
            print(f"  MISSING {src.name}")
            rc = 1
            continue
        iar_name = gcc_name[:-len("_gcc")] + "_iar"
        text, notes = convert(src.read_text(encoding="utf-8"), gcc_name, iar_name)

        # Both TZ keys must read false before this is written anywhere near hardware.
        bad = [ln for ln in text.splitlines()
               if "setTZBoundaries" in ln and 'value="true"' in ln]
        if bad:
            print(f"  REFUSED {iar_name}: setTZBoundaries still true -> {bad}")
            rc = 1
            continue
        # Every GCC tree name must be gone, or a launch would flash GCC images.
        left = [g for g, _ in TREE_MAP if "\\" + g + "\\" in text]
        if left:
            print(f"  REFUSED {iar_name}: GCC trees remain {left}")
            rc = 1
            continue

        out = LAUNCH_DIR / f"{iar_name}.launch"
        if a.check:
            state = "same" if out.is_file() and out.read_text(encoding="utf-8") == text \
                    else "would write"
            print(f"  {state:<12} {out.name}  [{', '.join(notes)}]")
        else:
            out.write_text(text, encoding="utf-8")
            print(f"  wrote {out.name}  [{', '.join(notes)}]")
    return rc


if __name__ == "__main__":
    sys.exit(main())
