#!/usr/bin/env bash
#
# RA6E1 chip-lock experiment — capture the option/config area over J-Link so we can
# see EXACTLY when (if) it gets zeroed and PBPS is set during a flash cycle.
#
# RA6E1 is a faithful proxy for the RA6M4 lock: same flash/TZ/DLM features and the
# IDENTICAL config-area map (BPS @0x0100A1C0, PBPS @0x0100A1E0). The RA6E1 BL2 image
# emits only OFS0/OFS1_SEC/OFS1_SEL - NOT PBPS - so if PBPS goes to 0 after flashing,
# the zeroing came from the TOOL/flash operation, not the image. See DESIGN.md 8.4.
#
# PROTOCOL (run this at each step, label the output):
#   ./capture_config_ra6e1.sh before      # fresh/erased board  -> baseline (expect all FF)
#   <build the RA6E1 BL2 project>
#   <erase via Ozone/JLink>    ; ./capture_config_ra6e1.sh after_erase
#   <program via Ozone/JLink>  ; ./capture_config_ra6e1.sh after_program
#   <reset/run>                ; ./capture_config_ra6e1.sh after_reset
# Diff consecutive logs to find which operation zeros 0x0100A1E0 (PBPS).
#
# Reads are NON-DESTRUCTIVE. Device R7FA6E10F2CFP.
set -u

LABEL="${1:-capture}"
JLINK_DIR=$(ls -d "/c/Program Files/SEGGER/JLink"* 2>/dev/null | sort -V | tail -1)
JLINK="$JLINK_DIR/JLink.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/config_ra6e1_${LABEL}.log"
DEVICE="R7FA6E10F2CFP"

if [ ! -x "$JLINK" ]; then echo "ERROR: JLink.exe not found under /c/Program Files/SEGGER"; exit 1; fi

S=$(mktemp --suffix=.jlink)
cat > "$S" <<'EOF'
si SWD
speed 4000
device R7FA6E10F2CFP
connect
echo --- DLM state (0x400E002C bits[3:0]: 1=CM 2=SSD 3=NSECSD 4=DPL 5=LCK_DBG 6=LCK_BOOT) ---
mem32 400E002C 1
echo --- reset vector @0x0 (SP, Reset_Handler) ---
mem32 00000000 2
echo --- OFS / config area 0x0100A100-0x0100A2FF (watch PBPS @0x0100A1E0) ---
mem32 0100A100 4
mem32 0100A110 4
mem32 0100A120 4
mem32 0100A130 4
mem32 0100A140 4
mem32 0100A150 4
mem32 0100A160 4
mem32 0100A170 4
mem32 0100A180 4
mem32 0100A190 4
mem32 0100A1A0 4
mem32 0100A1B0 4
mem32 0100A1C0 4
mem32 0100A1D0 4
mem32 0100A1E0 4
mem32 0100A1F0 4
mem32 0100A200 4
mem32 0100A210 4
mem32 0100A240 4
mem32 0100A260 4
mem32 0100A280 4
exit
EOF

echo "=== RA6E1 config capture [$LABEL] -> $LOG ==="
"$JLINK" -device "$DEVICE" -CommanderScript "$S" -ExitOnError 0 2>&1 \
    | sed -n '/Cortex-M33 identified/,$p' | tee "$LOG"
rm -f "$S"

echo ""
echo "KEY WORDS:"
echo "  0x400E002C DLMMON  : 0x2 = SSD (normal). 0x5/0x6 = locked lifecycle."
echo "  0x0100A1E0 PBPS    : FFFFFFFF = unprotected/OK. 00000000 = PERMANENT block protect => BRICK."
echo "  0x0100A1C0 BPS     : FFFFFFFF = OK. 00000000 = block protect (cancelable)."
echo "Compare against the previous step's log:"
echo "  diff $SCRIPT_DIR/config_ra6e1_before.log $LOG"
