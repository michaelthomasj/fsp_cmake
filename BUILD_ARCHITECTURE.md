# Build Architecture — what builds what, and what links where

The CMake target graph of the port: two projects, the `api_ns/` handoff, and the FSP module
libraries added to upstream TF-M's targets. Line numbers are `ra6m5/CMakeLists.txt` unless
marked; `ra8m2` has the same targets at different lines (§3 lists both). Why the port is built
this way: [DESIGN.md](DESIGN.md) §1.

## 1. Two projects, not one

The secure and non-secure sides are separate CMake projects. The first installs an
`api_ns/` tree; the second is configured against that tree, not against TF-M's source.

- `CMAKE_INSTALL_PREFIX` defaults to `<build dir>/api_ns` — `config/config_base.cmake:17`.
- `api_ns/` carries `interface/{include,src,lib}`, `image_signing/` and
  `cmake/toolchain_ns_GNUARM.cmake`.
- The NS project needs both `CONFIG_SPE_PATH` and `TFM_TOOLCHAIN_FILE` pointing into it.

Regression builds configure the SPE from `tf-m-tests/tests_reg/spe` and the NS project from
`tf-m-tests/tests_reg`; application builds use the TF-M root and `<part>/ns_app`. The diagram
shows the regression flow.

```
e2 studio solution            SPE project                     NS project
(inputs; never built          cmake -S tests_reg/spe          cmake -S tests_reg
 by CMake)                    (regression; the app build      (regression; the app build
                               uses the TF-M root)             uses <part>/ns_app)
                                                        .
ra6m5_gcc_mcuboot --BL2_APP_DIR--> bl2.axf --> bl2.hex / bl2.srec
                                              (flashed raw, NEVER signed)

ra6m5_gcc_secure  ----S_APP_DIR--> tfm_s.axf --> imgtool --> tfm_s_signed.bin
                                      |
ra6m5_gcc_nonsecure --NS_APP_DIR-->   | cmake --build <spe> -- install
                                      v
                                   api_ns/
                                     +-- interface/{include,src,lib}
                                     +-- image_signing/
                                     +-- cmake/toolchain_ns_GNUARM.cmake
                                      |
                                      |  -DCONFIG_SPE_PATH=<spe>/api_ns
                                      |  -DTFM_TOOLCHAIN_FILE=.../toolchain_ns_GNUARM.cmake
                                      v
                                                        tfm_ns.axf
                                                            |
                                                            v
                                                 imgtool --> tfm_ns_signed.bin
```

- The three e2 projects are inputs only: generated FSP sources, `bsp_linker_info.h` (the
  partition addresses) and the OFS values.
- The SPE project records `FSP_NS_APP_DIR` into `api_ns` so the NS project builds against the
  same e2 project; it compiles NS sources only under `<PART>_NS_IN_SPE_BUILD` (OFF).
- BL2 is not signed; flash `bl2.elf`, `.hex` or `.srec`, never `bl2.bin`
  ([GETTING_STARTED.md](GETTING_STARTED.md) §6). Only `tfm_s` and `tfm_ns` go through `imgtool`.

The invocations are in `scripts/` — see [scripts/README.md](scripts/README.md).

## 2. The library graph

Two executables in the SPE project, one in the NS project. No target below is the port's
own: the port adds sources to six upstream targets (§3) and supplies the FSP module
libraries (§4).

