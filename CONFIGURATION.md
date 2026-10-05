# Configuration reference — every knob you may legitimately change

Scope: the options a user of this port sets, where each is defined, and the constraint that
makes it non-obvious. Verified against the code on **2026-10-04** for the two live parts,
RA6M5 and RA8M2.

Read `DESIGN.md` §1 first. The core principle is that **RASC is the source of config truth**:
the memory layout and the enabled FSP modules come from the e2 projects, and the options here
sit on top of that rather than replacing it. Anything that contradicts the generated layout is
a defect, not a setting.

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

**The trap (D007):** a cache default in `<part>/config.cmake` **beats `TFM_PROFILE`**. Passing
`-DTFM_PROFILE=profile_medium` does *not* override `TFM_ISOLATION_LEVEL` or the
`TFM_PARTITION_*` set, because those are already in the cache by the time the profile file is
read. To change them, pass them explicitly.

**The second trap:** `set(X ON CACHE BOOL "")` does **not** overwrite an existing cache entry
without `FORCE`. If an option appears not to take effect, check `CMakeCache.txt` in the build
tree, not the config file. This has cost real debugging time twice ([D083], [D084]).

---

## 1. Build inputs — required

| Option | Meaning |
|---|---|
| `TFM_PLATFORM` | `renesas/ra6m5` or `renesas/ra8m2` |
| `FSP_S_APP_DIR` | the generated **secure** e2 project. Supplies `Debug/bsp_linker_info.h`, from which the whole layout is derived |
| `FSP_BL2_APP_DIR` | the generated **bootloader** project. Supplies the OFS values and, on RA8M2, FSP's MCUboot backend |
| `FSP_NS_APP_DIR` | the generated **non-secure** project |
| `TFM_TOOLCHAIN_FILE` | `toolchain_GNUARM.cmake` or `toolchain_IARARM.cmake` |
| `CMAKE_BUILD_TYPE` | **`MinSizeRel` is not optional on GNUARM.** `Debug` does not fit — `tfm_s` comes out around 414 KB against RA8M2's 293 KB secure region. IAR `Debug` does fit ([D056]) |

**The e2 project must have been BUILT, not just generated.** The TF-M build reads
`Debug/bsp_linker_info.h` and `Debug/memory_regions.*`, which only an e2 build produces.

---

## 2. FSP module selection

These decide which FSP sources are compiled into which image. They live in
`<part>/CMakeLists.txt`, not `config.cmake`.

| Variable | RA6M5 | RA8M2 |
|---|---|---|
| `FSP_MODULES_S` | `bsp flash sce agt` | `bsp flash sce agt` |
| `FSP_MODULES_BL2` | `bsp flash` | `bsp flash mcuboot_port` |
| `FSP_MODULE_DIRS_flash` | `r_flash_hp` | **`r_mram`** — MRAM, not HP flash |
| `FSP_MODULE_DIRS_mcuboot_port` | — | `rm_mcuboot_port` |
| `FSP_MODULES_NEVER_BUILT` | `r_sce rm_psa_crypto rm_mcuboot_port` | `r_sce rm_psa_crypto` |

`FSP_MODULES_NEVER_BUILT` lists modules whose sources the port supplies or compiles by another
route; naming one here keeps the generic module glob from also building it.

**Adding an FSP module you enabled in e2.** e2 does not emit CMake modules, so a new module
needs one line in `FSP_MODULES_S` (or `_BL2`) and one `FSP_MODULE_DIRS_<name>` giving its source
directories. This is the known gap in goal 3 (`DESIGN.md` §0) and is bridged by documentation
rather than by code.

**Do not use a recursive glob for a module directory.** `rm_mcuboot_port` is the cautionary
case: `fsp_module_glob` is `GLOB_RECURSE` and would pull in `custom_crypto_stacks/`, `os/` and
`rm_mcuboot_port.c` alongside the one wanted file ([D079]).

---

## 3. MCUboot and the flash layout

