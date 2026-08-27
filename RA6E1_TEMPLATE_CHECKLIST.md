# RA6E1 solution template — what it must emit for TF-M

Derived from the TF-M port as it stands on 2026-08-26 (all three images building and signed).
Everything below is something the port **reads from a generated project**. If the template emits
it, a fresh solution builds TF-M with no hand-edits; if it does not, the failure mode is listed.

Companion docs: `RA6E1_SOLUTION.md` (current layout and TZ boundaries), `DESIGN.md` (why),
`TFM_INTEGRATION_COMPLETE.md` §"Adding New FSP Modules" (how to extend the CMake side).

---

## 1. Project set and names

The port takes three directories, and validates each has `ra/`, `ra_gen/`, `ra_cfg/`:

| Variable | Project | Role in the TF-M build |
|---|---|---|
| `FSP_BL2_APP_DIR` | `ra6e1_mcuboot` | FSP modules for BL2; **flat build** |
| `FSP_S_APP_DIR` | `ra6e1_secure` | FSP modules for the secure image; **source of the layout** |
| `FSP_NS_APP_DIR` | `ra6e1_nonsecure` | whole FSP application, built as `tfm_ns` |

- [ ] All three generate and **build cleanly in e2 standalone**. This is not optional politeness:
      the layout files are build outputs, so an unbuildable project is an unconfigurable TF-M.

---

## 2. Generated files the port consumes

Emitted into `<project>/Debug/` by the e2 build, so they exist only after a build there.

