# Who owns the flash map — TF-M, MCUboot, FSP

> **RESOLVED 2026-10-05: Option 3 adopted and verified on hardware ([D091]).** Both parts take
> TF-M's MCUboot map and backend, with FSP's HAL behind `fa_driver` via the port's own
> `Driver_Flash.c` - the same shape ST uses for STM32Cube. The full RA6M5 regression suite
> passes, secure and non-secure. Upstream item 13 is withdrawn and `bl2/CMakeLists.txt` is
> byte-identical to TF-Mv2.2.0. The analysis below stands as written; §7 records the options as
> they were weighed.

Design review, 2026-10-05. Written to answer four questions: what MCUboot's porting contract
actually is, whether TF-M's BL2 breaks it, what other vendors do, and where this port is
inconsistent with the two standing objectives —

- **A. TF-M updates must keep flowing in.** The port must not diverge from upstream so far that
  a TF-M bump becomes a merge exercise.
- **B. FSP updates must keep flowing in.** A pack update plus a regenerate should carry FSP's
  fixes into the port without hand-patching.

Every claim below was checked against the source on 2026-10-05, not recalled.

---

## 1. MCUboot's actual contract

**MCUboot does not define `struct flash_area`.** `bootutil` includes
`<flash_map_backend/flash_map_backend.h>` (`bootutil_priv.h:35`, `bootutil_public.h:44`,
`enc_key.h:32`) and **every port supplies that header itself**:

```
boot/zephyr/include/flash_map_backend/flash_map_backend.h
boot/espressif/include/...
boot/mynewt/flash_map_backend/include/...
boot/nuttx/include/...
boot/cypress/cy_flash_pal/include/...
boot/mbed/include/...
sim/mcuboot-sys/csupport/...
```

So the porting interface is: **the port owns the type and the `flash_area_*` functions.**
MCUboot owns only the algorithms above them.

How the ports fill that slot differs, and the pattern is informative:

| Port | Where the type comes from |
|---|---|
| **zephyr** | `#include <zephyr/storage/flash_map.h>` — the RTOS already has a flash map; the backend header just adapts it |
| **mynewt** | `#include <flash_map/flash_map.h>` + `<sysflash/sysflash.h>` — same, the OS owns it |
| **nuttx**, **espressif** | define the struct inline, 12 bytes: `fa_id, fa_device_id, pad16, fa_off, fa_size` |

**FSP supplying `rm_mcuboot_port/flash_map_backend/flash_map_backend.h` is therefore
idiomatic MCUboot**, and structurally identical to what Zephyr and Mynewt do. FSP is not
deviating; it is doing exactly what a platform is supposed to do.

---

## 2. What TF-M does

**TF-M is itself an MCUboot port.** It occupies that same single slot:

```
bl2/ext/mcuboot/include/flash_map_backend/flash_map_backend.h   guard __FLASH_MAP_BACKEND_H__
  └── #include "flash_map/flash_map.h"                          guard H_UTIL_FLASH_MAP_
```

That is Mynewt's two-file shape, inherited. FSP collapsed the same ancestry into one file and
kept the **inner** guard. Hence the collision ([D090]): both headers claim `H_UTIL_FLASH_MAP_`,
the first one reached silences the other, and they do not define the same type.

TF-M's struct carries one member FSP's does not:

```c
struct flash_area {
    uint8_t  fa_id;
    uint8_t  fa_device_id;
    uint16_t pad16;
    ARM_DRIVER_FLASH *fa_driver;   /* TF-M only - 16 bytes vs FSP's 12 */
    uint32_t fa_off;
    uint32_t fa_size;
};
```

That member is not decoration. **TF-M's backend reaches flash through it**:

```c
DRV_FLASH_AREA(area)->ReadData(area->fa_off + off, ...)   /* bl2/src/flash_map.c:166 */
DRV_FLASH_AREA(area)->ProgramData(...)                    /* :320 */
```

