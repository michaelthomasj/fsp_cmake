# Reconfiguring the memory layout

Audience: someone changing the partitioning of an existing part — resizing a slot, moving the
storage area, growing the bootloader.
Not for: adding a new part, which is [PORTING.md](PORTING.md).

> The one-sentence version. Change the layout in the e2 solution, rebuild the secure
> project there, and most of the chain follows automatically. Four things do not, and three of
> them fail on silicon rather than at build time.

---

## 1. What follows automatically

One edit propagates through four stages, and you touch none of them:

```
  e2 solution  (solution.xml / the Memory tab)
        │  e2 build — NOT regeneration alone
        ▼
  <project>/Debug/bsp_linker_info.h          #define BSP_PARTITION_<NAME>_{START,SIZE}
        │  platform CMakeLists: file(STRINGS …) greps the BSP_PARTITION_* lines
        ▼
  <build>/generated/bsp_partitions.h         macros only — see §2
        │  #include
        ▼
  flash_layout.h          FLASH_AREA_*_OFFSET/SIZE, ITS/PS areas, FLASH_DEVICE_ID
  region_defs.h           BL2_*, S_*, NS_* code and data regions
        │  both preprocessed with -xc into the linker scripts
        ▼
  <part>_bl2.ld / .icf ·  the TF-M secure and NS scatter files
```

Consequences worth knowing:

- **Build the e2 project, do not just regenerate** ([GETTING_STARTED.md](GETTING_STARTED.md) §4).
- **Never hand-edit `bsp_partitions.h`.** It is generated into the build directory and
  regenerated every configure.
- If the grep finds no `BSP_PARTITION_*` lines the configure stops with a message naming the
  cause — that error means step 1 did not happen.

## 2. What does NOT follow — the four

### 2.1 RDPM boundary values ⚠ *fails on silicon*

The boundaries are programmed into the device and change with the layout. Re-derive them (the
SOLUTION documents show how), then reprogram with RDPM, which erases the part
([GETTING_STARTED.md](GETTING_STARTED.md) §6). Wrong values give a secure image that never
starts, with no output.

### 2.2 `PS_NUM_ASSETS` capacity *fails at runtime*

Protected Storage capacity is a sum, not a per-asset limit, and the cap is per part: 5 on
RA6M5 (1,536 B PS block) against 155 on RA8M2 (15,872 B). Resizing the storage area changes
it. The formula is in `config_tfm_target.h`; assert the result in `<part>_layout_checks.c`.

**Erase the storage area before the first boot after any storage change** — data flash on
RA6M5, the DF_EMULATION region in MRAM on RA8M2. A stale area survives a reflash and the
storage suites then fail in ways that look like code faults.

### 2.3 The NSC window LMA budget *fails at link, obscurely*

The NSC veneers are pinned at the top of the secure region, so the code budget is the region
([CONFIGURATION.md](CONFIGURATION.md) §6) and exceeding it fails the link. When you resize, keep
the slot ≥ region + 0x200 header + ~275 B of TLVs + trailer, or imgtool refuses after a clean
link.

### 2.4 `MCUBOOT_ALIGN_VAL` compatibility *fails as a verification error*

Images signed at one `MCUBOOT_ALIGN_VAL` are rejected by a BL2 built at another; reflash every
slot after a change ([CONFIGURATION.md](CONFIGURATION.md) §3).

## 3. The assertions that catch you

`<part>_layout_checks.c` turns layout mistakes into compile errors. Examples:

| Checks | Catches |
|---|---|
| `S_MSP_STACK_SIZE == BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` | FSP's `SystemInit()` writing its stack seal past the top of the stack instead of on the reserved `__StackSeal` |
| `S_CODE_VECTOR_TABLE_SIZE` vs the configured device | `.TFM_VECTORS` overflowing into the next section; also flags `RA8M2_VECTOR_TABLE_ENTRIES` in `startup_<part>.c` |
| The part has MRAM | a `flash_layout.h` full of MRAM alias offsets on a part without MRAM |
| Erase sector is a whole number of write units | a trailer straddling a sector boundary |
| Each area starts on an erase-sector boundary | `boot_read_sectors()` erasing from the wrong address on upgrade |

After any layout change, build first and read these. If you add a constraint the existing
assertions do not cover, add one.

---

## 4. Procedure

1. Change the layout in the e2 solution. The Memory tab of the solution, not a project.
2. Rebuild all three e2 projects (secure, bootloader, non-secure). Not regenerate - build.
   The bootloader one matters because the OFS addresses come from its `Debug/memory_regions.*`
   on RA8M2, and [PORTING.md](PORTING.md) §5 asks for all three. Confirm
   `<project>/Debug/bsp_linker_info.h` has the new values before going on.
3. Reconfigure TF-M from a deleted build directory; a stale `CMakeCache.txt` keeps the old values
   silently.
4. Build and read the assertions (§3).
5. Revisit the four (§2): RDPM, `PS_NUM_ASSETS`, the NSC/trailer budget, `MCUBOOT_ALIGN_VAL`.
6. Check the OFS guard output. `check_ofs.py` runs during the build; a layout change can move
   the option-setting words. ⚠ [DESIGN.md](DESIGN.md) §8.4.
7. Reprogram RDPM if the boundaries moved, then reflash all three images. **RDPM erases
   the part.**
8. Erase code and data flash on the first connect after a storage change
   ([GETTING_STARTED.md](GETTING_STARTED.md) §6).
9. Re-run the full regression and the storage suite (test 403 exercises the boundary).
10. Re-sign secondary-slot images with `scripts/sign_secondary.py`
    ([scripts/README.md](scripts/README.md)).

---

## 5. Symptoms, mapped back

| Symptom | Look at |
|---|---|
| Configure stops: no `BSP_PARTITION_*` defines | step 2 — the e2 project was not built |
| New values ignored | step 3 — stale build directory |
| `region CODE_RAM overflowed` | `S_RAM_CODE_SIZE` — see [CONFIGURATION.md](CONFIGURATION.md) |
| `region FLASH overflowed` with space apparently free | §2.3 — the NSC window / trailer |
| A `_Static_assert` fires | §3 — read the message, it names the fix |
| Secure image never starts, nothing on console | §2.1 — RDPM boundaries |
| Storage suite fails oddly after a change | §2.2 — erase data flash; check `PS_NUM_ASSETS` |
| MCUboot rejects an image it signed | §2.4 — `MCUBOOT_ALIGN_VAL` changed |
| Upgrade erases the wrong address | sector-boundary assertion in §3 |

---

## 6. See also

[DESIGN.md](DESIGN.md) §3, [CONFIGURATION.md](CONFIGURATION.md) §7, the SOLUTION documents,
[PORTING.md](PORTING.md) for a new part.
