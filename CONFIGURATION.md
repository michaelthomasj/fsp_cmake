# Configuration reference — every knob you may legitimately change

Every option a user of this port sets, its default on RA6M5 and RA8M2, and the constraint that
bites. The layout and FSP module set come from the e2 projects ([DESIGN.md](DESIGN.md) §1); these
options sit on top.

---

## How the three layers interact, and two cache traps

```
e2 / RASC solution          partitions, FSP modules, OFS values, BSP_CFG_*
      |  generated Debug/bsp_linker_info.h, Debug/memory_regions.*
      v
<part>/config.cmake         the port's opinions - cache defaults
      |
      v
your -D on the command line wins over both
```

**Two cache traps.** A default in `<part>/config.cmake` beats `TFM_PROFILE`, so pass
`TFM_ISOLATION_LEVEL` and `TFM_PARTITION_*` explicitly. A cache entry is never overwritten by a
later `set(... CACHE ...)`: after editing `config.cmake`, delete the build tree or pass `-D`, and
check `CMakeCache.txt`, not the config file.

---

## 1. Build inputs — required

| Option | Meaning |
|---|---|
| `TFM_PLATFORM` | `renesas/ra6m5` or `renesas/ra8m2` |
| `FSP_S_APP_DIR` | the generated secure e2 project. Supplies `Debug/bsp_linker_info.h`, from which the whole layout is derived |
| `FSP_BL2_APP_DIR` | the generated bootloader project. Supplies the OFS values and the FSP drivers BL2 needs |
| `FSP_NS_APP_DIR` | the generated non-secure project |
| `TFM_TOOLCHAIN_FILE` | `toolchain_GNUARM.cmake` or `toolchain_IARARM.cmake` |
| `CMAKE_BUILD_TYPE` | `MinSizeRel` for GNUARM on RA8M2 (Debug, ~414 KB, does not fit the region) and for every regression build. Debug fits the RA6M5 GNUARM and both IAR application builds. Release: §9 |

Build the e2 projects before configuring ([GETTING_STARTED.md](GETTING_STARTED.md) §4).

---

## 2. FSP module selection

These decide which FSP sources are compiled into which image. They live in
`<part>/CMakeLists.txt`, not `config.cmake`.

| Variable | RA6M5 | RA8M2 |
|---|---|---|
| `FSP_MODULES_S` | `bsp flash sce agt` | `bsp flash sce agt` |
| `FSP_MODULES_BL2` | `bsp flash` (+ `sce` when `CRYPTO_HW_ACCELERATOR` is ON) | `bsp flash` (+ `sce` when `CRYPTO_HW_ACCELERATOR` is ON) |
| `FSP_MODULE_DIRS_flash` | `r_flash_hp` | `r_mram` — MRAM, not HP flash |
| `FSP_MODULES_NEVER_BUILT` | `r_sce rm_psa_crypto rm_mcuboot_port` | `r_sce rm_psa_crypto rm_mcuboot_port` |

