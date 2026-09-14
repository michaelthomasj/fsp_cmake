#!/bin/sh
# Sign SECONDARY-slot copies of the current RA6E1 TF-M images with bumped versions.
#
# Purpose: exercise the upgrade path. MCUboot only overwrites the primary slot when the
# secondary holds a VALID image with a HIGHER version, so the same payloads that are already
# running can be reused - only the version in the header has to differ. This is the first
# thing that makes BL2 actually WRITE code flash, which is what MCUBOOT_ALIGN_VAL=128 and the
# 128-byte program_unit exist for. Everything before this only ever read.
#
# The payloads are byte-identical to the primaries; nothing is rebuilt. That is deliberate -
# if the upgrade misbehaves it is the copy/trailer machinery, not a code difference.
#
# Re-signing rather than copying the primary .bin is required: the version lives in the image
# header, which is covered by the signature, so it cannot be patched after the fact.
#
# SPLIT BUILD (since 2026-08-30): the two images come from two different build trees and are
# signed with two different key/layout sets. The secure half still comes from the SPE build;
# the non-secure half comes from the NSPE build and uses the signing material the SPE
# EXPORTED into api_ns/image_signing/, which is what the NSPE build itself uses. Mirroring
# each build rather than assuming they share paths is the point - if the keys ever diverge,
# this follows instead of silently signing with the wrong one.
#
# Usage:  ./sign_ra6e1_secondary.sh [S_VERSION] [NS_VERSION]
# Output: <spe>/bin/tfm_s_signed_secondary.bin      -> flash at 0x00018000  (0x40000)
#         <nspe>/bin/tfm_ns_signed_secondary.bin    -> flash at 0x000C8000  (0x30000)
set -eu

TFM_DIR="C:/Users/Michael/Renesas_work/repos/trusted-firmware-m"
SPE_DIR="${TFM_DIR}/build_ra6e1"
NSPE_DIR="${TFM_DIR}/build_ra6e1_ns"
API_NS="${SPE_DIR}/api_ns"
PYTHON="${PYTHON:-python3}"

S_VERSION="${1:-2.3.0}"
NS_VERSION="${2:-0.0.1}"

# Security counter stays 1, matching the primaries. Raising it would trip rollback protection
# and make the primaries permanently unbootable - do not bump it while iterating.
SEC_COUNTER=1

# Dependency TLVs, copied from the generated build commands: image 0 requires image 1 >= this,
# and vice versa. Both bumped versions still satisfy 0.0.0+0.
DEP_S="(1,0.0.0+0)"
DEP_NS="(0, 0.0.0+0)"

# --measured-boot-record is passed because the BUILD passes it, for both images. Note that
# it is on despite the port's config.cmake setting MCUBOOT_MEASURED_BOOT OFF: config_base.cmake
# force-sets it ON with a plain set() whenever CONFIG_TFM_BOOT_STORE_MEASUREMENTS and
# CONFIG_TFM_BOOT_STORE_ENCODED_MEASUREMENTS are on, and a plain set() shadows the cache. The
# secondary must be signed exactly like the primary apart from the version, so it matches the
# build rather than the config.
MEASURED_BOOT="--measured-boot-record"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -f "${SPE_DIR}/bin/tfm_s.bin" ] || \
    die "${SPE_DIR}/bin/tfm_s.bin not found. Build the SPE first."
[ -f "${NSPE_DIR}/bin/tfm_ns.bin" ] || \
    die "${NSPE_DIR}/bin/tfm_ns.bin not found. The NS image moved to the NSPE build on
       2026-08-30 - build it with 'cmake --build ${NSPE_DIR}'. See
       platform/ext/target/renesas/ra6e1/ns_app/README.md."
[ -d "${API_NS}/image_signing" ] || \
    die "${API_NS}/image_signing not found. Run 'cmake --install ${SPE_DIR}' - that is the
       step that exports the signing keys and layout files."

# The primaries' versions, read from the build rather than assumed: the secondary version must
# be STRICTLY GREATER or MCUboot leaves the secondary alone and boots the primary unchanged,
# which looks exactly like a failed upgrade.
prim_ver() { grep -oE "^$1:[^=]*=.*" "${SPE_DIR}/CMakeCache.txt" | cut -d= -f2; }
echo "Primary versions in the build:  S $(prim_ver MCUBOOT_IMAGE_VERSION_S)  NS $(prim_ver MCUBOOT_IMAGE_VERSION_NS)"
echo "Signing secondaries as:         S ${S_VERSION}  NS ${NS_VERSION}"
echo

# wrapper.py imports the imgtool package from the CURRENT DIRECTORY, so each invocation has to
# run from a directory that contains one. The SPE build and the exported tree each ship their
# own copy; use whichever belongs to the image being signed.

echo "  tfm_s  -> ${S_VERSION}"
cd "${SPE_DIR}/lib/ext/mcuboot-src/scripts"
"${PYTHON}" "${TFM_DIR}/bl2/ext/mcuboot/scripts/wrapper/wrapper.py" \
    -v "${S_VERSION}" \
    --layout "${SPE_DIR}/bl2/ext/mcuboot/CMakeFiles/signing_layout_s.dir/./signing_layout_s.o" \
    -k "${TFM_DIR}/bl2/ext/mcuboot/root-EC-P256.pem" \
    --public-key-format hash \
    --align 128 --pad --pad-header \
    -H 0x200 -s "${SEC_COUNTER}" -L 128 \
    -d "${DEP_S}" \
    --overwrite-only \
    ${MEASURED_BOOT} \
    "${SPE_DIR}/bin/tfm_s.bin" \
    "${SPE_DIR}/bin/tfm_s_signed_secondary.bin"

echo "  tfm_ns -> ${NS_VERSION}"
cd "${API_NS}/image_signing/scripts"
"${PYTHON}" "${API_NS}/image_signing/scripts/wrapper/wrapper.py" \
    --version "${NS_VERSION}" \
    --layout "${API_NS}/image_signing/layout_files/signing_layout_ns.o" \
    --key "${API_NS}/image_signing/keys/image_ns_signing_private_key.pem" \
    --public-key-format hash \
    --align 128 --pad --pad-header \
    -H 0x200 -s "${SEC_COUNTER}" -L 128 \
    -d "${DEP_NS}" \
    --overwrite-only \
    ${MEASURED_BOOT} \
    "${NSPE_DIR}/bin/tfm_ns.bin" \
    "${NSPE_DIR}/bin/tfm_ns_signed_secondary.bin"

echo
echo "Done. Flash to the SECONDARY slots:"
echo "  ${SPE_DIR}/bin/tfm_s_signed_secondary.bin    -> 0x00018000  (0x40000)"
echo "  ${NSPE_DIR}/bin/tfm_ns_signed_secondary.bin  -> 0x000C8000  (0x30000)"
echo
echo "Both rows are DISABLED in ra6e1_TFM.launch - enable them for the upgrade run, then"
echo "disable them again, or every subsequent connect re-arms the same upgrade."
