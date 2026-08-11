#!/usr/bin/env bash
#
# One-command bring-up for the TF-M RA6M4: flash BL2 + secure + NS, then stream
# SEGGER RTT so you can watch the BL2 -> secure -> non-secure boot chain.
#
#   ./bringup_ra6m4.sh              # flash, then RTT from the SECURE control block
#   ./bringup_ra6m4.sh bl2          # RTT from the BL2 control block
#   ./bringup_ra6m4.sh ns           # RTT from the NS control block
#   ./bringup_ra6m4.sh noflash s    # skip flashing, just attach RTT (secure)
#
# Requires SEGGER J-Link tools installed. Device: R7FA6M4AF, SWD.
set -u

# --- locate J-Link tools (newest install wins) ---
JLINK_DIR=$(ls -d "/c/Program Files/SEGGER/JLink"* 2>/dev/null | sort -V | tail -1)
JLINK="$JLINK_DIR/JLink.exe"
RTTLOG="$JLINK_DIR/JLinkRTTLogger.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- RTT control-block addresses ---
# These MOVE whenever the images are rebuilt. Refresh with:
#   for f in bl2 tfm_s tfm_ns; do arm-none-eabi-nm ../../trusted-firmware-m/build_ra6m4_boot/bin/$f.a*f \
#     | grep ' _SEGGER_RTT$'; done
# Current values: build_ra6m4_boot on the Renesas_work machine, 2026-08-10
# (previous values were BL2 0x20002bd0 / S 0x2000baf8 / NS 0x20020854 - the OFS
#  restore and .ram_noinit changes shifted all three).
RTT_BL2=0x20002c24
RTT_SECURE=0x2000bb38
RTT_NS=0x200208a4

# --- parse args ---
DO_FLASH=1
SEL="secure"
for a in "$@"; do
  case "$a" in
    noflash) DO_FLASH=0 ;;
    bl2)     SEL="bl2" ;;
    s|secure) SEL="secure" ;;
    ns)      SEL="ns" ;;
  esac
done
case "$SEL" in
  bl2)    RTT_ADDR=$RTT_BL2 ;;
  ns)     RTT_ADDR=$RTT_NS ;;
  *)      RTT_ADDR=$RTT_SECURE ;;
esac

if [ ! -x "$JLINK" ]; then echo "ERROR: JLink.exe not found under /c/Program Files/SEGGER"; exit 1; fi

if [ "$DO_FLASH" = 1 ]; then
  echo "=== Flashing (bl2 @0x0, tfm_s @0x20000, tfm_ns @0x50000) ==="
  "$JLINK" -device R7FA6M4AF -if SWD -speed 4000 -autoconnect 1 \
           -CommanderScript "$SCRIPT_DIR/flash_ra6m4.jlink"
  rc=$?
  if [ $rc -ne 0 ]; then echo "flash failed (rc=$rc)"; exit $rc; fi
fi

echo ""
echo "=== RTT capture from $SEL control block ($RTT_ADDR) ==="
echo "(RTTLogger resets the target and streams; Ctrl-C to stop. Log -> rtt_${SEL}.log)"
echo "Expected: [INF] Starting bootloader / Jumping to first slot (bl2),"
echo "          Booting TF-M v2.2.0 / Secure image initializing! (secure),"
echo "          [NS] non-secure world running (ns)."
"$RTTLOG" -Device R7FA6M4AF -If SWD -Speed 4000 -RTTAddress "$RTT_ADDR" "$SCRIPT_DIR/rtt_${SEL}.log"