So TF-M's model is: *a flash area names its CMSIS `ARM_DRIVER_FLASH`, and all access is
dispatched through that driver.* FSP's model is: *a flash area is an absolute address*, read
with `memcpy` and written through `R_FLASH_*` / `R_MRAM_*`.

These are two coherent designs that cannot share a struct.

---

## 3. Has TF-M broken MCUboot's abstraction?

**In form, no.** TF-M fills the port slot MCUboot defines, with the header and the functions the
contract asks for. Nothing is subverted.

**In effect, for a vendor who already has a flash map, yes** — and the reason is that the slot
is *singular*. A build contains exactly one `flash_map_backend.h`. TF-M has taken it, so a
platform whose SDK also supplies one (FSP, and Zephyr for the same reason) cannot simply bring
its own; one of the two must be suppressed.

TF-M does provide an escape hatch, and its limits are the important part:

| `DEFAULT_MCUBOOT_FLASH_MAP=OFF` gives you | it does **not** give you |
|---|---|
| drop `bl2/src/default_flash_map.c`, so you supply the `flash_map[]` **array** | TF-M's `struct flash_area` — you still use it |
| empty the `FLASH_AREA_IMAGE_PRIMARY/SECONDARY` macros in `sysflash.h`, so you define the **area IDs** | TF-M's `flash_area_*` **functions** — still `bl2/src/flash_map.c` |

**The only two upstream users prove the limit.** `corstone1000` and `rse` both set the flag,
and both still populate TF-M's struct:

```c
/* platform/ext/target/arm/corstone1000/bl2/flash_map_bl2.c:30 */
.fa_driver = &FLASH_DEV_NAME,
```

So upstream TF-M supports **"bring your own map data"**. It does **not** support **"bring your
own backend"**. No platform in the tree supplies its own `flash_map_backend.h` or `sysflash.h` —
I checked; there are none.

**That is the honest answer to the question.** MCUboot's abstraction is clean and would let FSP
plug straight in. TF-M sits in the socket and offers a narrower one, and this port is the first
to want the full width.

---

## 4. Where this port sits, and the seams

The port currently replaces **type, functions and data** with FSP's — further than any upstream
platform goes. That is what `DEFAULT_MCUBOOT_FLASH_BACKEND` exists for, and it is **our
invention**, not an upstream concept ([UPSTREAM_CHANGES] item 13).

The result is not one boundary but five, each a place the two projects' code meets:

| Seam | Taken from | Why |
|---|---|---|
| `struct flash_area` + `flash_area_*` | **FSP** | so FSP's fixes arrive with a pack update; on RA8M2 its `flash_area_open()` also programs the SAU |
| `flash_map[]` data | **FSP** (`bsp_linker_info.h`) | the Solution owns the layout |
| area-ID macros (`sysflash.h`) | **FSP** | follows the map |
| `mcuboot_config.h` (policy) | **TF-M** | deliberately — FSP's lacks `MCUBOOT_HW_ROLLBACK_PROT` ([D079]) |
| rollback counters | **TF-M** (`bl2/src/security_cnt.c`) | `rm_mcuboot_port` does not provide them |
| `boot_hooks.h` | **TF-M's MCUboot**, shimmed | FSP's copy is 287 lines to TF-M's 181 |

**FSP's `flash_map.c` is therefore compiled against a `mcuboot_config.h` FSP did not generate,
with a hook shim standing in for the MCUboot version FSP expects.** It works, and it is the
least comfortable thing in the design.

---

## 5. The decoupling that is being missed

**Layout ownership and backend ownership are separable, and this port has conflated them.**

The MCUboot areas already derive from the Solution regardless of which backend compiles:

```c
/* ra6m5/flash_layout.h */
#define FLASH_AREA_0_OFFSET   (BSP_PARTITION___BL_0_P_H_START)
#define FLASH_AREA_0_SIZE     TFM_SLOT_SPAN(BSP_PARTITION___BL_0_P_H, ...)
#define FLASH_AREA_1_OFFSET   (BSP_PARTITION___BL_1_P_H_START)
```

