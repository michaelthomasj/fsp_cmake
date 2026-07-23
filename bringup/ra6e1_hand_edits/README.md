# RA6E1 BL2 — hand edits (re-apply after every RASC regen)

RASC regeneration OVERWRITES these files. After a regen, commit the raw RASC output
first (clean diff), then re-apply these on top as a separate commit.

1. **`../../FSP_Project_ra6e1_bl2/src/hal_entry.c`** — bootloader-invoke edit.
   Restore from the preserved copy here: `cp hal_entry.c ../../FSP_Project_ra6e1_bl2/src/hal_entry.c`
   (diff first against the freshly regenerated template to merge any RASC changes).

2. **`../../FSP_Project_ra6e1_bl2/CMakeLists.txt`** — the auto-srec POST_BUILD block
   (after the `GeneratedSrc.cmake` include). Re-apply with:
   `git apply bringup/ra6e1_hand_edits/srec_rule.patch`  (or paste the block back).
