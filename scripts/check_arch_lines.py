#!/usr/bin/env python3
"""Verify BUILD_ARCHITECTURE.md's port line citations still point at the right construct.

    python scripts/check_arch_lines.py            # check, exit 1 on any mismatch
    python scripts/check_arch_lines.py --list     # print what each cited line holds

Exit codes:  0 all citations resolve   1 at least one is stale   2 no TF-M checkout beside
this repo (the pre-commit hook skips the check in that case rather than calling it)

WHY THIS EXISTS
---------------
The reference documents cite line numbers in the TF-M port, in upstream TF-M and in this
repository's own scripts. 39 port citations went stale TWICE in a single day, both times
because a *comment* was edited above the block - once by the PXN correction (2c6d4feb2), once
by the D129 comment pass. Neither edit changed a line of CMake. The 16 upstream citations were
untouched by both. check_docs.py cannot catch this class: the file exists and the D-numbers
resolve, so every reference stays "valid" while pointing at the wrong line.

A line number that silently drifts is worse than no line number, because a reader who follows
it and finds a plausible-looking neighbouring construct will believe it.

WHAT IT CHECKS
--------------
A table below pairs each citation with a regex the cited line must match. It does NOT re-derive
the numbers or edit anything - it reports. Fixing means editing the Markdown, which is where
the prose explaining each block lives.

The table is the contract. Adding a citation to the document means adding a row here.
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TFM = os.path.normpath(os.path.join(ROOT, "..", "trusted-firmware-m"))
PORT = os.path.join(TFM, "platform", "ext", "target", "renesas")
DOC = os.path.join(ROOT, "BUILD_ARCHITECTURE.md")

# (part, line, regex the line must match, what the document says is there)
CITES = [
    ("ra6m5",  234, r"^set\(FSP_MODULES_S\s",                    "FSP_MODULES_S"),
    ("ra6m5",  238, r"^set\(FSP_MODULES_BL2\s",                  "FSP_MODULES_BL2"),
    ("ra6m5",  247, r"^set\(FSP_MODULE_DIRS_bsp\s",              "FSP_MODULE_DIRS_bsp"),
    ("ra6m5",  249, r"^set\(FSP_MODULE_DIRS_sce\s",              "FSP_MODULE_DIRS_sce"),
    ("ra6m5",  266, r"^set\(FSP_MODULES_NEVER_BUILT\s",          "FSP_MODULES_NEVER_BUILT"),
    ("ra6m5",  269, r"^function\(fsp_add_modules",               "fsp_add_modules definition"),
    ("ra6m5",  293, r"^\s+message\(WARNING$",                    "the unclaimed-directory warning"),
    ("ra6m5",  384, r"^fsp_add_modules\(s\s",                    "fsp_add_modules(s ...)"),
    ("ra6m5",  385, r"^target_link_libraries\(platform_s PUBLIC", "platform_s PUBLIC FSP modules"),
    ("ra6m5",  387, r"^target_sources\(platform_s PRIVATE",      "platform_s sources"),
    ("ra6m5",  416, r"tfm_hal_nvic\.c",                          "the common IRQ HAL"),
    ("ra6m5",  425, r"tfm_timer0_irq\.c",                        "the AGT0 fixture handler"),
    ("ra6m5",  453, r"^target_sources\(tfm_sprt",                "tfm_sprt sources"),
    ("ra6m5",  517, r"^target_sources\(tfm_spm",                 "tfm_spm sources"),
    ("ra6m5",  607, r"^target_sources\(tfm_s PRIVATE",           "tfm_s sources"),
    ("ra6m5",  682, r"Driver_USART\.c",                          "Driver_USART.c, secure"),
    ("ra6m5",  695, r"^\s+fsp_add_modules\(bl2\s",               "fsp_add_modules(bl2 ...)"),
    ("ra6m5",  696, r"^\s+target_link_libraries\(platform_bl2 PUBLIC", "platform_bl2 PUBLIC FSP modules"),
    ("ra6m5",  704, r"^\s+target_sources\(platform_bl2 PRIVATE$", "platform_bl2 sources"),
    ("ra6m5",  728, r"^\s+target_sources\(bl2 PRIVATE$",         "bl2 sources"),
    ("ra6m5",  735, r"^\s+if\(CRYPTO_HW_ACCELERATOR\)",          "the accelerator-only bl2 block"),
    ("ra6m5",  747, r"^\s+target_sources\(platform_bl2 PRIVATE$", "platform_bl2 RTT stdout"),
    ("ra6m5",  837, r"add_custom_target\(ra6m5_orphan_check",    "the orphan-section check"),
    ("ra6m5",  915, r"add_custom_target\(ra6m5_ofs_check",       "the OFS guard"),
    ("ra6m5",  958, r"add_custom_target\(ra6m5_safe_bin",        "--emit-safe-bin"),
    ("ra6m5", 1016, r"^\s*set\(RA6M5_NS_IN_SPE_BUILD",           "the NS_IN_SPE_BUILD option"),
    ("ra6m5", 1021, r"^if\(FSP_NS_APP_DIR AND RA6M5_NS_IN_SPE_BUILD", "the NS_IN_SPE_BUILD guard"),
    ("ra6m5", 1065, r"^\s+target_sources\(tfm_ns PRIVATE",       "tfm_ns sources"),

    ("ra8m2",  537, r"^target_sources\(platform_s PRIVATE",      "platform_s sources"),
    ("ra8m2",  595, r"^target_sources\(tfm_sprt",                "tfm_sprt sources"),
    ("ra8m2",  648, r"^target_sources\(tfm_spm",                 "tfm_spm sources"),
    ("ra8m2",  724, r"^target_sources\(tfm_s PRIVATE",           "tfm_s sources"),
    ("ra8m2",  799, r"Driver_USART\.c",                          "Driver_USART.c, secure"),
    ("ra8m2",  821, r"^\s+target_sources\(platform_bl2 PRIVATE$", "platform_bl2 sources"),
    ("ra8m2",  843, r"^\s+target_sources\(bl2 PRIVATE$",         "bl2 sources, block 1"),
    ("ra8m2",  854, r"^\s+target_sources\(bl2 PRIVATE$",         "bl2 sources, block 2"),
    ("ra8m2",  857, r"^\s+if\(CRYPTO_HW_ACCELERATOR\)",          "the accelerator-only ra_sce_init block"),
    ("ra8m2",  858, r"^\s+target_sources\(bl2 PRIVATE$",         "bl2 sources, block 3"),
    ("ra8m2",  868, r"^\s+target_sources\(platform_bl2 PRIVATE$", "platform_bl2 RTT stdout"),
    ("ra8m2", 1204, r"^\s+target_sources\(tfm_ns PRIVATE",       "tfm_ns sources"),
]

# Upstream citations. Separate because these move only when TF-M is uprevved.
UPSTREAM = [
    ("secure_fw/CMakeLists.txt",                        51, r"^target_link_libraries\(secure_fw"),
    ("secure_fw/CMakeLists.txt",                        57, r"^target_link_libraries\(tfm_s"),
    ("secure_fw/spm/CMakeLists.txt",                    95, r"^target_link_libraries\(tfm_spm"),
    ("secure_fw/partitions/lib/runtime/CMakeLists.txt", 39, r"^target_link_libraries\(tfm_sprt"),
    ("interface/CMakeLists.txt",                        29, r"^target_link_libraries\(psa_interface"),
    ("interface/CMakeLists.txt",                        37, r"TFM_ISOLATION_LEVEL"),
    ("interface/CMakeLists.txt",                        40, r"CONFIG_TFM_PARTITION_META"),
    ("platform/CMakeLists.txt",                         95, r"^target_link_libraries\(platform_s"),
    ("platform/CMakeLists.txt",                        109, r"PLATFORM_DEFAULT_ATTEST_HAL.*tfm_sprt"),
    ("platform/CMakeLists.txt",                        125, r"CONFIG_TFM_ENABLE_MEMORY_PROTECT"),
    ("platform/CMakeLists.txt",                        126, r"TFM_PXN_ENABLE"),
    ("bl2/CMakeLists.txt",                             147, r"^target_link_libraries\(bl2"),
    ("bl2/ext/mcuboot/CMakeLists.txt",                  30, r"^target_link_libraries\(bootutil"),
    ("bl2/ext/mcuboot/CMakeLists.txt",                  70, r"^target_link_libraries\(bl2"),
    ("config/config_base.cmake",                        17, r"CMAKE_INSTALL_PREFIX"),
    ("config/check_config.cmake",                       91, r"TFM_PXN_ENABLE"),
    # Added after F320 found ~15 cited lines with no row. The gap was not theoretical:
    # writing the BRIDGING_FILES fix in the same pass, I cited ra8m2's
    # FSP_EXCLUDED_MODULES at :159 when it is at :112, and nothing objected.
    ("config/config_base.cmake",                       116, r"PLATFORM_DEFAULT_ATTEST_HAL"),
    ("platform/ext/common/tfm_hal_isolation_v8m.c",     268, r"PLATFORM_STATIC_MPU_REGIONS"),
]

# Port files cited by full path. These move with a PORT commit, exactly like the
# CITES rows above; they are listed separately only because the citation gives a
# path rather than a part name. A TF-M uprev does not move them (F341).
PORT_PATHS = [
    ("platform/ext/target/renesas/ra6m5/config.cmake",  127, r"CRYPTO_HW_ACCELERATOR\s"),
    ("platform/ext/target/renesas/ra6m5/config.cmake",  199, r"PLATFORM_DEFAULT_ATTEST_HAL"),
    ("platform/ext/target/renesas/ra8m2/config.cmake",  225, r"PLATFORM_DEFAULT_ATTEST_HAL"),
    ("platform/ext/target/renesas/ra6m5/CMakeLists.txt", 112, r"^\s+set\(FSP_EXCLUDED_MODULES"),
    ("platform/ext/target/renesas/ra8m2/CMakeLists.txt", 112, r"^\s+set\(FSP_EXCLUDED_MODULES"),
    ("platform/ext/target/renesas/ra6m5/CMakeLists.txt", 1023, r"fsp_collect_sources\(FSP_NS_SOURCES"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_module_common.cmake", 33, r"add_library\(.*STATIC"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_flash.cmake", 21, r"fsp_bsp_\$\{FSP_MODULE_ROLE\}"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_sce.cmake",   51, r"fsp_bsp_\$\{FSP_MODULE_ROLE\}"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_agt.cmake",   40, r"fsp_bsp_\$\{FSP_MODULE_ROLE\}"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_bsp.cmake",  105, r"src/rm_mcuboot_port\"$"),
    ("platform/ext/target/renesas/ra6m5/cmake/modules/fsp_bsp.cmake",  106, r"mcu-tools/MCUboot/boot/bootutil/include"),
]

# Citations into this repository's own files. Separate list because the path root differs.
LOCAL = [
    ("scripts/reg_build_gcc.bat",      150, r"cmake -S %TFM_TESTS%\\tests_reg\\spe"),
    ("scripts/reg_build_gcc.bat",      174, r"cmake -S %TFM_TESTS%\\tests_reg -B"),
    ("scripts/app_build_ra8m2_gcc.bat", 50, r"cmake -S %TFM_SRC% -B"),
    ("scripts/app_build_ra8m2_gcc.bat", 69, r"ra8m2\\ns_app -B"),
]


def lines(path):
    return io.open(path, encoding="utf-8", newline="").read().replace("\r\n", "\n").split("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", action="store_true", help="print each cited line's content")
    a = ap.parse_args()

    if not os.path.isdir(TFM):
        print("check_arch_lines: no trusted-firmware-m beside this repo at %s" % TFM)
        return 2

    cache, bad, checked = {}, [], 0
    for part, n, pat, what in CITES:
        p = os.path.join(PORT, part, "CMakeLists.txt")
        if p not in cache:
            cache[p] = lines(p)
        L = cache[p]
        got = L[n - 1] if 0 < n <= len(L) else "<past end of file>"
        ok = bool(re.search(pat, got))
        checked += 1
        if a.list:
            print("%-6s %-5d %-7s %s" % (part, n, "ok" if ok else "STALE", got.strip()[:84]))
        if not ok:
            hits = [i + 1 for i, l in enumerate(L) if re.search(pat, l)]
            bad.append("%s/CMakeLists.txt:%d should be %s\n      is: %s\n      found at: %s"
                       % (part, n, what, got.strip()[:76],
                          ", ".join(str(h) for h in hits) or "nowhere"))

    for rel, n, pat in UPSTREAM + PORT_PATHS:
        p = os.path.join(TFM, rel)
        if not os.path.exists(p):
            bad.append("%s is missing" % rel)
            continue
        if p not in cache:
            cache[p] = lines(p)
        L = cache[p]
        got = L[n - 1] if 0 < n <= len(L) else "<past end of file>"
        ok = bool(re.search(pat, got))
        checked += 1
        if a.list:
            print("%-30s %-5d %-7s %s" % (rel, n, "ok" if ok else "STALE", got.strip()[:60]))
        if not ok:
            hits = [i + 1 for i, l in enumerate(L) if re.search(pat, l)]
            bad.append("%s:%d should match /%s/\n      is: %s\n      found at: %s"
                       % (rel, n, pat, got.strip()[:70],
                          ", ".join(str(h) for h in hits) or "nowhere"))

    for rel, n, pat in LOCAL:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            bad.append("%s is missing" % rel)
            continue
        if p not in cache:
            cache[p] = lines(p)
        L = cache[p]
        got = L[n - 1] if 0 < n <= len(L) else "<past end of file>"
        ok = bool(re.search(pat, got))
        checked += 1
        if a.list:
            print("%-30s %-5d %-7s %s" % (rel, n, "ok" if ok else "STALE", got.strip()[:60]))
        if not ok:
            hits = [i + 1 for i, l in enumerate(L) if re.search(pat, l)]
            bad.append("%s:%d should match /%s/\n      is: %s\n      found at: %s"
                       % (rel, n, pat, got.strip()[:70],
                          ", ".join(str(h) for h in hits) or "nowhere"))

    # Report the count, always. D121's rule: a comparison that reports "no differences"
    # must say how many things it compared, or a silent zero-match reads as a pass.
    if bad:
        print("check_arch_lines: %d of %d citations are stale\n" % (len(bad), checked))
        for b in bad:
            print("  - %s" % b)
        print("\nFix BUILD_ARCHITECTURE.md and this table together.")
        return 1
    print("check_arch_lines: ok - %d citations checked, all resolve" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