Those are FSP's generated partition macros. **The Solution already sets the image layout, and
would continue to do so with TF-M's backend.** Adopting FSP's `flash_map.c` bought three
things, only one of which is about layout:

1. FSP's bug fixes in the backend — real, and the point of objective B.
2. RA8M2's SAU programming in `flash_area_open()` — real, and load-bearing there.
3. The layout coming from the Solution — **this one we already had.**

---

## 6. Inconsistencies against the objectives

### Against A — TF-M updates flowing in

| # | Issue | Why it bites |
|---|---|---|
| A1 | **Item 13 is an architectural change to common BL2 code.** Until upstream accepts it, every TF-M bump means re-applying it. | The patch queue is 13 items; 12 are small and local, this one is structural |
| A2 | **The fix depends on header search order, not on an interface.** FSP's directory must precede TF-M's for `bl2` and `bootutil`. | Any CMake change that reorders includes silently reintroduces [D090]. There is no build-time assertion — only the DWARF check in `BRIDGING_FILES.md` §3, which must be run by hand |
| A3 | **`fsp_flash_map_shim.h` re-exports pieces of TF-M's `flash_map.h`.** | If TF-M adds to that header, the shim silently lacks it; if TF-M changes a meaning, the shim is stale and still compiles |
| A4 | **We predefine `__FLASH_MAP_BACKEND_H__`** to suppress a TF-M header. | That is an internal include guard, not an interface. A rename upstream breaks it with no diagnostic |
| A5 | **`mcuboot_hook_shim.h` compensates for a version difference** between TF-M's MCUboot and FSP's. | If TF-M's MCUboot gains those hooks, the shim collides instead of filling a gap |

### Against B — FSP updates flowing in

| # | Issue | Why it bites |
|---|---|---|
| B1 | *Working as intended:* FSP's `flash_map.c` is compiled from the pack, so its fixes arrive on a regenerate. | This is the strongest part of the current design and the main argument for keeping it |
| B2 | **FSP's struct is now load-bearing for TF-M's bootutil.** | If FSP adds a member — exactly what TF-M did — the silent-shift bug returns. Caught only by the DWARF check |
| B3 | **FSP's `flash_map.c` runs against TF-M's `mcuboot_config.h`.** | FSP tests its code against its own config. Any FSP change that assumes an FSP-only option is a latent mismatch |
| B4 | **`fsp_module_glob` cannot be used for `rm_mcuboot_port`** — it is `GLOB_RECURSE` and would pull `custom_crypto_stacks/`, `os/`, `rm_mcuboot_port.c`. The file is named explicitly. | A new file FSP adds to that module will **not** be picked up, which is precisely the automatic-absorption property objective B asks for |

**B4 is the one I would flag hardest.** It is a direct, current violation of objective B, and it
is quiet: FSP adds a source, the port ignores it, nothing warns.

---

## 6a. Checked against latest upstream (2026-10-05)

Re-verified against `upstream/main`, well past TF-Mv2.3.1. **Nothing in the analysis changes:**

| | TF-Mv2.2.0 (our base) | upstream/main |
|---|---|---|
| `struct flash_area` | 16 B with `fa_driver` | unchanged |
| Guards `H_UTIL_FLASH_MAP_` / `__FLASH_MAP_BACKEND_H__` | collide | unchanged |
| `flash_map_backend.h` / `sysflash.h` in the tree | one each, TF-M's | still one each |
| Platforms with `DEFAULT_MCUBOOT_FLASH_MAP=OFF` | corstone1000, rse | still only those two |
| `DEFAULT_MCUBOOT_FLASH_BACKEND` | — | still does not exist |