`FSP_MODULES_NEVER_BUILT` only silences the unclaimed-module warning. A module stays out of the
secure and BL2 images by not being listed in `FSP_MODULES_S`/`_BL2`; the non-secure image builds
every module its project enables ([ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §2).

To add a driver to the secure or BL2 image, follow
[ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md).

---

## 3. MCUboot and the flash layout

| Option | RA6M5 | RA8M2 | Notes |
|---|---|---|---|
| `MCUBOOT_IMAGE_NUMBER` | 2 | 2 | secure + non-secure. BL2 loads them in reverse order (`bl2_main.c`) |
| `MCUBOOT_SIGNATURE_TYPE` | `EC-P256` | `EC-P256` | must match the solution |
| `MCUBOOT_UPGRADE_STRATEGY` | `OVERWRITE_ONLY` | `OVERWRITE_ONLY` | scratch is unused; see [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) on why its block is still reserved |
| `MCUBOOT_ALIGN_VAL` | 128 | 32 | imgtool encodes it into the boot magic when it is not 8, so images signed at one value are rejected by a BL2 built at another. **The two parts' images are not interchangeable** |
| `MCUBOOT_USE_PSA_CRYPTO` | ON | ON | required for `EC-P256` |
| `MCUBOOT_HW_KEY` | OFF | OFF | |
| `MCUBOOT_MEASURED_BOOT` | ON | ON | boot record per image |
| `MCUBOOT_DATA_SHARING` | ON | ON | this is the option that does the work: without it BL2 writes no boot record and `MEASURED_BOOT` has nothing to carry |
| `DEFAULT_MCUBOOT_FLASH_MAP` | ON | ON | upstream default: TF-M's map and backend over the port's `Driver_Flash.c` ([DESIGN.md](DESIGN.md) §4) |

A passing attestation suite does not prove measured boot works
([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §3).

Image versions are `MCUBOOT_IMAGE_VERSION_S` (`${TFM_VERSION}`) and `_NS` (`0.0.0`). FSP's
`MCUBOOT_IMAGE_VERSION` environment variable is ignored silently ([DESIGN.md](DESIGN.md) §1.1).

---

## 4. Isolation, partitions and the SPM

| Option | Default here | Notes |
|---|---|---|
| `TFM_ISOLATION_LEVEL` | 1 | the PSA Arch builds use 3 |
| `CONFIG_TFM_SPM_BACKEND` | `SFN` | no IPC overhead; the PSA Arch builds use `IPC` |
| `PLATFORM_HAS_ISOLATION_L3_SUPPORT` | ON | the shared Armv8-M isolation HAL implements L3 ([D008]) |
| `TFM_PARTITION_CRYPTO` / `_INTERNAL_TRUSTED_STORAGE` / `_PROTECTED_STORAGE` / `_INITIAL_ATTESTATION` / `_PLATFORM` | ON | |
| `TFM_PARTITION_FIRMWARE_UPDATE` | OFF | |
| `CONFIG_TFM_USE_TRUSTZONE` | ON | |
| `TFM_MULTI_CORE_TOPOLOGY` | OFF | |
| `CONFIG_TFM_ENABLE_CP10CP11` | OFF | soft float, matching TF-M |

The `PLATFORM_DEFAULT_*` set is pinned because the port supplies its own implementation:
`PLATFORM_DEFAULT_ATTEST_HAL` OFF, `PLATFORM_DEFAULT_SYSTEM_RESET_HALT` OFF,
`PLATFORM_DEFAULT_NV_SEED` OFF (the hardware TRNG is the entropy source), and
`PLATFORM_DEFAULT_NV_COUNTERS` / `_CRYPTO_KEYS` / `_OTP` / `_PROVISIONING` ON.

---

## 5. Crypto

| Option | RA6M5 | RA8M2 |
|---|---|---|
| `CRYPTO_HW_ACCELERATOR` | ON | ON |
| `CRYPTO_HW_ACCELERATOR_TYPE` | `renesas/sce9` | `renesas/rsip_e50d` |
| `<PART>_FSP_MBEDTLS` | ON | ON |
| `PS_ENCRYPTION` | ON | ON (AES-GCM) |
| `TFM_CRYPTO_TEST_ALG_CFB` | OFF | OFF |

AES-CCM runs in software by design ([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2).

---

## 6. Diagnostics — and what they cost

**"Region" below means the secure *code* region**, the one the linker fills and reports —
`0x47A00` (293,376 B) on RA8M2. Two larger figures circulate for the same part, and each is
correct about something else. Add the 1,024 B non-secure-callable window and you get the
`0x47E00` (294,400 B) that `config.cmake` works in. That is also the 294,912 B slot less its
512 B MCUboot header. Every figure in this document means the code region unless it says
otherwise.

```
                         secure region   code used   spare for code
RA6M5, Debug, GNUARM          521,728     323,536         198,192
RA8M2, MinSizeRel, GNUARM     293,376     216,936          76,440

                         slot        signed image   spare in the slot
RA6M5                      524,288        522,427            1,861
RA8M2                      294,912        294,075              837
```

The NSC veneers are pinned at the top of the secure region, so `tfm_s.bin` and the signed image
are always region-sized and nearly fill the slot. Adding code does not grow them; running out of
region fails the link. Measure from the linker's `Memory region` table (or `readelf -lW`), never
from the size of `tfm_s.bin`.

| Option | Default | Cost |
|---|---|---|
| `<PART>_STDOUT_RTT` | ON | SEGGER RTT over J-Link, no UART wiring. **Leave it ON**: `OFF` selects `PLATFORM_DEFAULT_UART_STDOUT` and does not build as the projects ship — see §9 |
| `<PART>_RTT_BLOCKING` | OFF | ON blocks rather than dropping output |
| `TFM_EXCEPTION_INFO_DUMP` | ON | secure text ~3.4 KB. The one worth reconsidering for production |
| `TFM_SPM_DEBUG_TRACE` | ON | a few bytes. Needs `TFM_SPM_LOG_LEVEL` above `_SILENCE`, which `MinSizeRel`/`Release` set, and configure rejects the pair: pass `-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG` or `-DTFM_SPM_DEBUG_TRACE=OFF` |
| `<PART>_BL2_HALT_AT_MAIN` | OFF | BL2 spins at `main()` for debugger attach |
| `<PART>_ORPHAN_CHECK_STRICT` | OFF | makes an orphan section fatal; intended for CI |
| `<PART>_NS_IN_SPE_BUILD` | OFF | builds the NS image inside the secure build |
| `MCUBOOT_LOG_LEVEL` | `INFO` upstream; `OFF` only under `MinSizeRel`/`Release` | `INFO` costs BL2 text +5,960 B and bss +4,284 B. BL2 has its own region, so this does not touch the secure slot |
| `TFM_SPM_LOG_LEVEL`, `TFM_PARTITION_LOG_LEVEL`, `CONFIG_TFM_HALT_ON_CORE_PANIC` | silent / OFF | secure text +3,785 B together; both parts have region room |

---

## 7. Header-level tunables

Not cache variables, but the ones people need to change, with the constraint that bites.

| Symbol | Where | Constraint |
|---|---|---|
| `S_RAM_CODE_SIZE` | `region_defs.h` | RA6M5 only (`0xA00`). Holds `0x7d0` of RAM-resident flash P/E code plus an ld-inserted long-branch veneer. Overflow is `region CODE_RAM overflowed`. Revisit on FSP uprev. RA8M2 has no such window — `r_mram.c` needs no RAM-resident code |
| `S_DATA_EXTRA_NOINIT_SECTION_NAME` | `region_defs.h` | must stay outside `__bss_start__..__bss_end__` and be NOLOAD ([D012]) |
| `S_MSP_STACK_SIZE` | `region_defs.h` | `BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE`, asserted at build time, so the e2 project and the port must agree |
| `PS_NUM_ASSETS` | `config_tfm_target.h` | 5 on both, but the cap is per-part: RA6M5's 1,536 B PS block allows 5, RA8M2's 15,872 B allows 155. Asserted in `<part>_layout_checks.c`. **Erase data flash before the first boot after any change** |
| `PS_MAX_ASSET_SIZE` | `config_tfm_target.h` | 512. Not the binding constraint — capacity is a sum — and it has a floor of its own around 448 |
| `TFM_NV_COUNTERS_AREA_SIZE` | `flash_layout.h` | 2048 B; PS and ITS split what remains |
| `TFM_HAL_PS_SECTORS_PER_BLOCK` | `flash_layout.h` | `(area/sector)/2`. `num_blocks < 2` fails ITS and PS init outright, reported as pid 257 |
| `FLASH_AREA_IMAGE_SECTOR_SIZE` | `flash_layout.h` | `0x8000` on both. Restates an FSP value and is not machine-checkable against it — see the note in `<part>_layout_checks.c` and diff FSP's generated `mcuboot_config.h` after a pack uprev ([D054]) |
| OFS `OPTION_SETTING_*` | `region_defs.h` (RA6M5), generated `option_settings.h` (RA8M2) | **Brick hazard**: one `MEMORY` region per option group, enforced by `check_ofs.py` ([DESIGN.md](DESIGN.md) §8.4). RA6M5 programs only the groups placed in `region_defs.h`; any other group enabled in e2 is dropped without a diagnostic |

**OFS values are edited in the bootloader project**, not the secure one. Both projects define
the same `BSP_CFG_OPTION_SETTING_*` groups, so editing the wrong one has no effect and no
warning. Only `FSP_BL2_APP_DIR` is on the path for `bl2_option_setting.c`.

---

## 8. What is NOT a setting

- TrustZone boundaries and `setTZBoundaries`. Values are in
  [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) and [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md); the rules
  are in [GETTING_STARTED.md](GETTING_STARTED.md) §6.
- The memory layout. Change it in the e2 solution and regenerate; `region_defs.h` and all
  three linker scripts follow. What does not follow: the RDPM boundaries, PS capacity, and
  the NSC-window budget.

---

## 9. A release build

The scripts build development images. These options make a release build; keys, provisioning,
anti-rollback and lifecycle are in [DESIGN.md](DESIGN.md) §13 — **a release build with the sample
keys still trusts them**. Use a clean build directory:

```
-DCMAKE_BUILD_TYPE=MinSizeRel
-DTFM_EXCEPTION_INFO_DUMP=OFF
-DTFM_SPM_DEBUG_TRACE=OFF
-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_SILENCE
-DTFM_PARTITION_LOG_LEVEL=TFM_PARTITION_LOG_LEVEL_SILENCE
-DCONFIG_TFM_HALT_ON_CORE_PANIC=OFF
-DMCUBOOT_LOG_LEVEL=OFF
```

`TFM_SPM_DEBUG_TRACE=OFF` must accompany the silent log level, or configure fails. Build type:
§1. Leave `<PART>_STDOUT_RTT` ON (see below). Logging and halt-on-panic are off because they are
diagnostics, not for space; costs are in §6.

Re-measure against §6 and re-run the tests on the image you ship;
[TEST_RESULTS.md](TEST_RESULTS.md) does not cover this configuration.

> **`<PART>_STDOUT_RTT=OFF` does not build as shipped.** It compiles `Driver_USART.c` into the
> secure image and BL2, which need an SCI UART instance `g_uart0` that no shipped project has.
> For a UART console: add SCI UART as `g_uart0` to the secure and bootloader projects, declare it
> per [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) (`fsp_sci_uart.cmake`, `FSP_MODULES_S`,
> `FSP_MODULES_BL2`), and rebuild. Untested.
