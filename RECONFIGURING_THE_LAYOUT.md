# Reconfiguring the memory layout

**Audience:** someone changing the partitioning of an existing part — resizing a slot, moving the
storage area, growing the bootloader.
**Not for:** adding a new part, which is [PORTING.md](PORTING.md).

> **The one-sentence version.** Change the layout in the **e2 solution**, rebuild the secure
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

**Consequences worth knowing:**

- **Rebuild the e2 project, do not just regenerate.** `bsp_linker_info.h` is a build artefact.
  Regenerating alone leaves the old values and the TF-M build happily uses them.
- **Never hand-edit `bsp_partitions.h`.** It is generated into the build directory and
  regenerated every configure.
- If the grep finds no `BSP_PARTITION_*` lines the configure stops with a message naming the
  cause — that error means step 1 did not happen.

### Why `bsp_partitions.h` exists at all

`flash_layout.h` and `region_defs.h` are consumed by C **and** preprocessed into the linker
scripts with `-xc`. `bsp_linker_info.h` cannot serve the second: alongside the macros it declares
C types and externs (`typedef enum e_bsp_init_mem`, `gp_ddsc_*`) that land verbatim in the
preprocessed linker script and fail to parse. It also defines a `static const struct flash_area
flash_map[]` under `FLASH_MAP_C` that would collide with TF-M's own.

So the CMakeLists extracts **only** the `#define BSP_PARTITION_*` lines. That is the whole trick.

---

## 2. What does NOT follow — the four

### 2.1 RDPM boundary values ⚠ *fails on silicon*

The TrustZone boundaries are programmed into the **device**, not the image, through the Renesas
Device Partition Manager. Nothing in the build knows what you set. RA8M2 is `703/1/0/935/1/0`.

- Change the layout, and the RDPM values almost certainly change with it.
- **RDPM erases the part.** Reflash all three images afterwards.
- Getting them wrong gives a secure image that will not start, with no console output.

### 2.2 `PS_NUM_ASSETS` capacity *fails at runtime*

Protected Storage capacity is a **sum**, not a per-asset limit, and the cap is per part: **5** on
RA6M5 (1,536 B PS block) against **155** on RA8M2 (15,872 B). Resizing the storage area changes
it. The formula is in `config_tfm_target.h`; assert the result in `<part>_layout_checks.c`.

**Erase data flash before the first boot after any storage change** — a stale area survives a
reflash and the storage suites then fail in ways that look like code faults.

### 2.3 The NSC window LMA budget *fails at link, obscurely*

The non-secure callable veneers sit at a fixed address at the top of the secure region, and the
MCUboot trailer occupies the slot tail. Both constrain how much the secure image can grow.
Symptom is `region FLASH overflowed` with apparently free space.

Related: `ih_img_size` is set by the **layout**, not by how much code you emitted — the image
runs to the veneers at their fixed address. Both toolchains report the same value for this
reason ([D106]).

### 2.4 `MCUBOOT_ALIGN_VAL` is a flag day *fails as a verification error*

imgtool encodes the alignment in the boot magic, so **images signed before and after a change are
not interchangeable**. RA6M5 uses 128 (trailer `0x180`), RA8M2 uses 32 (`0x60`). Changing it
means reflashing everything, including any secondary-slot images.

---

## 3. The assertions that catch you

`<part>_layout_checks.c` carries **35 compile-time assertions** on RA8M2. They are the
difference between a mistake found in two seconds and one found on a board with no console
output. A sample of what they cover, with the message each prints:

| Checks | Catches |
|---|---|
| `S_MSP_STACK_SIZE == BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE` | FSP's `SystemInit()` writing its stack seal past the top of the stack instead of on the reserved `__StackSeal` |
| `S_CODE_VECTOR_TABLE_SIZE` vs the configured device | `.TFM_VECTORS` overflowing into the next section; also flags `RA8M2_VECTOR_TABLE_ENTRIES` in `startup_<part>.c` |
| The part actually has MRAM | a `flash_layout.h` full of MRAM alias offsets on a part without MRAM |
| Erase sector is a whole number of write units | a trailer straddling a sector boundary |
| Each area starts on an erase-sector boundary | `boot_read_sectors()` erasing from the wrong address on upgrade |

**After any layout change, build first and read these.** If you add a constraint the existing
assertions do not cover, add one — this file is where the time is earned back.

---

## 4. Procedure

1. **Change the layout in the e2 solution.** The Memory tab of the solution, not a project.
2. **Rebuild the secure project in e2.** Not regenerate — build. Confirm
   `<project>/Debug/bsp_linker_info.h` has the new values before going on.
3. **Reconfigure TF-M from scratch.** Delete the build directory. A stale `CMakeCache.txt`
   carries the old generated values with no diagnostic — this has bitten the port repeatedly
   ([D089], [D102]).
4. **Build and read the assertions** (§3).
5. **Revisit the four** (§2): RDPM, `PS_NUM_ASSETS`, the NSC/trailer budget, `MCUBOOT_ALIGN_VAL`.
6. **Check the OFS guard output.** `check_ofs.py` runs during the build; a layout change can move
   the option-setting words. ⚠ [DESIGN.md](DESIGN.md) §8.4.
7. **Reprogram RDPM if the boundaries moved**, then reflash **all three** images — RDPM erases
   the part.
8. **Erase code and data flash** on the first connect after any storage change.
9. **Re-run the full regression and the storage suite.** Storage is the one most sensitive to
   layout, and test 403 ("insufficient space") exercises the boundary directly.
10. **Resign any secondary-slot images** — `scripts/sign_secondary.py`. They are built against
    the old layout otherwise.

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
| MCUboot rejects an image it signed | §2.4 — `MCUBOOT_ALIGN_VAL` flag day |
| Upgrade erases the wrong address | sector-boundary assertion in §3 |

---

## 6. See also

- [DESIGN.md](DESIGN.md) §1 config truth, §3 the authoritative memory map, §8.4 OFS ⚠
- [CONFIGURATION.md](CONFIGURATION.md) — every layout symbol and its constraint
- [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) / [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) — the current maps and RDPM values
- [PORTING.md](PORTING.md) — a new part rather than a new layout
- [GETTING_STARTED.md](GETTING_STARTED.md) §4 — why the e2 build is a prerequisite
