# Configuration reference — every knob you may legitimately change

Scope: the options a user of this port sets, where each is defined, and the constraint that
makes it non-obvious. Every value below is verified against the code for both supported parts,
RA6M5 and RA8M2.

Read [DESIGN.md](DESIGN.md) §1 first. The core principle is that RASC is the source of config
truth: the memory layout and the enabled FSP modules come from the e2 projects, and the options
here sit on top of that rather than replacing it. Anything that contradicts the generated layout
is a defect, not a setting.

---

## How the three layers interact, and the one trap

```
e2 / RASC solution          partitions, FSP modules, OFS values, BSP_CFG_*
      |  generated Debug/bsp_linker_info.h, Debug/memory_regions.*
      v
<part>/config.cmake         the port's opinions - cache defaults
      |
      v
your -D on the command line wins over both
```

**The trap (D007):** a cache default in `<part>/config.cmake` beats `TFM_PROFILE`. Passing
`-DTFM_PROFILE=profile_medium` does not override `TFM_ISOLATION_LEVEL` or the
`TFM_PARTITION_*` set, because those are already in the cache by the time the profile file is
read. To change them, pass them explicitly.

**The second trap:** `set(X ON CACHE BOOL "")` does not overwrite an existing cache entry
without `FORCE`. If an option appears not to take effect, check `CMakeCache.txt` in the build
tree, not the config file. This has caught the port twice: a tree of hand-set debug options
no script reproduced ([D084]), and a stale tool path that survived regeneration ([D083]).

---

## 1. Build inputs — required

| Option | Meaning |
|---|---|
| `TFM_PLATFORM` | `renesas/ra6m5` or `renesas/ra8m2` |
| `FSP_S_APP_DIR` | the generated secure e2 project. Supplies `Debug/bsp_linker_info.h`, from which the whole layout is derived |
| `FSP_BL2_APP_DIR` | the generated bootloader project. Supplies the OFS values and the FSP driver modules BL2 needs ([D091] removed the FSP MCUboot backend from both parts) |
| `FSP_NS_APP_DIR` | the generated non-secure project |
| `TFM_TOOLCHAIN_FILE` | `toolchain_GNUARM.cmake` or `toolchain_IARARM.cmake` |
| `CMAKE_BUILD_TYPE` | `MinSizeRel` is not optional on GNUARM. `Debug` does not fit — `tfm_s` comes out around 414 KB against RA8M2's 293,376-byte (`0x47A00`) secure code region, as §6 defines it. IAR `Debug` does fit ([D055]; [D057] for why GNUARM `Debug` does not) |

The e2 project must have been built, not just generated. The TF-M build reads
`Debug/bsp_linker_info.h` and `Debug/memory_regions.*`, which only an e2 build produces.

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

