#!/usr/bin/env python3
"""Produce secondary-slot images for an MCUboot upgrade test.

    python sign_secondary.py <spe-build-dir> [ns-build-dir] [--version X.Y.Z]

    python sign_secondary.py C:/b/m2gflih/build-spe C:/b/m2gflihns

Writes tfm_s_signed_secondary.bin beside tfm_s_signed.bin, and the same for the
non-secure image if an NS build directory is given.

WHY A SCRIPT AND NOT A CMAKE TARGET
-----------------------------------
TF-M has no secondary-image signing target - checked on upstream/main as well as our base.
Adding one would mean touching bl2/ext/mcuboot/CMakeLists.txt, which is currently
byte-identical to TF-Mv2.2.0 and which DECISIONS D091 went to some trouble to keep that way.
An upgrade test is a bring-up activity, not something every build should pay for, so it lives
here instead.

WHAT AN UPGRADE TEST NEEDS
--------------------------
The secondary image must differ from the primary in a way MCUboot will act on:

  * a HIGHER VERSION. With MCUBOOT_UPGRADE_STRATEGY=OVERWRITE_ONLY and downgrade prevention,
    BL2 installs the secondary only if its version exceeds the primary's. Default here is to
    bump the primary's minor version.
  * the TRAILER MAGIC, which --pad writes. Without it BL2 sees an empty slot and reports
    "Secondary image of image pair (N.) is unreachable. Treat it as empty".

Everything else - key, alignment, header size, security counter, dependencies, the measured
boot record - must match the primary exactly, or BL2 rejects the image for a reason that has
nothing to do with the upgrade path. This script therefore does not invent a command line: it
reads the one the build actually used out of build.ninja and changes only -v and the output.

AFTER FLASHING
--------------
BL2 should log the swap, then boot an image whose version banner is the bumped one. A second
reset must NOT re-install: in OVERWRITE_ONLY the secondary is erased once installed.
"""

import argparse
import re
import shlex
import subprocess
import sys
from pathlib import Path


def find_sign_command(build_dir: Path, signed_name: str) -> list[str]:
    """Recover the exact imgtool invocation the build used for `signed_name`."""
    ninja = build_dir / "build.ninja"
    if not ninja.is_file():
        sys.exit(f"no build.ninja in {build_dir} - is that a configured build directory?")

    text = ninja.read_text(encoding="utf-8", errors="replace")
    # The COMMAND line that runs wrapper.py and emits this particular signed image.
    for line in text.splitlines():
        if "wrapper.py" in line and signed_name in line:
            # Strip the cmd.exe /C "cd /D <dir> && ..." wrapper, keep the python invocation.
            m = re.search(r'(["\']?[^"\']*python[^"\']*["\']?\s+\S*wrapper\.py.*?)(?:\s+&&|\s*"$|$)',
                          line)
            if m:
                argv = [a.strip('"') for a in shlex.split(m.group(1), posix=False)]
                # argv[0] is whatever interpreter CMake found, often the WindowsApps store
                # alias, which CreateProcess refuses with "Access is denied" when invoked by
                # path. The interpreter already running this script works, so use it.
                argv[0] = sys.executable
                return argv
    sys.exit(f"could not find the signing command for {signed_name} in {ninja}")


def bump(version: str) -> str:
    """2.2.0 -> 2.3.0. Only the dotted part; imgtool also accepts a +build suffix."""
    core = version.split("+", 1)[0]
    parts = core.split(".")
    while len(parts) < 3:
        parts.append("0")
    parts[1] = str(int(parts[1]) + 1)
    return ".".join(parts[:3])


def sign_secondary(build_dir: Path, signed_name: str, version: str | None) -> Path | None:
    argv = find_sign_command(build_dir, signed_name)

    # The version flag. The secure image is signed by TF-M's own rule, which uses the short
    # "-v"; the non-secure image is signed from the exported api_ns/image_signing tree, whose
    # generated rule uses the long "--version". Accept either.
    vi = next((argv.index(f) for f in ("-v", "--version") if f in argv), None)
    if vi is None:
        sys.exit(f"no -v/--version in the recovered command for {signed_name}")
    primary_version = argv[vi + 1]
    argv[vi + 1] = version or bump(primary_version)

    # The last two positional arguments are <input> <output>.
    out = Path(argv[-1].strip('"'))
    secondary = out.with_name(out.stem + "_secondary" + out.suffix)
    argv[-1] = str(secondary)

    print(f"  {out.name}")
    print(f"    version {primary_version} -> {argv[vi + 1]}")
    rc = subprocess.run(argv, cwd=build_dir).returncode
    if rc != 0:
        print(f"    FAILED (exit {rc})")
        return None

    # The build copies the signed image next to bl2; do the same so the launch finds it.
    bin_dir = build_dir / "bin"
    if bin_dir.is_dir() and secondary.parent != bin_dir:
        dest = bin_dir / secondary.name
        dest.write_bytes(secondary.read_bytes())
        secondary = dest
    print(f"    -> {secondary}  ({secondary.stat().st_size} bytes)")
    return secondary


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spe", type=Path, help="SPE build directory (holds build.ninja and bin/)")
    ap.add_argument("ns", type=Path, nargs="?", help="NS build directory, optional")
    ap.add_argument("--version", help="explicit version instead of bumping the minor")
    a = ap.parse_args()

    print("Signing secondary-slot images")
    ok = sign_secondary(a.spe, "tfm_s_signed.bin", a.version) is not None
    if a.ns:
        ok &= sign_secondary(a.ns, "tfm_ns_signed.bin", a.version) is not None
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