```
tfm_s (exe)                             secure_fw/CMakeLists.txt:57
  +-- PRIVATE  secure_fw                INTERFACE lib, :51
  |              +-- INTERFACE tfm_spm
  |              +-- INTERFACE tfm_partitions
  +-- PRIVATE  platform_s
  +-- PRIVATE  psa_interface
  +-- PRIVATE  tfm_sprt

tfm_spm                                 secure_fw/spm/CMakeLists.txt:95
  +-- PUBLIC   tfm_arch, tfm_spm_defs
  +-- PRIVATE  platform_s, tfm_boot_status, tfm_config, tfm_partitions,
               tfm_fih_headers, tfm_sprt          <-- unconditional; see §6

tfm_sprt                   secure_fw/partitions/lib/runtime/CMakeLists.txt:39
  +-- PUBLIC   psa_interface, tfm_spm_defs, tfm_config, platform_s, tfm_vprintf
  +-- PRIVATE  tfm_spm, psa_crypto_config

psa_interface (INTERFACE)               interface/CMakeLists.txt:29
  +-- INTERFACE tfm_config
      carries TFM_ISOLATION_LEVEL and CONFIG_TFM_PARTITION_META   (:37, :40)

platform_s                              platform/CMakeLists.txt:95
  +-- PUBLIC   platform_common_interface, platform_region_defs,
  |            tfm_fih_headers, cmsis, cmsis_stack_override
  +-- PUBLIC   fsp_bsp_s, fsp_flash_s, fsp_sce_s, fsp_agt_s   <-- port, :385
  +-- PRIVATE  tfm_config, tfm_spm_defs, psa_crypto_library_config
  +-- PRIVATE  tfm_sprt    ONLY if PLATFORM_DEFAULT_ATTEST_HAL  (:109)

bl2 (exe)                               bl2/CMakeLists.txt:147
  +-- PUBLIC   bootutil                 bl2/ext/mcuboot/CMakeLists.txt:70
  |              +-- PUBLIC mcuboot_config, platform_bl2, bl2_crypto   (:30)
  +-- PUBLIC   bl2_crypto

platform_bl2
  +-- PUBLIC   fsp_bsp_bl2, fsp_flash_bl2 (+ fsp_sce_bl2)      <-- port, :696
```

- `bl2` does not link `platform_bl2`. The only route is `bl2 -> bootutil -> platform_bl2`,
  both PUBLIC. A platform symbol missing from the BL2 link is a `bootutil` problem, not a
  `bl2` one.
- Two cycles are intentional (`tfm_spm` <-> `tfm_sprt`; `platform_s` <-> `tfm_sprt` when the
  attest HAL is on). CMake repeats archives to resolve them, so link trouble here is usually
  archive order.
- `PLATFORM_DEFAULT_ATTEST_HAL` is OFF on both parts (the port supplies `attest_hal.c`), which is
  what §6 depends on.

## 3. What the port adds to each upstream target

| Target | ra6m5 | ra8m2 | Sources added |
|---|---|---|---|
| `platform_s` | 387 | 537 | Unconditional: `target_cfg.c`, `tfm_hal_platform.c`, `tfm_peripherals_def.c`, `attest_hal.c`, `cmsis_drivers/Driver_Flash.c`, `sce_trng.c`, `ra_sce_init.c`, `<part>_layout_checks.c`. Under FLIH/SLIH: `tfm_hal_nvic.c`, `tfm_timer0_irq.c` (`plat_test.c` stays in `tfm_sprt`). RTT off: `Driver_USART.c` |
| `tfm_sprt` | 453 | 595 | `plat_test.c` under FLIH/SLIH, with `platform_s`'s include list scoped to that one file, because `tfm_sprt` links into every partition |
| `tfm_spm` | 517 | 648 | `ext/common/tfm_hal_isolation_v8m.c` — the upstream file. **Do not move it back to `platform_s`**; see §6 |
| `tfm_s` | 607 | 724 | `startup_<part>.c` |
| `platform_bl2` | 704 | 821 | `target_cfg.c`, `tfm_hal_platform.c` (for `__STACK_SEAL`), `cmsis_drivers/Driver_Flash.c`, plus RTT or USART stdout. Built with `<PART>_BUILDING_BL2` and no `_RA_TZ_`: BL2 is a flat build |
| `bl2` | 728 | 843 | `startup_<part>.c`, `bl2_option_setting.c` (the OFS emitter). `bl2_boot_hal.c`: under `CRYPTO_HW_ACCELERATOR` on ra6m5; unconditional on ra8m2, where it enables the SAU. `ra_sce_init.c`: under the accelerator on both |
| `tfm_ns` | 1065 | 1204 | Only under `<PART>_NS_IN_SPE_BUILD` (OFF): `rtt/SEGGER_RTT.c`, `rtt/rtt_ns_init.c` |

The default build has no `tfm_ns` target in the SPE project; `<PART>_NS_IN_SPE_BUILD` (OFF)
exists only for boot bisection.

## 4. The FSP module registry

e2 studio does not emit CMake. The port turns each FSP driver into its own static library
through a registry, so modules are opted into by name rather than globbed off disk, and
anything in the project that no module claims is reported rather than silently dropped.

