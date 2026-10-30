# e2 project requirements — what a generated project must supply

The TF-M build reads its memory layout, FSP driver sources and several load-bearing settings from
the generated e2 projects; this is the contract they must satisfy. Most of it is enforced: a
missing requirement stops the build with an `#error` naming the setting and project. New part:
[PORTING.md](PORTING.md).

---

## 1. The three projects

The build takes three directories per part and toolchain, one per image:

| Variable | Role | RA6M5 | RA8M2 |
|---|---|---|---|
| `FSP_BL2_APP_DIR` | FSP driver modules for BL2, which is a flat build | `ra6m5_<tc>_mcuboot` | `ra8m2_<tc>_mcuboot` |
| `FSP_S_APP_DIR` | driver modules for the secure image, and the source of the layout | `ra6m5_<tc>_secure` | `ra8m2_<tc>_CPU0_secure` |
| `FSP_NS_APP_DIR` | the whole FSP application, built as `tfm_ns` | `ra6m5_<tc>_nonsecure` | `ra8m2_<tc>_CPU0_nonsecure` |

`<tc>` is `gcc` or `iar`. **Use the project set generated for the toolchain you build with.** All
three projects belong to one solution, which owns the partitioning; the GCC and IAR solutions
must agree on the layout, because both feed one set of TrustZone boundary values.

---

## 2. Files only an e2 build produces

Regenerating is not enough. These are build outputs, so a project that has never been built in
e2 cannot configure TF-M:

| File | Read by |
|---|---|
| `Debug/bsp_linker_info.h` | every image. Filtered to its `BSP_PARTITION_*` defines at configure time, because the rest of the file declares C types a linker script cannot take |
| `Debug/memory_regions.ld`, `Debug/memory_regions.icf` | the non-secure link, and on RA8M2 the option-memory addresses, filtered into a generated `option_settings.h` |
| `script/fsp.ld` | the non-secure link, used as the scatter file |

The build looks in `Debug/`; the standalone Smart Configurator writes these to the project root,
which the build does not read. Procedure: [GETTING_STARTED.md](GETTING_STARTED.md) §4.

---

## 3. The partition contract

`bsp_linker_info.h` must define these as `_START`/`_SIZE` pairs. The secure project's copy is
parsed, because only it carries the bootloader regions too.

| Group | Symbols |
|---|---|
| Bootloader | `FLASH_BL_CPU0_S`, `RAM_BL_CPU0_S` |
| Code and RAM | `FLASH_CPU0_S`, `FLASH_CPU0_C`, `FLASH_CPU0_N`, `RAM_CPU0_S`, `RAM_CPU0_C`, `RAM_CPU0_N` |
| Slot markers | `__BL_0_P_H`, `__BL_0_P_T`, `__BL_0_S_H`, `__BL_0_S_T`, and the same four for `__BL_1` |
| Storage, RA6M5 | `DATA_FLASH_CPU0_S`, `DATA_FLASH_CPU0_N` |
| Storage, RA8M2 | `DATA_FLASH_CPU0_S`, which must stay `0`, and `DF_EMULATION` |

Three geometry rules the layout has to keep, each asserted in `<part>_layout_checks.c`:

- **Partitions are contiguous and both slot pairs are the same size.** `fa_size` is a sum of
  sizes while the trailer magic is placed from the address span, so a hole makes imgtool and
  bootutil disagree about where the magic goes. Such an image boots, then fails its first
  upgrade.
- **The non-secure-callable region ends exactly where the non-secure region starts**, and lies
  inside the signed payload so the veneers are covered by the signature.
- **The header is `0x200` and both trailer partitions are zero-size end markers.** MCUboot
  takes its trailer from the slot tail. TF-M's default header is `0x400`, and `region_defs.h`
  stops the build on a mismatch.

Secure data flash must be large enough for the NV counters, Protected Storage and Internal
Trusted Storage together. `flash_layout.h` divides what it is given and stops below the
minimum.

---

## 4. Modules, per project

A module reaches the secure or bootloader image only if the port declares it; an extra module
enabled in e2 produces a configure-time warning.

| Project | Modules the build needs |
|---|---|
| secure | `bsp`, `flash`, `sce`, `agt` |
| bootloader | `bsp`, `flash`, and `sce` whenever `CRYPTO_HW_ACCELERATOR` is `ON`, which is the default |
| non-secure | whatever the application needs; the whole tree is globbed |

- **The flash driver differs per part**: `r_flash_hp` (instance `g_flash0`) on RA6M5; `r_mram`
  (instance `g_mram0`, shown in e2 as Flash with the MRAM implementation) on RA8M2.
- **The crypto engine directory under `r_sce` is discovered, not named**: `sce9` on RA6M5,
  `rsip_e50d` on RA8M2.
- **The SCE module** supplies the TRNG behind PSA's external RNG (without it the secure image has
  no entropy source) and, with `CRYPTO_HW_ACCELERATOR` ON (the default), the accelerated cipher,
  hash and ECC paths; BL2 takes it for its engine SHA-256.
- **AGT in the secure project, with a real interrupt priority.** Disabled emits no vector entry
  at all, and the FLIH and SLIH suites then cannot raise an interrupt. Configuring it in the
  secure project is also what makes the interrupt secure.
- **`rm_psa_crypto` and `rm_mcuboot_port` are not built into the secure or bootloader images**,
  because their crypto and flash-map configuration collides with TF-M's; those images list
  modules explicitly and do not list them. The non-secure image globs every enabled module and
  does compile them; `--gc-sections` drops what is unreferenced. (`FSP_MODULES_NEVER_BUILT` only
  silences the unclaimed-module warning.) Their headers must resolve, because the generated
  `common_data.h` and `hal_data.h` include them.
- **Generated file names stay standard.** The build excludes `ra_gen/main.c`,
  `Source/startup.c` and `bsp_linker.c` by name for the secure and bootloader images, because
  TF-M supplies all three. Renaming them makes the FSP versions collide at link.

---

## 5. Settings that are load-bearing

| Setting | Where | Consequence if wrong |
|---|---|---|
| Early BSP Initialization (`BSP_CFG_EARLY_INIT` = 1) | secure and bootloader | `SystemCoreClock` is zero after `SystemInit()` and the flash driver fails to open with `FSP_ERR_FCLK` |
| Main stack size | all three | it replaces the `g_init_info` and `g_main_stack` that the excluded `bsp_linker.c` would have defined, and it must match the secure image stack size the build expects |
| Option-setting words | bootloader only | the bootloader project is the only one whose option settings reach an image. Editing them in the secure project has no effect and gives no warning |

RA8M2 carries one guard per option word the port does not place, so a word enabled in e2 cannot
be silently dropped. RA6M5 has none, because it places the three words it emits.

---

## 6. Launch configurations

**`setTZBoundaries` must be `false` for every probe a launch names**
([GETTING_STARTED.md](GETTING_STARTED.md) §6; why: [DESIGN.md](DESIGN.md) §7.2).

Leave the J-Link options to erase code flash and data flash on download enabled
(`eraseRomOnDownload`, `eraseDataRomOnDownload`), so a stale storage area does not survive a
reflash.

---

## 7. What a project cannot supply

- **The TrustZone boundaries**, set once per board with the Device Partition Manager and
  recomputed on any repartition: values in [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) and
  [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md), procedure in [GETTING_STARTED.md](GETTING_STARTED.md)
  §6.
- **The option-memory placement rule**, which lives in the TF-M linker scripts
  ([DESIGN.md](DESIGN.md) §8.4). Re-run the check in [GETTING_STARTED.md](GETTING_STARTED.md) §6
  after any layout change.
