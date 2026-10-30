# Build Architecture — what builds what, and what links where

The CMake target graph of this port: two projects, one handoff, and an FSP module registry
added to upstream TF-M's target graph.

Every edge below was read out of a `target_link_libraries()` or `target_sources()` call and is
cited by file and line. Unqualified port line numbers are
`platform/ext/target/renesas/ra6m5/CMakeLists.txt` at TF-M `HEAD` after the D129 comment pass.
A comment edit anywhere above a block moves them, so check the construct, not just the number.
Upstream paths are relative to the `trusted-firmware-m` root.

`ra8m2` has the same targets, not the same layout. It adds `bl2` sources in three blocks
(`:843`, `:854`, `:858`) where ra6m5 uses two, and its line numbers differ throughout —
`tfm_spm` is `:648` there against `:517` here. The §3 table carries both columns; follow the
construct into `ra8m2/CMakeLists.txt` rather than the ra6m5 line.

> [DESIGN.md](DESIGN.md) says why the port is built this way — §1 (consume RASC, don't fork) and §1.1
> (the documented deviations). This file says what the graph is.

## 1. Two projects, not one

The secure and non-secure sides are separate CMake projects. The first installs an
`api_ns/` tree; the second is configured against that tree, not against TF-M's source.

- `CMAKE_INSTALL_PREFIX` defaults to `<build dir>/api_ns` — `config/config_base.cmake:17`.
- `api_ns/` carries `interface/{include,src,lib}`, `image_signing/` and
  `cmake/toolchain_ns_GNUARM.cmake`.
- The NS project needs both `CONFIG_SPE_PATH` and `TFM_TOOLCHAIN_FILE` pointing into it.

The `-S` source differs by what you are building. Regression (`reg_build_gcc.bat:150,174`)
configures the SPE from `tf-m-tests/tests_reg/spe` and the NS project from
`tf-m-tests/tests_reg`. Application (`app_build_ra8m2_gcc.bat:50,69`) configures the SPE
from the TF-M root and the NS project from
`platform/ext/target/renesas/<part>/ns_app`. Everything else below is identical; the diagram
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

- The three e2 projects are inputs only. They supply the generated FSP sources,
  `bsp_linker_info.h` (the partition addresses every layout derives from) and the OFS values.
- The slot layout comes from the secure project's `Debug/bsp_linker_info.h`, named above.
  The SPE project takes `FSP_NS_APP_DIR` but does not compile from it: it records the path
  into `api_ns` (`<part>_ns_config.cmake`) so the NS project builds against the same e2
  non-secure project and can cross-check it. Those sources are compiled only under
  `RA6M5_NS_IN_SPE_BUILD`, which is off by default.
- BL2 is not signed. It is the root of trust and is flashed raw, as `.hex` or `.srec`,
  **never the flat `.bin`** ([[D002]], [GETTING_STARTED.md](GETTING_STARTED.md) §6). Only `tfm_s` and `tfm_ns` go
  through `imgtool`.

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
- Two cycles are intentional: `tfm_spm` <-> `tfm_sprt`, and
  `platform_s` <-> `tfm_sprt` when the attest HAL is on. CMake resolves static-library cycles
  by repeating archives on the link line, so these build — but they are why link trouble here
  has tended to be archive ordering rather than a missing library.
- `PLATFORM_DEFAULT_ATTEST_HAL` is ON upstream (`config/config_base.cmake:116`) and
  OFF on both live parts (`ra6m5/config.cmake:199`, `ra8m2/config.cmake:225`) because the
  port supplies its own `attest_hal.c`. That single `OFF` is what makes §6 possible.

## 3. What the port adds to each upstream target

| Target | ra6m5 | ra8m2 | Sources added |
|---|---|---|---|
| `platform_s` | 387 | 537 | **Unconditional:** `target_cfg.c`, `tfm_hal_platform.c`, `tfm_peripherals_def.c`, `attest_hal.c`, `cmsis_drivers/Driver_Flash.c`, `sce_trng.c` (PSA external RNG over the SCE9 TRNG), `ra_sce_init.c`, `<part>_layout_checks.c` (static assertions only, no code). **Under `CONFIG_TFM_FLIH_API` OR `CONFIG_TFM_SLIH_API`:** `ext/common/tfm_hal_nvic.c` (the IRQ HAL, `:416`) and `tfm_timer0_irq.c` (the AGT0 fixture handler, `:425`) — the privileged half of the TIMER0 fixture; `plat_test.c` is the other half and must stay in `tfm_sprt`. **Separate block:** `Driver_USART.c` when RTT is off (`:682` / ra8m2 `:799`) |
| `tfm_sprt` | 453 | 595 | `plat_test.c`, behind `CONFIG_TFM_FLIH_API` OR `CONFIG_TFM_SLIH_API`. Scoped to the one file, and given `platform_s`'s resolved include list rather than a hand-written subset — `tfm_sprt` links into every partition, so the FSP tree must not reach the whole target |
| `tfm_spm` | 517 | 648 | `ext/common/tfm_hal_isolation_v8m.c` — the upstream file. **Do not move it back to `platform_s`**; see §6 |
| `tfm_s` | 607 | 724 | `startup_<part>.c` |
| `platform_bl2` | 704 | 821 | `target_cfg.c`, `tfm_hal_platform.c` (there for one symbol: `__STACK_SEAL`, which anchors `.msp_stack_seal_res`), `cmsis_drivers/Driver_Flash.c` — three files, unconditional. Plus RTT or USART stdout in a later block (`:747` / ra8m2 `:868`). Compiled with `RA6M5_BUILDING_BL2` and no `_RA_TZ_` macro — BL2 is a flat build. `bl2_boot_hal.c` is not here; see the `bl2` row |
| `bl2` | 728 | 843 | `startup_<part>.c`, `bl2_option_setting.c` — the OFS emitter, and the reason BL2 needs discrete per-word `MEMORY` regions in its linker script ([[D002]]). **The gating differs by part.** On ra6m5, `if(CRYPTO_HW_ACCELERATOR)` (`:735`) covers both `ra_sce_init.c` and `bl2_boot_hal.c`. On ra8m2, `bl2_boot_hal.c` is unconditional (`:854`) because it enables the SAU, without which BL2 cannot read the non-secure slots; only `ra_sce_init.c` is behind the accelerator there (`:858`). Either way BL2's SHA-256 runs on the engine, and BL2 brings it up itself in `boot_platform_post_init()` before MCUboot hashes the first slot |
| `tfm_ns` | 1065 | 1204 | Optional path only. `rtt/SEGGER_RTT.c`, `rtt/rtt_ns_init.c` under `RA6M5_STDOUT_RTT` — but the whole block sits inside `if(FSP_NS_APP_DIR AND RA6M5_NS_IN_SPE_BUILD)` (`:1021`), and that option is OFF by default (`:1016`). See the note below |

The default build has no `tfm_ns` target in the SPE project. `RA6M5_NS_IN_SPE_BUILD`
(ra8m2: `RA8M2_NS_IN_SPE_BUILD`) exists for single-configure boot bisection and has been off
by default. In the normal split build the NS image is built by the NS
project — §1 and §2 — and gets its RTT from `syscalls_ns.c`'s own `_write()` plus the
`ns_app`/`tests_reg` sources, not from this block. `rtt_stdout.c` is absent by design
either way: it would collide with that `_write()`.

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

- Adding a module takes three things, not two: a name in `FSP_MODULES_S` or `_BL2`, an
  `FSP_MODULE_DIRS_<name>` entry, and a `cmake/modules/fsp_<name>.cmake` file. See
  [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md).
- The two mistakes fail differently. A name with no `.cmake` file aborts the configure —
  `include()` is not `OPTIONAL`. A missing `DIRS` line takes the warning path: the
  directory stays unclaimed and the build tells you the driver is not in the image.
- Both roles build their own copy of a shared module, which is why the target name carries the
  role: `fsp_bsp_s` and `fsp_bsp_bl2` are different libraries.
- Every non-`bsp` module PUBLIC-links `fsp_bsp_<role>` — `fsp_flash.cmake:21`,
  `fsp_sce.cmake:51`, `fsp_agt.cmake:40`. A new module almost certainly needs the same line;
  [ADDING_FSP_MODULES.md](ADDING_FSP_MODULES.md) carries it in the template.
- `FSP_MODULES_NEVER_BUILT` (`:266`) is not an exclusion from the build. It is the
  allowlist for the audit, naming directories that are in the e2 project and are expected to
  be unclaimed.
  - `r_sce` is built, by the `sce` module: `FSP_MODULE_DIRS_sce = r_sce` (`:249`), and
    `fsp_sce.cmake` globs the tree. In the secure image the TRNG is always reachable; the
    SCE9 cipher `*_ALT` path is live whenever `CRYPTO_HW_ACCELERATOR` is ON, which is the
    default (`config.cmake:127`). BL2 declares the module only with the accelerator, for
    the SHA-256 image hash. Its entry in `NEVER_BUILT` is therefore not redundant: it is what
    keeps the audit quiet in the BL2-without-accelerator case, where no listed module claims
    the directory.
  - `rm_psa_crypto` and FSP's `ra/arm/mbedtls` are the real omissions, as FSP modules. The
    `*_ALT` sources that drive the engine are compiled by
    `platform/ext/accelerator/renesas/sce9` instead, and the crypto library comes from the
    `fsp_mbedtls.cmake` overlay below. FSP's crypto code is in the image; what
    is excluded is FSP's PSA/ITS configuration, which wires PSA ITS to littlefs and conflicts
    with `TFM_PARTITION_INTERNAL_TRUSTED_STORAGE` ([DESIGN.md](DESIGN.md) §6). The header of
    `cmake/modules/fsp_sce.cmake` is the authority on this split.
  - `rm_mcuboot_port` — its own `FLASH_AREA_*_ID` values and single-image assumptions conflict
    with TF-M's dual-image flash map ([DESIGN.md](DESIGN.md) §4, §5). Grafting it on is what failed on
    RA6M4.
- Beside the registry, `cmake/fsp_mbedtls.cmake` does something larger: it `FORCE`-sets
  `MBEDCRYPTO_PATH` to an overlay built from the secure project's `ra/arm/mbedtls`. Present for
  `ra6m5` and `ra8m2` only.

## 5. After the link

Each is an `add_custom_target(... ALL)`, not `add_custom_command(TARGET ... POST_BUILD)` — the
latter only attaches to a target created in the same directory, and `bl2_bin` is not.

| Step | Line | Does what |
|---|---|---|
| orphan-section check | 837 | Fails on any section the linker script did not place, against a short allowlist |
| `check_ofs.py` | 915 | Reads the program headers of the linked ELF and fails if a `PT_LOAD` coalesces the option-setting words. Toolchain-agnostic. This is the only place the mistake is visible — not the srec, not the map, and a plausible-looking linker script is no evidence ([[D002]], [[D094]]) |
| `--emit-safe-bin` | 958 | Re-emits the flat binary address-driven. `objcopy -O binary` flattens from the lowest address and zero-fills the gaps, which yields an image that can permanently lock the part |
| `imgtool` | — | Signs `tfm_s` and `tfm_ns` into their slots, using the layouts installed under `api_ns/image_signing/`. Slot overflow fails here, after a clean link |

## 6. Why the isolation HAL's target is load-bearing

`ext/common/tfm_hal_isolation_v8m.c` switches on six macros. Four arrive as compile
definitions, and those are the ones the target choice decides. The other two arrive by header,
so they are target-independent, which is why they were never part of the defect.

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

- `tfm_spm` reaches the two `psa_interface` macros indirectly and unconditionally: it
  PRIVATE-links `tfm_sprt`, which PUBLIC-links `psa_interface`.
- `platform_s` has no such route. Its own `tfm_sprt` edge exists only under
  `PLATFORM_DEFAULT_ATTEST_HAL`, which this port turns off (§2).
- All nine upstream users of the file — an519, an524, corstone300, corstone310, mps4,
  musca_b1, musca_s1, rse, alcor — add it to `tfm_spm`. All four RA ports added it to
  `platform_s`.
- Consequence: the file compiled with `TFM_ISOLATION_LEVEL` undefined, so every `#if` on it
  evaluated 0. `== 2` and `== 3` tests were false; `!= 3` tests were true. The MMIO region
  was never programmed at isolation 2, and the partition-metadata region was never covered
  at isolation 3. The App RoT data arm did fire, which [[D120]] records against an earlier
  "neither arm fires" reading.
- This is a target choice, not an upstream defect. Moving the source fixed the class rather
  than the two macros that had been noticed. [[D113]] through [[D126]]; the withdrawal
  of the upstream claim is item 15 of [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md).