```
FSP_MODULES_S   = bsp flash sce agt              :234
FSP_MODULES_BL2 = bsp flash (+ sce if CRYPTO_HW_ACCELERATOR)   :238, :242
FSP_MODULE_DIRS_bsp   = bsp r_ioport             :247
                _flash = r_flash_hp  _sce = r_sce  _agt = r_agt
          |
          v
fsp_add_modules(role, dir, includes, out_targets)         :269
          |                     called at :384 (s) and :695 (bl2)
          +-- include() cmake/modules/fsp_module_common.cmake   once
          |      add_library(fsp_<name>_<role> STATIC)      common:33
          +-- include() cmake/modules/fsp_<name>.cmake       per name
          |      -> a missing file here is a HARD configure failure
          |
          +-- glob ra/fsp/src/* ; for each directory:
                 unclaimed AND not in FSP_MODULES_NEVER_BUILT
                   -> message(WARNING) "it is NOT in the image"      :293

the module libraries are not a flat set:

    fsp_flash_<role> --PUBLIC--+
    fsp_sce_<role>   --PUBLIC--+--> fsp_bsp_<role>
    fsp_agt_<role>   --PUBLIC--+
```

- Registry rules, the three exclusion mechanisms and the non-secure glob:
  [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) §2.
- Every non-`bsp` module PUBLIC-links `fsp_bsp_<role>`.
- `rm_psa_crypto` and `ra/arm/mbedtls` are excluded as FSP modules; the `*_ALT` sources come from
  `platform/ext/accelerator/renesas/{sce9,rsip_e50d}` and the library from the
  `cmake/fsp_mbedtls.cmake` overlay, which `FORCE`-sets `MBEDCRYPTO_PATH`. What is excluded is
  FSP's PSA/ITS configuration, which wires PSA ITS to littlefs and conflicts with
  `TFM_PARTITION_INTERNAL_TRUSTED_STORAGE`. `rm_mcuboot_port` is excluded because its own
  `FLASH_AREA_*_ID` values and single-image assumptions conflict with TF-M's dual-image flash
  map ([DESIGN.md](DESIGN.md) §4).

## 5. After the link

| Step | Line | Does what |
|---|---|---|
| orphan-section check | 837 | Fails on any section the linker script did not place, against a short allowlist |
| `check_ofs.py` | 915 | Fails if a `PT_LOAD` in the linked ELF coalesces the option-setting words; the only place the mistake is visible ([DESIGN.md](DESIGN.md) §8.4) |
| `--emit-safe-bin` | 958 | Re-emits the flat binary address-driven, because `objcopy -O binary` zero-fills the gaps and can lock the part. Building `bl2_bin` alone still writes the unsafe image ([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §4) |
| `imgtool` | — | Signs `tfm_s` and `tfm_ns` into their slots, using the layouts installed under `api_ns/image_signing/`. Slot overflow fails here, after a clean link |

## 6. Why the isolation HAL's target is load-bearing

`ext/common/tfm_hal_isolation_v8m.c` switches on six macros; four arrive as compile definitions,
so the target it is compiled into decides whether it sees them.

| Macro | Delivered by | Reaches `platform_s`? | Reaches `tfm_spm`? |
|---|---|---|---|
| `CONFIG_TFM_ENABLE_MEMORY_PROTECT` | CMake — `platform_s` PUBLIC, `platform/CMakeLists.txt:125` | yes | yes |
| `TFM_PXN_ENABLE` | CMake — `platform_s` PUBLIC, `platform/CMakeLists.txt:126` | yes | yes |
| `TFM_ISOLATION_LEVEL` | CMake — `psa_interface` INTERFACE, `interface/CMakeLists.txt:37` | no | yes |
| `CONFIG_TFM_PARTITION_META` | CMake — `psa_interface` INTERFACE, `interface/CMakeLists.txt:40` | no | yes |
| `CONFIG_TFM_MMIO_REGION_ENABLE` | header — generated `config_impl.h` | yes | yes |
| `PLATFORM_STATIC_MPU_REGIONS` | header — the platform's `tfm_peripherals_def.h` (`:268`) | yes | yes |

```
psa_interface  --PUBLIC--  tfm_sprt  --PRIVATE-->  tfm_spm     always
                               ^
                               |  PRIVATE, only if
                               |  PLATFORM_DEFAULT_ATTEST_HAL=ON  (OFF here)
                           platform_s
```

Consequence: compiled into `platform_s`, the file sees `TFM_ISOLATION_LEVEL` and
`CONFIG_TFM_PARTITION_META` undefined and silently skips the isolation-2 MMIO and isolation-3
metadata regions. Every upstream user compiles it into `tfm_spm`; keep it there.
