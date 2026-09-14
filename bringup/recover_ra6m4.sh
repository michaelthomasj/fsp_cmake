#!/usr/bin/env bash
#
# RA6M4 recovery / device-state helper.
#
# WHAT ACTUALLY RECOVERS A LOCKED-OUT BOARD (verified on this bench):
#   Renesas Device Partition Manager GUI -> "Initialize device" over J-Link.
#     e2 studio / RASC:  Run -> Renesas Debug Tools -> Renesas Device Partition Manager
#     tick "Initialize device", Target MCU connection = J-Link, Run.
#   This drives J-Link's native RA DLM support over the NORMAL SWD debug
#   connection. It needs NO boot-mode jumper. It erases all flash + resets the
#   memory partitions and DLM state to factory. A "connects but won't erase"
#   board (restricted DLM state) is recovered this way, not by RFP.
#
# WHAT DOES NOT WORK ON THIS BENCH:
#   The RDPM command-line tool (RenesasDevicePartitionManagerCmd.exe) only
#   reaches the device through BOOT firmware (-bootInterface SCI|SWD). On the
#   EK-RA6M4 with its on-board J-Link, boot mode is not reachable that way even
#   with the J16 (MD) jumper fitted -- it fails with
#     "Establishing connection: FAILED! Unable to retrieve device's boot code."
#   This was observed on a KNOWN-GOOD board too, so that failure says nothing
#   about board health. Use the GUI path above. The CLI is only useful in a
#   production fixture that actually wires up SCI/USB boot mode.
#
# This script itself only does the SAFE, READ-ONLY things:
#   ./recover_ra6m4.sh status   # J-Link connect + read OFS + reset vector (read-only)
#   ./recover_ra6m4.sh help     # print the GUI recovery steps
#
set -u

JLINK_DIR=$(ls -d "/c/Program Files/SEGGER/JLink"* 2>/dev/null | sort -V | tail -1)
JLINK="$JLINK_DIR/JLink.exe"

print_help() {
  cat <<'EOF'
=== Recover a locked-out / bricked EK-RA6M4 ===
The board "connects and reads but will not erase or program" -> it is in a
restricted TrustZone DLM state (e.g. NSECSD), NOT dead flash.

Recovery (dev bench, no jumper needed):
  1. Open e2 studio or RASC.
  2. Run -> Renesas Debug Tools -> Renesas Device Partition Manager.
  3. Tick "Initialize device".  (this alone; all other actions grey out)
  4. Target MCU connection = J-Link.  Click Run.
  5. Wait for "Initialize: SUCCESSFUL". Board is now factory-erased & unlocked.

Then re-program: cmake --build <build> --target signed_images, and flash
(see bringup_ra6m4.sh). After Initialize the DLM state is back to SSD.

Verify state at any time (read-only):
  ./recover_ra6m4.sh status
A fully-erased board reads all 0xFFFFFFFF at 0x0 and at 0x0100A100/A200/A280.
EOF
}

case "${1:-status}" in
  status)
    if [ ! -x "$JLINK" ]; then echo "ERROR: JLink.exe not found under /c/Program Files/SEGGER"; exit 1; fi
    echo "=== J-Link read-only status (OFS + reset vector) ==="
    S=$(mktemp --suffix=.jlink)
    cat > "$S" <<'EOF'
si SWD
speed 4000
device R7FA6M4AF
connect
mem32 0100A100 4
mem32 0100A200 4
mem32 0100A280 4
mem32 00000000 8
exit
EOF
    "$JLINK" -CommanderScript "$S" -ExitOnError 0 2>&1 | \
      sed -n '/Cortex-M33 identified/,$p'
    rm -f "$S"
    echo ""
    echo "OFS0=0x0100A100  OFS1_SEC=0x0100A200  OFS1_SEL=0x0100A280  (all FF = erased/factory)"
    echo "Reset vector @0x0 = FF -> no image programmed. Run './recover_ra6m4.sh help' to re-flash."
    ;;
  help|-h|--help) print_help ;;
  *) echo "usage: $0 {status|help}"; print_help; exit 1 ;;
esac
