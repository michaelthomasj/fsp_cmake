#!/usr/bin/env bash
#
# RA6M4 unbrick / device-state tool — Renesas Device Partition Manager (RDPM) CLI.
#
# USE THIS, NOT RFP, when the board "connects and reads but will not erase or program".
# That symptom is a TrustZone *access-permission* state (DLM = NSECSD/DPL), not dead
# flash: in NSECSD the debugger is restricted to non-secure regions, so erasing the
# secure area (where BL2 lives, 0x0-0x4F3FF) is refused. RFP over SWD cannot fix this.
# RDPM in BOOT MODE can, because it talks to the MCU's boot firmware instead.
#
#   ./recover_ra6m4.sh status      # read DLM state + IDAU boundaries (READ-ONLY, safe)
#   ./recover_ra6m4.sh initialize  # ERASE EVERYTHING, back to factory (destructive)
#   ./recover_ra6m4.sh ssd         # transition DLM state back to SSD
#   ./recover_ra6m4.sh boundaries  # program the TF-M TZ boundaries (see DESIGN.md 7.1)
#
# ⚠ HARDWARE PREREQUISITE for every command here:
#   EK-RA6M4 must be in BOOT MODE -> place a jumper on **J16** (MD/P201), then
#   power-cycle the board. Leave J16 OPEN for normal single-chip operation.
#   Without the jumper you get: "Establishing connection: FAILED! Unable to
#   retrieve device's boot code."
#
# Note: INITIALIZE is refused when the device is in CM state, and is permanently
# disabled by PERMANENT block protection (PBPS). This port emits neither BPS nor
# PBPS (only ofs0 / ofs1_sec / ofs1_sel), so that path stays open.
set -u

# --- locate the RDPM CLI (newest Renesas support area wins) ---
# Use the 32-bit build: it ships its own JLinkARM.dll. The x64 build does not and
# fails with "Could not load library: ...\x64\JLinkARM.dll".
RDPM=$(ls -d /c/Users/*/.eclipse/com.renesas.platform_*/DebugComp/RA/DevicePartitionManager/RenesasDevicePartitionManagerCmd.exe 2>/dev/null \
       | sort -V | tail -1)
if [ -z "${RDPM:-}" ] || [ ! -f "$RDPM" ]; then
  echo "ERROR: RenesasDevicePartitionManagerCmd.exe not found."
  echo "  It lives in the Renesas support area:"
  echo "  <SUPPORT_FILE_LOCATION>/DebugComp/RA/DevicePartitionManager/"
  echo "  (Help -> About -> Installation Details -> 'e2 studio support area')"
  exit 1
fi
echo "RDPM: $RDPM"

COMMON="-deviceFamily RA -emuType JLINK -bootInterface SWD"

# TF-M TrustZone boundaries for this port (DESIGN.md 7.1 / 7).
# Code Secure 317K + Code NSC 3K = 320K -> NS partition starts at 0x50000 (32K-aligned).
IDAU="-idauCFS 317 -idauCFNSC 3 -idauDFS 8 -idauSRAMS 128 -idauSRAMNSC 0 -idauCFSIP 0"

case "${1:-status}" in
  status)
    echo "=== Reading device status (read-only) ==="
    "$RDPM" -action STATUS $COMMON
    ;;
  initialize)
    echo "*** DESTRUCTIVE: erases ALL flash + resets memory partitions to factory ***"
    printf "Type ERASE to continue: "; read -r c
    [ "$c" = "ERASE" ] || { echo "aborted."; exit 1; }
    "$RDPM" -action INITIALIZE $COMMON
    echo "--- re-reading status ---"
    "$RDPM" -action STATUS $COMMON
    ;;
  ssd)
    echo "=== Transition DLM state -> SSD (Secure Software Development) ==="
    "$RDPM" -action DLM -dlmTargetState SSD $COMMON
    ;;
  boundaries)
    echo "=== Programming TF-M TZ boundaries: $IDAU ==="
    "$RDPM" -action BOUNDARY,STATUS $IDAU $COMMON
    ;;
  *)
    echo "usage: $0 {status|initialize|ssd|boundaries}"; exit 1 ;;
esac