**New and decisive: ST is already doing Option 3.** Four ST platforms
(`b_u585i_iot02a`, `nucleo_u3c5zi_q`, `stm32h573i_dk`, `stm32wba65i_dk`) now appear in the
tree, all setting `DEFAULT_MCUBOOT_FLASH_MAP` **ON**. ST has STM32Cube HAL - the direct
analogue of FSP - and their answer is to wrap it behind a CMSIS driver rather than replace the
backend:

```
stm/common/hal/CMSIS_Driver/low_level_flash.c
    HAL_FLASH_Program(), HAL_FLASHEx_GetOperation()     <- ST's own HAL
        wrapped as ARM_DRIVER_FLASH
            externed by bl2/src/default_flash_map.c as FLASH_DEV_NAME_0..3
```

So the vendor whose situation most resembles this one keeps TF-M's map **and** backend, and
supplies only the driver.

## 7. Options

Stated with their costs, not ranked — the choice is a judgement about which divergence is
cheaper to carry.

### Option 1 — keep FSP's backend (current state)

- **A:** needs item 13 upstreamed, or carried forever. Keeps A2–A5.
- **B:** best case for FSP fixes, except B4.
- RA8M2's SAU programming comes free.
- **Verdict:** maximum FSP absorption, maximum TF-M divergence.

### Option 2 — TF-M's backend, FSP-generated data (the corstone1000 model)

Generate a `flash_map[]` from `bsp_linker_info.h` into TF-M's struct, set
`DEFAULT_MCUBOOT_FLASH_MAP=OFF`, keep `bl2/src/flash_map.c`.

- **A:** **zero architectural divergence** — this is the upstream-sanctioned path, already used
  by two Arm platforms. Item 13 is withdrawn. A2–A5 all disappear.
- **B:** we stop getting FSP's backend fixes; `rm_mcuboot_port` returns to being shadowed.
- The Solution still owns the layout (§5), so **the stated layout objective is still met**.
- **Cost:** RA8M2's SAU programming must move into `boot_hal`, which re-opens [D076] — the
  change that was tried and reverted. It is ~10 lines and the register values are in
  `R_PSCU->CFSAMONA_b.CFS2`, but it is port-owned code replicating FSP's.

### Option 3 — TF-M's backend, FSP data, FSP's flash driver behind `fa_driver`

As Option 2, but the port's `Driver_Flash.c` (which already exists and wraps `R_FLASH_HP` /
`R_MRAM`) becomes the `ARM_DRIVER_FLASH` that `fa_driver` points at.

- **A:** same as Option 2 — zero divergence.
- **B:** FSP's *driver* fixes still flow in, since `Driver_Flash.c` calls FSP's HAL. Only
  `rm_mcuboot_port`'s own logic is lost, which is thin — an address computation and a
  controller open.
- **This is what corstone1000 does**, with the port's CMSIS driver in the slot.
- **Cost:** the RA8M2 SAU only. **Cheaper than first estimated** - the code already exists in
  `299b03039`, which was reverted for wanting FSP's flash_map, not because it was wrong.
  `ARM_DRIVER_FLASH Driver_FLASH0`/`Driver_FLASH1` already exist on both parts and
  `FLASH_DEV_NAME` already resolves to `Driver_FLASH0`, so nothing new is written there.

---

## 8. What I would want decided

1. **Is `rm_mcuboot_port`'s logic worth the divergence?** It is roughly: pick the alias, open
   the controller, program the SAU, `memcpy`. Option 3 keeps FSP's HAL underneath while handing
   the MCUboot-facing contract back to TF-M.
2. **Is item 13 something upstream would take?** It is a reasonable request — "let a platform
   replace the backend, not just the data" — but it is the only structural item in the queue,
   and it is what makes a TF-M bump expensive.
3. **B4 should be fixed regardless of the above.** A module whose new files are silently ignored
   defeats objective B whichever backend wins.

The layout objective — FSP's Solution deciding the image layout — is **already satisfied and is
not at risk under any option**. It should not be the reason to keep the FSP backend.