**`FSP_MODULES_NEVER_BUILT` excludes nothing.** It names the directories that the
unclaimed-module audit should stay quiet about, for modules whose sources the port supplies or
compiles by another route. What keeps a module out of the secure and bootloader images is
simply not listing it in `FSP_MODULES_S` or `FSP_MODULES_BL2`. **Nothing keeps one out of the
non-secure image**: that side globs every module the project enables, minus `ra_gen/main.c`.
`FSP_EXCLUDED_MODULES` looks like the exception and is not — its only caller is guarded on
`<PART>_NS_IN_SPE_BUILD`, which is off by default.
[ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §2 sets the three mechanisms side by side.

**Adding an FSP module you enabled in e2.** e2 does not emit CMake modules, so a new module
needs three things, not two: a line in `FSP_MODULES_S` (or `_BL2`), an `FSP_MODULE_DIRS_<name>`
giving its source directories, and a `cmake/modules/fsp_<name>.cmake` file. `fsp_add_modules()`
`include()`s that file for every module listed, so naming a module without creating it aborts the
configure. [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) is the step-by-step. This is the known
gap in goal 3 ([DESIGN.md](DESIGN.md) §0) and is bridged by documentation rather than by code.

**Do not use a recursive glob for a module directory.** `rm_mcuboot_port` is the cautionary
case: `fsp_module_glob` is `GLOB_RECURSE` and would pull in `custom_crypto_stacks/`, `os/` and
`rm_mcuboot_port.c` alongside the one wanted file ([D079]).

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
| `DEFAULT_MCUBOOT_FLASH_MAP` | ON | ON | upstream default; the port does not set it. Both parts take TF-M's map and backend, with FSP's HAL behind `fa_driver` ([D091], superseding [D079], [D082], [D090]) |
| `DEFAULT_MCUBOOT_FLASH_BACKEND` | gone | gone | this variable no longer exists. It is not set in either `config.cmake`, and neither part supplies its own `flash_map_backend.h` or `sysflash.h` |

RA8M2's SAU programming moved with it. It used to arrive as a side effect of FSP's
`flash_area_open()`, which is why the backend override was load-bearing on that part. Under [D091]
it lives in `bl2_boot_hal.c`, with the bounds imported from FSP's `flash_map.c`.
[DESIGN.md](DESIGN.md) §4 is the current account; the `struct flash_area` guard-collision note in
[FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md) still applies if you ever reintroduce a platform
backend.

**Measured boot cannot be verified by the attestation suite.** With `component_cnt == 0` under
the default `ATTEST_TOKEN_PROFILE_PSA_IOT_1`, `attest_add_all_sw_components()` emits
`IAT_NO_SW_COMPONENTS` and returns success, so the suite passes whether or not measured boot
works. Read the boot record out of RAM instead ([D080], [D081]).

`MCUBOOT_IMAGE_VERSION` is a documented deviation. FSP expects an environment variable of
that name, read by `rm_mcuboot_port_sign.py`. This port uses TF-M's `MCUBOOT_IMAGE_VERSION_S`
(= `${TFM_VERSION}`) and `_NS` (= `0.0.0`) instead. **Setting the FSP variable has no effect
and fails silently.** [DESIGN.md](DESIGN.md) §1.1.

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

CCM runs in software on RA6M5 by design. FSP's SCE9 CCM caps associated data at 110 B and
Protected Storage exceeds it; CCM still reaches the engine per block through the cipher and AES
ALTs ([D043]).

---

## 6. Diagnostics — and what they cost

Two different limits get confused here, and only one of them constrains adding code.

**"Region" below means the secure *code* region**, the one the linker fills and reports —
`0x47A00` (293,376 B) on RA8M2. Two larger figures circulate for the same part and both are
correct about something else: add the 1,024 B non-secure-callable window and you get the
`0x47E00` (294,400 B) that `config.cmake` works in, which is also the 294,912 B slot minus its
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

**The signed image is region-sized, which is why the slot looks full.** The non-secure-callable
veneers are pinned at the top of the secure region, so `objcopy -O binary` spans the whole
region and `tfm_s.bin` comes out at 521,792 B on RA6M5 whatever the image costs. imgtool signs
*that*, so the signed artefact nearly fills the slot while the code occupies 62% of the region.

The consequence matters: **the ~1.8 KB and ~0.8 KB of slot spare do not limit how much code you
can add.** Adding code does not grow the signed image, because it is already region-sized. What
limits code is the region — about 198 KB spare on RA6M5 and 76 KB on RA8M2 — and exceeding it
fails the link, loudly, rather than failing to sign.

So the diagnostics below are affordable on both parts. An earlier revision of this section said
the opposite, having read the slot figure as the code budget; the three logging options cost
3,785 B against tens of kilobytes of region spare.

Read the region figures from the linker's own `Memory region` table in the build output, or from
`readelf -lW` summed over the LOAD segments inside the secure region. **Do not read
`tfm_s.bin`'s size as the image size**, for the reason above.

| Option | Default | Cost |
|---|---|---|
| `<PART>_STDOUT_RTT` | ON | SEGGER RTT over J-Link, no UART wiring. **Leave it ON**: `OFF` selects `PLATFORM_DEFAULT_UART_STDOUT` and does not build as the projects ship — see §9 |
| `<PART>_RTT_BLOCKING` | OFF | ON blocks rather than dropping output |
| `TFM_EXCEPTION_INFO_DUMP` | ON | secure text ~3.4 KB. The one worth reconsidering for production |
| `TFM_SPM_DEBUG_TRACE` | ON | a handful of bytes. ON requires `TFM_SPM_LOG_LEVEL` above `_SILENCE` - `check_config.cmake:119` rejects the pair, and `MinSizeRel`/`Release` set `_SILENCE`. Pass `-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG` or `-DTFM_SPM_DEBUG_TRACE=OFF`. Nothing to do with isolation or IPC ([D007]) |
| `<PART>_BL2_HALT_AT_MAIN` | OFF | BL2 spins at `main()` for debugger attach |
| `<PART>_ORPHAN_CHECK_STRICT` | OFF | makes an orphan section fatal; intended for CI |
| `<PART>_NS_IN_SPE_BUILD` | OFF | builds the NS image inside the secure build |
| `MCUBOOT_LOG_LEVEL` | `INFO` upstream; `OFF` only under `MinSizeRel`/`Release` | `INFO` costs BL2 text +5,960 B and bss +4,284 B. BL2 has its own region, so this does not touch the secure slot |
| `TFM_SPM_LOG_LEVEL`, `TFM_PARTITION_LOG_LEVEL`, `CONFIG_TFM_HALT_ON_CORE_PANIC` | silent / OFF | secure text +3,785 B for the three together, which both parts have region room for. The PSA Arch scripts pass them explicitly so the ordinary builds stay smaller, not because they would fail to link |

The PSA Arch scripts pass the last two groups explicitly, which is why they are per-script
rather than in `config.cmake` ([D084]): a suite run wants the logs and an ordinary build does
not. **It is not a space constraint** — both parts have region room for all three, as the table
above says.

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
| OFS `OPTION_SETTING_*` | `region_defs.h` (RA6M5), generated `option_settings.h` (RA8M2) | **BRICK HAZARD.** One `MEMORY` region per word; a coalesced `PT_LOAD` writes `0x00` into the eight defined option registers between the emitted words, and into the reserved bytes. Two boards were bricked this way and no recovery is known ([D133]; which of the eight registers does it is not established, and neither is whether the state is reversible). Invisible in the srec — `readelf -l` is the only place it shows. `check_ofs.py` enforces it ([D002]) |

**OFS values are edited in the bootloader project**, not the secure one. Both projects define
the same `BSP_CFG_OPTION_SETTING_*` groups, so editing the wrong one has no effect and no
warning. Only `FSP_BL2_APP_DIR` is on the path for `bl2_option_setting.c`.

---

## 8. What is NOT a setting

- TrustZone boundaries. Programmed once per board with RDPM and never by firmware. Values
  are in [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) and [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md), derived from the generated layout.
  **RDPM erases the part** — reflash all three images afterwards.
- `setTZBoundaries` in a launch configuration. Must be `false` for every probe the launch
  names, not only the selected one. The debugger
  derives boundaries from the launched project's symbols and gets them wrong against BL2
  ([DESIGN.md](DESIGN.md) §7.2).
- The memory layout. Change it in the e2 solution and regenerate; `region_defs.h` and all
  three linker scripts follow. What does not follow: the RDPM boundaries, PS capacity, and
  the NSC-window budget.

---

## 9. A release build

The scripts build development images. This is the build-option half of turning one into a
release image; the half that is not a build option — keys, provisioning, anti-rollback, the
device lifecycle — is [DESIGN.md](DESIGN.md) §13, and **a release build with the sample keys
still trusts the sample keys**.

Pass these on a clean build directory, because most are cached and several others derive from
them:

```
-DCMAKE_BUILD_TYPE=MinSizeRel
-DTFM_EXCEPTION_INFO_DUMP=OFF
-DTFM_SPM_DEBUG_TRACE=OFF
-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_SILENCE
-DTFM_PARTITION_LOG_LEVEL=TFM_PARTITION_LOG_LEVEL_SILENCE
-DCONFIG_TFM_HALT_ON_CORE_PANIC=OFF
-DMCUBOOT_LOG_LEVEL=OFF
```

**`TFM_SPM_DEBUG_TRACE` must go `OFF` in the same step as the log level.** It requires a level
above `_SILENCE`, and `check_config.cmake` rejects the pair rather than resolving it — which is
the one combination in this list that stops the build instead of producing a larger image.

| Decision | Value | Why |
|---|---|---|
| Build type | `MinSizeRel` | mandatory for GNUARM on RA8M2, where Debug comes out around 414 KB against a 293,376 B code region. RA6M5 Debug does fit, and a release image should not spend the room anyway |
| Build type, IAR | `MinSizeRel` as well | IAR Debug fits on both parts, so this is a size choice rather than a constraint |
| Console | **leave `<PART>_STDOUT_RTT` ON for now** | see the warning below. A release image with RTT on does carry a debug transport, but turning it off does not currently build |
| Logging | silent | the three log options together cost 3,785 B of secure text, which both parts have room for; turn them off for a release image because they are diagnostics, not because of space |
| Bootloader logging | `MCUBOOT_LOG_LEVEL=OFF` | `INFO` costs BL2 text +5,960 B and bss +4,284 B |
| Halt on panic | `OFF` | a release image should reset rather than spin where a debugger can find it |

**Re-measure, do not assume the image shrank.** Read the linker's own `Memory region` table
rather than the size of `tfm_s.bin`, which is region-sized whatever the image costs — §6 gives
the reason and the measured figures.

Then re-run the tests against the image you are actually shipping:
[TEST_RESULTS.md](TEST_RESULTS.md) records what has run here, and the configuration these
options produce is not one of them.

> **`<PART>_STDOUT_RTT=OFF` does not build as the projects ship.** It selects
> `PLATFORM_DEFAULT_UART_STDOUT`, which compiles `cmsis_drivers/Driver_USART.c` into both the
> secure image and the bootloader. That file includes `r_sci_uart.h` and calls
> `R_SCI_UART_Open(&g_uart0_ctrl, &g_uart0_cfg)`, and **no secure or bootloader project
> contains the SCI UART module or a `g_uart0` instance** — so it fails at the include, before
> any link. Switching the console to a UART therefore takes two changes, not one:
>
> 1. **In e2**, add the SCI UART module to the secure and bootloader projects, name the instance
>    `g_uart0`, regenerate and rebuild there.
> 2. **In the port**, write `cmake/modules/fsp_sci_uart.cmake` and list `sci_uart` in
>    `FSP_MODULES_S` and `FSP_MODULES_BL2`. Those two images are opt-in per module
>    ([ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §1–§3), and no such module file exists, so
>    step 1 alone leaves the driver unbuilt and the link unresolved.
>
> Established by reading the source, not by building it.