- [ ] `Debug/bsp_linker_info.h` — **all three projects** (existence is validated per project;
      the secure project's copy is the one actually parsed)
- [ ] `Debug/memory_regions.ld` — NS project (pulled in by `script/fsp.ld`)
- [ ] `script/fsp.ld` — NS project (used verbatim as the NS scatter file)
- [ ] `Debug/compile_commands.json` — not read by the build, but it is the reference for the
      generated-header include set in `cmake/modules/fsp_bsp.cmake`. Keep it emitted.

> The port hardcodes `Debug/`. RASC writes these to the project root instead — a known
> divergence, deliberately not abstracted while e2 is the only shape that produces solutions.

---

## 3. Partition symbols — the actual contract

`bsp_linker_info.h` is filtered down to its `#define BSP_PARTITION_*` lines at configure time
(the rest of the file declares C types that cannot be preprocessed into a linker script). The
port needs **exactly these**, in `_START` / `_SIZE` pairs unless noted:

| Group | Symbols |
|---|---|
| Bootloader | `FLASH_BL_CPU0_S_*`, `RAM_BL_CPU0_S_SIZE` |
| Image 0 (S) slots | `__BL_0_P_H_*`, `__BL_0_P_T_*`, `__BL_0_S_H_*`, `__BL_0_S_T_*` |
| Image 1 (NS) slots | `__BL_1_P_H_*`, `__BL_1_P_T_*`, `__BL_1_S_H_*`, `__BL_1_S_T_*` |
| Code partitions | `FLASH_CPU0_S_*`, `FLASH_CPU0_C_*`, `FLASH_CPU0_N_*` |
| RAM partitions | `RAM_CPU0_S_*`, `RAM_CPU0_C_*`, `RAM_CPU0_N_*` |
| Data flash | `DATA_FLASH_CPU0_S_*`, `DATA_FLASH_CPU0_N_*` |

- [ ] **The secure project emits the full set.** The port reads the layout from `ra6e1_secure`
      specifically because it is a strict superset — it carries the `RAM_BL` / `DATA_FLASH_BL` /
      `QSPI_FLASH_BL` entries the bootloader's own copy omits. If the template ever narrows what
      the secure project emits, the port loses the bootloader region.
- [ ] `FLASH_CPU0_C_START` lands **below** `__BL_0_P_T_START`, so the NSC veneers sit inside the
      signed payload. Currently `0x97C00` vs `0x98000`. Re-check on every repartition — see
      `RA6E1_SOLUTION.md`, "NSC placement".

---

## 4. Modules to enable, per project

A module reaches a TF-M image only if the port declares it. Enabling more in e2 is harmless for
the standalone build but produces a configure-time **warning** naming the module as not-in-image.

| Project | Must have | Also enabled, deliberately never linked into TF-M |
|---|---|---|
| `ra6e1_secure` | BSP + IOPORT, `r_flash_hp`, `r_sce` | — |
| `ra6e1_mcuboot` | BSP + IOPORT, `r_flash_hp` | `r_sce`, `rm_psa_crypto`, `rm_mcuboot_port` |
| `ra6e1_nonsecure` | whatever the NS app needs | — (whole tree is globbed) |

- [ ] `r_sce` in the **secure** project. Only the TRNG is taken (`sce_trng.c` → PSA external
      RNG); `--gc-sections` trims the rest to ~8 KB. Without it the secure image has no entropy
      source and falls back to the shared hard-coded NV seed.
- [ ] `r_flash_hp` in **both** S and BL2.
- [ ] The excluded three keep their **headers** resolvable — generated `common_data.h` /
      `hal_data.h` include them unconditionally even when nothing is instantiated. Their include
      paths are already listed and `EXISTS`-guarded in `fsp_bsp.cmake`; if a regenerated project
      needs another, read it off `Debug/compile_commands.json` (entry for `ra_gen/hal_data.c`).
- [ ] Generated file **names** stay standard. The port excludes `ra_gen/main.c`,
      `.../Source/startup.c` and `bsp_linker.c` by name for S and BL2 (TF-M supplies all three).
      Renaming them means FSP's versions collide at link.
- [ ] **Remove LittleFS from the FSP mbedTLS / `rm_psa_crypto` stack.** The stock stacking wires
      PSA ITS down to LittleFS for key storage. TF-M provides ITS itself — the
      `TFM_PARTITION_INTERNAL_TRUSTED_STORAGE` partition owns the secure data flash, backed by
      `Driver_FLASH1` — so the two implementations both claim that role and the FSP one drags in
      a filesystem the secure image has no use for. Dropping LFS from the stack in the template
      avoids having to unpick it per project. See DESIGN.md §6.

      Note this does not change what TF-M links today: `rm_psa_crypto` and `ra/arm/mbedtls` are
      already in `FSP_MODULES_NEVER_BUILT`, so nothing from them reaches a signed image. The
      reason to fix it in the template is that the module has to stay **generatable and buildable
      standalone** — it is the path to hardware-accelerated crypto later, and that switch is much
      easier if the storage backend was never LittleFS.

---

## 5. BSP configuration, per project

| Setting | `ra6e1_secure` | `ra6e1_mcuboot` | `ra6e1_nonsecure` |
|---|---|---|---|
| `BSP_CFG_EARLY_INIT` | **1** | **1** | 0 |
| `BSP_CFG_STACK_MAIN_BYTES` | sane non-zero | sane non-zero | sane non-zero |

- [ ] `BSP_CFG_EARLY_INIT = 1` in **secure and bootloader**. It is what puts `SystemCoreClockUpdate()`
      on the path before `main()`. Without it `R_FLASH_HP_Open()` sees FCLK 0 and returns
      `FSP_ERR_FCLK` — the July 2026 failure. NS does not need it (`DESIGN.md` §8.1).
- [ ] `BSP_CFG_STACK_MAIN_BYTES` — consumed by `bsp_init_stub.c`, which weakly replaces the
      `g_init_info` / `g_main_stack` that FSP's excluded `bsp_linker.c` would have defined.

**`BSP_CFG_CLOCKS_SECURE` is no longer a requirement.** It was, until BL2 became a flat build
(commit `9e3a10ef4`). Flat takes the `#else` branch of `bsp_mcu_ofs_cfg.h`, which emits
`OFS1_SEL = 0xFFFFF8F8` unconditionally and never reads the setting. BL2 is the only image that
emits OFS at all, so the setting now has no effect on any TF-M image. Note also that
`ra_gen/bsp_clock_cfg.h` defines it **unguarded**, so `-D` can never override it — if a future
change does need it set, it has to be set in the project.

---

## 6. MCUboot module settings

**TF-M builds its own BL2** from its own vendored MCUboot, with its own keys; `ra6e1_mcuboot`
contributes only FSP driver modules. So these settings govern the **standalone** bootloader, and
only the ones the shared flash layout implies have to agree with `config.cmake`. Verified
2026-08-26: switching this project from `signature.none` to ECDSA P-256 left `bl2.axf`,
`tfm_s_signed.bin` and `tfm_ns_signed.bin` byte-identical.

The two bootloaders are separate binaries with different keys — images signed for one will not
boot under the other. A mismatch is not a build error.

- [ ] `MCUBOOT_IMAGE_NUMBER` = **2** — dual image
- [ ] Signature **ECDSA P-256**. ⚠ The template's default is **Signature Type: None**, which
      silently reduces the standalone bootloader to a SHA-256 hash check — it boots, and looks
      like it validated. This project set ran that way until 2026-08-26. Does not affect TF-M's
      BL2 (see the note above), but it is the wrong default to ship.
- [ ] Upgrade mode **overwrite-only** (hence no scratch area)
- [ ] **Validate primary slot** enabled — the secure image's trailer is NS-writable by
      construction (RA has one secure region and it precedes the NSC), so this is what bounds
      that to a DoS. Do not turn it off.
- [ ] Header **`0x200`** / trailer **`0x100`**. `config.cmake` reads these out of
      `bsp_linker_info.h` (`___BL_0_P_H_SIZE`, `___BL_0_P_T_SIZE`) because TF-M's own defaults
      are `0x400` — and those cache values are what **imgtool signs with**. Left at the default,
      the payload is placed `0x400` into the slot while the image is linked for slot+`0x200`:
      a silently unbootable image. `region_defs.h` now `#error`s on the mismatch.

---

## 7. Sizing the default layout

Measured from the current build; leave headroom rather than fitting exactly.

| Image | `text` | Slot code region | Used |
|---|---|---|---|
| bl2 | 55 540 | `0x18000` (96K) | 57% |
| tfm_s | 175 838 | `0x3FD00` (255.25K) | 67% |
| tfm_ns | 3 334 | `0x2FD00` (191.25K) | 2% |

- [ ] Secure slot **≥ 256K**. TF-M's secure image is the binding constraint, and the current 67%
      is with `CRYPTO_HW_ACCELERATOR` **off** — the SCE cipher stack will grow it.
- [ ] Bootloader **96K** is comfortable at 57%.
- [ ] **Data flash: give the secure side more than 4 KB if the template can.** This is the one
      genuinely tight resource. The RA6M4 port uses ~7 KB of 8 KB (NV counters 2K + PS 3K +
      ITS 2K); the current solution gives the secure side 4 KB and the rest to NS. `flash_layout.h`
      splits what it has proportionally and `#error`s below 4 KB, but there is no wear-levelling
      headroom at that size.

> Do not size the secure image from `ld --print-memory-usage` — it reports 99.85% because the
> veneers are pinned at the top of FLASH, so the region always reads as full. Use `arm-none-eabi-size`.

---

## 8. Launch configurations

- [ ] `com.renesas.hardwaredebug.arm.jlink.setTZBoundaries` = **`false`** in **every** launch
      config the template emits. It defaults to **enabled**, derives boundaries from the launched
      project's symbols, and cannot handle a bootloader *and* a secure image sharing the secure
      region — launched against the bootloader it marks everything secure and silently undoes a
      correct partition. TF-M's BL2 is exactly the same shape. `DESIGN.md` §7.2.

---

## 9. What the template still cannot supply

- **TrustZone boundaries.** Nothing in the firmware ever programs them; they are set once per
  board with the Renesas Device Partition Manager, in KB, and must be recomputed on every
  repartition against the 32 KB (code) / 8 KB (SRAM) granularity rule. Current values in
  `RA6E1_SOLUTION.md`.
- **The OFS discrete-region rule.** `ra6e1_bl2.ld` must keep thirteen **discrete** `MEMORY`
  regions, each `> REGION`. One coalesced `PT_LOAD` zero-fills 368 bytes of FCU config including
  the FSPR permanence word and permanently bricks the part — invisible in the srec, and it cost
  two EK-RA6M4 boards on 2026-07-21. This lives in the TF-M port, not the template, but any
  layout change should be re-verified: `arm-none-eabi-readelf -l bin/bl2.axf`.