| Option | RA6M5 | RA8M2 | Notes |
|---|---|---|---|
| `MCUBOOT_IMAGE_NUMBER` | 2 | 2 | secure + non-secure. BL2 loads them in **reverse** order (`bl2_main.c`) |
| `MCUBOOT_SIGNATURE_TYPE` | `EC-P256` | `EC-P256` | must match the solution |
| `MCUBOOT_UPGRADE_STRATEGY` | `OVERWRITE_ONLY` | `OVERWRITE_ONLY` | scratch is unused; see `RA6M5_SOLUTION.md` on why its block is still reserved |
| `MCUBOOT_ALIGN_VAL` | **128** | **32** | **flag day** — imgtool encodes it into the boot magic when it is not 8, so images signed at one value are rejected by a BL2 built at another. The two parts' images are not interchangeable |
| `MCUBOOT_USE_PSA_CRYPTO` | ON | ON | required for `EC-P256` |
| `MCUBOOT_HW_KEY` | OFF | OFF | |
| `MCUBOOT_MEASURED_BOOT` | ON | ON | boot record per image |
| `MCUBOOT_DATA_SHARING` | ON | ON | **this is the one that does the work** — without it BL2 writes no boot record and `MEASURED_BOOT` has nothing to carry |
| `DEFAULT_MCUBOOT_FLASH_MAP` | default ON | **OFF** | |
| `DEFAULT_MCUBOOT_FLASH_BACKEND` | default ON | **OFF** | RA8M2 takes both from FSP, because FSP's `flash_area_open()` programs the SAU. RA6M5 has no SAU and stays on TF-M's ([D079], [D085]) |

**Measured boot cannot be verified by the attestation suite.** With `component_cnt == 0` under
the default `ATTEST_TOKEN_PROFILE_PSA_IOT_1`, `attest_add_all_sw_components()` emits
`IAT_NO_SW_COMPONENTS` and returns success — so the suite passes whether or not measured boot
works. Read the boot record out of RAM instead ([D080], [D081]).

**`MCUBOOT_IMAGE_VERSION` is a documented deviation.** FSP expects an environment variable of
that name, read by `rm_mcuboot_port_sign.py`. This port uses TF-M's `MCUBOOT_IMAGE_VERSION_S`
(= `${TFM_VERSION}`) and `_NS` (= `0.0.0`) instead. **Setting the FSP variable has no effect and
fails silently.** `DESIGN.md` §1.1.

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

**CCM is deliberately in software on RA6M5.** FSP's SCE9 CCM caps associated data at 110 B and
Protected Storage exceeds it; CCM still reaches the engine per block through the cipher and AES
ALTs ([D043]).

---

## 6. Diagnostics — and what they cost

The secure slot is nearly full on both parts, so these are a space decision, not a free choice:

```
            raw tfm_s.bin   signed payload ends   slot        true spare
RA6M5           521,792             522,579    524,288         1,693 B
RA8M2           293,440             294,226    294,912           670 B
```

Measured 2026-10-04 by locating the 0xFF gap between the signed payload and the 16-byte
trailer at the top of the slot. Earlier figures here said 1,984 B and 960 B; those were
`raw image + header` against the slot and omitted the ~275 B of imgtool TLVs (signature and
hashes) and the trailer, which overstated RA8M2's headroom by 30%.

| Option | Default | Cost |
|---|---|---|
| `<PART>_STDOUT_RTT` | ON | SEGGER RTT over J-Link, no UART wiring. OFF selects `PLATFORM_DEFAULT_UART_STDOUT` |
| `<PART>_RTT_BLOCKING` | OFF | ON blocks rather than dropping output |
| `TFM_EXCEPTION_INFO_DUMP` | ON | secure text ~3.4 KB. The one worth reconsidering for production |
| `TFM_SPM_DEBUG_TRACE` | ON | a handful of bytes. **Must stay off at isolation 3 + IPC** |
| `<PART>_BL2_HALT_AT_MAIN` | OFF | BL2 spins at `main()` for debugger attach |
| `<PART>_ORPHAN_CHECK_STRICT` | OFF | makes an orphan section fatal; intended for CI |
| `<PART>_NS_IN_SPE_BUILD` | OFF | builds the NS image inside the secure build |
| `MCUBOOT_LOG_LEVEL` | `OFF` | `INFO` costs **BL2** text +5,960 B and bss +4,284 B. BL2 has its own region, so this does not touch the secure slot |
| `TFM_SPM_LOG_LEVEL`, `TFM_PARTITION_LOG_LEVEL`, `CONFIG_TFM_HALT_ON_CORE_PANIC` | silent / OFF | **secure** text +3,785 B for the three together — more than RA6M5's 1,984 B of headroom, so they cannot be enabled globally |

