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
# Usage:  ./sign_ra6e1_secondary.sh [S_VERSION] [NS_VERSION]
# Output: <build>/bin/tfm_s_signed_secondary.bin   -> flash at 0x00018000
#         <build>/bin/tfm_ns_signed_secondary.bin  -> flash at 0x000C8000
set -eu

TFM_DIR="C:/Users/Michael/Renesas_work/repos/trusted-firmware-m"
BUILD_DIR="${TFM_DIR}/build_ra6e1"
PYTHON="${PYTHON:-python3}"

# Primaries are S 2.2.0 / NS 0.0.0 (MCUBOOT_IMAGE_VERSION_* in the CMake cache). These must be
# strictly greater or MCUboot leaves the secondary alone and boots the primary unchanged - which
# looks exactly like a failed upgrade.
S_VERSION="${1:-2.3.0}"
NS_VERSION="${2:-0.0.1}"

# Security counter stays 1, matching the primaries. Raising it would trip rollback protection
# and make the primaries permanently unbootable - do not bump it while iterating.
SEC_COUNTER=1

# Dependency TLVs, copied from the generated build commands: image 0 requires image 1 >= this,
# and vice versa. Both bumped versions still satisfy 0.0.0+0.
DEP_S="(1,0.0.0+0)"
DEP_NS="(0,0.0.0+0)"

# wrapper.py imports the imgtool package from the current directory, so it must run from
# mcuboot's scripts/ - the same WORKING_DIRECTORY the build uses.
cd "${BUILD_DIR}/lib/ext/mcuboot-src/scripts"

sign() {
    img="$1"; ver="$2"; key="$3"; dep="$4"
    echo "  ${img}: version ${ver}"
    "${PYTHON}" "${TFM_DIR}/bl2/ext/mcuboot/scripts/wrapper/wrapper.py" \
        -v "${ver}" \
        --layout "${BUILD_DIR}/bl2/ext/mcuboot/CMakeFiles/signing_layout_${img#tfm_}.dir/./signing_layout_${img#tfm_}.o" \
        -k "${TFM_DIR}/bl2/ext/mcuboot/${key}" \
        --public-key-format hash \
        --align 128 --pad --pad-header \
        -H 0x200 -s "${SEC_COUNTER}" -L 128 \
        -d "${dep}" \
        --overwrite-only \
        --measured-boot-record \
        "${BUILD_DIR}/bin/${img}.bin" \
        "${BUILD_DIR}/bin/${img}_signed_secondary.bin"
}

echo "Signing secondary-slot images (align 128):"
sign tfm_s  "${S_VERSION}"  root-EC-P256.pem   "${DEP_S}"
sign tfm_ns "${NS_VERSION}" root-EC-P256_1.pem "${DEP_NS}"

echo
echo "Done. Flash to the SECONDARY slots:"
echo "  ${BUILD_DIR}/bin/tfm_s_signed_secondary.bin   -> 0x00018000  (0x40000)"
echo "  ${BUILD_DIR}/bin/tfm_ns_signed_secondary.bin  -> 0x000C8000  (0x30000)"
