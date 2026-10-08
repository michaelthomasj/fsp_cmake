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

THE HOST PROJECT IS THE IAR ONE, which DIVERGES from RA6M5 on purpose. RA6M5's IAR launches
name ra6m5_gcc_nonsecure in PROJECT_ATTR - both toolchains hosted by the GCC project. Here
each toolchain names its own, because serverParam builds the J-Link settings path from
${ProjName}:

    -uJLinkSetting= "${workspace_loc:/${ProjName}}/${LaunchConfigName}.jlink"

so hosting both toolchains in one project makes them share a directory for those sidecars.
Nothing is built either way - ATTR_BUILD_BEFORE_LAUNCH_ATTR is 2 (disabled) - so the host
project only supplies that name and the debug context.

PROJECT_BUILD_CONFIG_AUTO_ATTR is false, which is what all six working RA6M5 IAR launches
use. The GCC launches have true, so it cannot simply be inherited.
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

# Attributes that must change with the toolchain, not just the build paths. Each must match
# exactly once; convert() asserts that, so an e2 rewrite that reshapes one is caught here
# rather than by a launch that quietly uses the wrong project.
GCC_PROJ = "ra8m2_gcc_CPU0_nonsecure"
IAR_PROJ = "ra8m2_iar_CPU0_nonsecure"
PROJECT_SUBS = [
    (f'<stringAttribute key="org.eclipse.cdt.launch.PROJECT_ATTR" value="{GCC_PROJ}"/>',
     f'<stringAttribute key="org.eclipse.cdt.launch.PROJECT_ATTR" value="{IAR_PROJ}"/>'),
    ('<booleanAttribute key="org.eclipse.cdt.launch.PROJECT_BUILD_CONFIG_AUTO_ATTR" value="true"/>',
     '<booleanAttribute key="org.eclipse.cdt.launch.PROJECT_BUILD_CONFIG_AUTO_ATTR" value="false"/>'),
    (f'<listEntry value="/{GCC_PROJ}"/>',
     f'<listEntry value="/{IAR_PROJ}"/>'),
]


def convert(text: str, gcc_name: str, iar_name: str) -> tuple[str, list[str]]:
    notes = []
    for gcc_tree, iar_tree in TREE_MAP:
        n = text.count("\\" + gcc_tree + "\\")
        if n:
            text = text.replace("\\" + gcc_tree + "\\", "\\" + iar_tree + "\\")
            notes.append(f"{gcc_tree}->{iar_tree} x{n}")
    text = text.replace(gcc_name, iar_name)

    for before, after in PROJECT_SUBS:
        n = text.count(before)
        if n != 1:
            raise SystemExit(f"{gcc_name}: expected 1 of {before[:72]}..., found {n}")
        text = text.replace(before, after, 1)
    notes.append(f"host project -> {IAR_PROJ}")

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
        if GCC_PROJ in text:
            print(f"  REFUSED {iar_name}: still names the GCC project")
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
