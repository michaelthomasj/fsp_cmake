# RASC Project Settings — RA6M4 TF-M Port (recreate-from-scratch reference)

Configuration reference for the three RASC-generated FSP projects consumed by the TF-M build
(BL2, Secure, Non-Secure). Captured from the working projects so they can be **recreated from
scratch** in a newer RASC/FSP without re-deriving the settings.

For *why* the port is built this way, see [DESIGN.md](DESIGN.md); for current status/TODO see
[TFM_RA6M4_STATUS.md](TFM_RA6M4_STATUS.md).

> Captured 2026-07-13 from FSP **6.1.0** / RASC **sc_v2025-07**
> (`C:/Renesas/RA/sc_v2025-07_fsp_v6.1.0/eclipse/rasc.exe`).

---

## 1. Common to all three projects

| Setting | Value |
|---|---|
| Device | **R7FA6M4AF3CFB** (RA6M4, Cortex-M33) |
| Board | EK-RA6M4 |
| Toolchain | GNU Arm Embedded 13.2 (IAR support is a TODO — see DESIGN.md §11) |
| FSP version | 6.1.0 |

### 1.1 Clock configuration (identical in all three — they must match)
Sourced from `ra_gen/bsp_clock_cfg.h`:

| Setting | Value |
|---|---|
| XTAL | **24 MHz** (main oscillator populated) |
| PLL source | Main osc (XTAL) |
| PLL | **÷3 × 25.0 → 200 MHz** |
| Clock source | PLL |
| HOCO | 20 MHz (`BSP_CFG_HOCO_FREQUENCY = 2`) |
| ICLK | ÷1 → **200 MHz** |
| PCLKA / PCLKB / PCLKC / PCLKD | ÷2 / ÷4 / ÷4 / ÷2 |
| BCLK | ÷2 |
| **FCLK** | **÷4 → 50 MHz** |
| PLL2 / CLKOUT / USBCLK / OCTACLK | disabled |

⚠ **FCLK must stay within 4–60 MHz** — the HP flash driver rejects anything below 4 MHz with
`FSP_ERR_FCLK` (`R_FLASH_HP_Open`). ÷4 from 200 MHz = 50 MHz is correct. If you change ICLK, re-check
the FCLK divider.

### 1.2 BSP settings that the TF-M integration depends on

| Setting | Required value | Why |
|---|---|---|
| **`BSP_CFG_EARLY_INIT`** | **1** ⚠ | **Critical.** TF-M's startup calls `SystemInit()` (FSP clock init) *before* the C-runtime init, so FSP state in `.bss` is zeroed right after it's computed. `EARLY_INIT=1` places `SystemCoreClock` et al. in `.ram_noinit`. With `0`, BL2 dies in `boot_platform_init` with `FSP_ERR_FCLK`. See DESIGN.md §8.1. **RASC defaults this to 0 — you must change it.** |
| `BSP_CFG_C_RUNTIME_INIT` | 1 | FSP default; TF-M's startup performs the actual C init. |
| `BSP_CFG_PFS_PROTECT` | 1 | FSP default. |
| `BSP_CFG_PARAM_CHECKING_ENABLE` | 0 | Size; enable while debugging if useful. |
| `BSP_CFG_ASSERT` | 0 | FSP default. |
| `BSP_CFG_STARTUP_CLOCK_REG_NOT_RESET` | 0 | FSP default. |

### 1.3 Option-setting memory (OFS)
`OFS0 = (OFS_IWDT | OFS_WDT)` — watchdogs not auto-started. OFS is emitted into the **BL2 image only**
(DESIGN.md §8); the secure/NS images must not carry it (MCUboot-signed images must be contiguous).

---

## 2. BL2 project — `FSP_Project_ra6m4_bl2` (MCUboot bootloader)

| Setting | Value |
|---|---|
| Main stack | `0x1500` |
| Heap | `0x1500` (MCUboot/mbedTLS need heap) |
| Memory regions | Full device: FLASH `0x00000000` len `0x00100000`; RAM `0x20000000` len `0x00040000`; data flash `0x08000000` len `0x2000` |