The PSA Arch scripts pass the last two groups explicitly, because `profile_large` at isolation 3
has the room and the ordinary builds do not. That is why they are per-script rather than in
`config.cmake` ([D084]).

---

## 7. Header-level tunables

Not cache variables, but the ones people need to change, with the constraint that bites.

| Symbol | Where | Constraint |
|---|---|---|
| `S_RAM_CODE_SIZE` | `region_defs.h` | **RA6M5 only** (`0xA00`). Holds `0x7d0` of RAM-resident flash P/E code plus an ld-inserted long-branch veneer. Overflow is `region CODE_RAM overflowed`. Revisit on FSP uprev. RA8M2 has no such window — `r_mram.c` needs no RAM-resident code |
| `S_DATA_EXTRA_NOINIT_SECTION_NAME` | `region_defs.h` | must stay outside `__bss_start__..__bss_end__` and be NOLOAD ([D012]) |
| `S_MSP_STACK_SIZE` | `region_defs.h` | `BSP_CFG_STACK_MAIN_BYTES + STACKSEAL_SIZE`, asserted at build time, so the e2 project and the port must agree |
| `PS_NUM_ASSETS` | `config_tfm_target.h` | 5 on both, but the **cap is per-part**: RA6M5's 1,536 B PS block allows 5, RA8M2's 15,872 B allows 155. Asserted in `<part>_layout_checks.c`. **Erase data flash before the first boot after any change** |
| `PS_MAX_ASSET_SIZE` | `config_tfm_target.h` | 512. Not the binding constraint — capacity is a sum — and it has a floor of its own around 448 |
| `TFM_NV_COUNTERS_AREA_SIZE` | `flash_layout.h` | 2048 B; PS and ITS split what remains |
| `TFM_HAL_PS_SECTORS_PER_BLOCK` | `flash_layout.h` | `(area/sector)/2`. `num_blocks < 2` fails ITS **and** PS init outright, reported as pid 257 |
| `FLASH_AREA_IMAGE_SECTOR_SIZE` | `flash_layout.h` | `0x8000` on both. **Restates an FSP value** and is not machine-checkable against it — see the note in `<part>_layout_checks.c` and diff FSP's generated `mcuboot_config.h` after a pack uprev ([D054]) |
| OFS `OPTION_SETTING_*` | `region_defs.h` (RA6M5), generated `option_settings.h` (RA8M2) | **BRICK HAZARD.** One `MEMORY` region per word; a coalesced `PT_LOAD` zero-fills the gaps and programs block protect to 0, permanently. Invisible in the srec — `readelf -l` is the only place it shows. `check_ofs.py` enforces it ([D002]) |

**OFS values are edited in the BOOTLOADER project**, not the secure one. Both projects define
the same `BSP_CFG_OPTION_SETTING_*` groups, so editing the wrong one has no effect and no
warning. Only `FSP_BL2_APP_DIR` is on the path for `bl2_option_setting.c`.

---

## 8. What is NOT a setting

- **TrustZone boundaries.** Programmed once per board with RDPM and never by firmware. Values
  are in `RA6M5_SOLUTION.md` and `RA8M2_SOLUTION.md`, derived from the generated layout. RDPM
  **erases the part** — reflash all three images afterwards.
- **`setTZBoundaries` in a launch configuration.** Must be `false` everywhere. The debugger
  derives boundaries from the launched project's symbols and gets them wrong against BL2
  (`DESIGN.md` §7.2).
- **The memory layout.** Change it in the e2 solution and regenerate; `region_defs.h` and all
  three linker scripts follow. What does *not* follow: the RDPM boundaries, PS capacity, and
  the NSC-window budget.