**Modules / stacks to add in RASC:**
- `driver.flash_hp` — Flash HP (MCUboot flash access)
- `driver.ioport` — I/O port
- `driver.psa_crypto` — PSA crypto (pulls mbedTLS)
- `middleware.mcuboot` — MCUboot
- `middleware.mcuboot_port` — MCUboot port layer (`rm_mcuboot_port`)
- `middleware.mcuboot_sysflash` — sysflash
- `middleware.mcuboot_logging` — MCUboot logging

Notes:
- The bootloader is **not** a TrustZone secure/non-secure project — it owns the whole device.
- The TF-M build takes the OFS values and (optionally) the MCUboot sources from here; it does **not**
  use this project's `script/fsp.ld` (TF-M supplies `ra6m4_bl2.ld` — DESIGN.md §8).

---

## 3. Secure project — `FSP_Project_ra6m4_s_rtos`

| Setting | Value |
|---|---|
| Project type | **TrustZone — Secure** |
| Main stack | `0x400` |
| Heap | `0` |
| Memory regions | Full device (unused by the TF-M build — TF-M generates the secure linker itself) |

**Modules / stacks:**
- `driver.flash_hp` — Flash HP (ITS/PS backing store)
- `driver.ioport` — I/O port
- `driver.sci_uart` — SCI UART (only needed if `RA6M4_STDOUT_RTT=OFF`; RTT is the default console)
- `middleware.rm_tz_context` — TrustZone context (exports the `TZ_*_S` NSC functions FreeRTOS-NS needs)

Notes:
- TF-M generates the secure linker script from `region_defs.h`; this project's `memory_regions.ld` is
  **not** consumed, so its full-device values are harmless.
- Veneer/NSC placement is controlled by TF-M macros, not RASC (DESIGN.md §7).

---

## 4. Non-Secure project — `FSP_Project_ra6m4_ns_rtos`

| Setting | Value |
|---|---|
| Project type | TrustZone — Non-Secure |
| Main stack | `0x400` |
| Heap | `0` (FreeRTOS supplies its own heap) |
| **Memory regions** | ⚠ **hand-edited** — see below |

**Modules / stacks:**
- `awsfreertos.thread` — FreeRTOS + a thread (the NS application)

### ⚠ 4.1 Required manual edit: `memory_regions.ld`
RASC generates a **standalone** layout (RAM `0x20002000`, FLASH `0x00008000`) that puts the NS image in
**secure RAM** — it will SecureFault the moment TF-M jumps to non-secure. It must be the TF-M NS
partition:

```
RAM_START    = 0x20020000;   RAM_LENGTH   = 0x00020000;   /* NS RAM 128K            */
FLASH_START  = 0x00050400;   FLASH_LENGTH = 0x0001f400;   /* NS slot 0x50000 + hdr  */
```
(`0x50400` = NS partition `0x50000` + BL2 header `0x400`; length = `0x20000 − 0x400 − 0x800`.)

**RASC regeneration overwrites this** — re-apply it, or set the equivalent in the RASC linker/BSP
configuration so it regenerates correctly.

---

## 5. Post-generation checklist (after any RASC regeneration)

1. **`BSP_CFG_EARLY_INIT = 1`** in every project (§1.2). RASC defaults to 0 → BL2 `FSP_ERR_FCLK` crash.
2. **NS `memory_regions.ld`** → the TF-M NS partition values (§4.1).
3. Verify the **clock tree** still matches §1.1 and that **FCLK is 4–60 MHz**.
4. Confirm `OFS0` (§1.3) still reflects the intended watchdog/LVD configuration.
5. The TF-M port also carries a **vendored `fsp/` snapshot** used when `FSP_*_APP_DIR` is not set —
   it needs the same settings (notably `BSP_CFG_EARLY_INIT=1`). Prefer pointing the build at the
   regenerated RASC projects so this snapshot doesn't drift.
