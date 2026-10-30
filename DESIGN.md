# Renesas RA TF-M Port — Architecture & Design

How the port is built and why, and what to re-check on an FSP or TF-M update. Part status and
tool versions: [README.md](README.md). Per-part layouts and boundary values:
[RA6M5_SOLUTION.md](RA6M5_SOLUTION.md), [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md). Background to
individual decisions: [DECISIONS.md](DECISIONS.md).

## 1. Core principle — RASC is the source of config truth; consume, don't fork
- The user generates the base project(s) from RASC (Smart Configurator). BSP, clocks, pins,
  drivers, MPU, OFS, etc. are configured there and generated as code.
- The TF-M BL2 / secure / non-secure builds consume that generated code — they do not
  hand-fork it. Mechanism: `FSP_BL2_APP_DIR` / `FSP_S_APP_DIR` / `FSP_NS_APP_DIR` point the build at
  the RASC projects (with an embedded `fsp/` snapshot as fallback default).
- Prefer TF-M's own config hooks/macros over copying/forking TF-M files, and directory globs of
  the RASC tree (as RASC's own `GeneratedSrc.cmake` does) over hand-maintained file lists. This is
  what keeps "update FSP" and "update TF-M" cheap.
- Corollary: whenever a value/section could come from RASC config, source it from there
  (e.g. OFS values from `BSP_CFG_OPTION_SETTING_*`), even if the emitting shim is small.

### 1.1 Documented deviations from the principle

Documented exceptions. Anything not listed here that diverges from RASC is a defect, not a choice.

#### Image version
**Do not set `MCUBOOT_IMAGE_VERSION`.** FSP's `rm_mcuboot_port_sign.py` reads that environment
variable; this port does not use the script, so the variable is ignored silently. Set
`MCUBOOT_IMAGE_VERSION_S` (default `${TFM_VERSION}`) and `MCUBOOT_IMAGE_VERSION_NS` (default
`0.0.0`) in `config.cmake` or on the command line. TF-M versions the two images independently,
and the attestation token reports them as separate components.

#### `BSP_TZ_CFG_MSAR=0` on RA8M2
A workaround for an e2 generator defect; remove it once e2 emits `BSP_CFG_CLOCKS_SECURE (1)`.
Mechanism and removal test: [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md)
§"MRAM's MRCPFB must stay Secure".

## 2. Repositories
- `ra_fsp_cmake_tfm`: the e2 solutions and generated FSP projects, build scripts and these
  documents.
- `trusted-firmware-m`: the port, under `platform/ext/target/renesas/<part>/`, on TF-M v2.2.0.

Tool and FSP versions: [README.md](README.md).

## 3. Memory map — authoritative source
`flash_layout.h` and `region_defs.h` are authoritative for the build and derive every address
from the solution's `bsp_linker_info.h`. Per-part figures: the two SOLUTION documents.

## 4. Flash driver geometry
Per-part, and the one place where getting a constant wrong fails only on hardware.

| | RA6M5 | RA8M2 |
|---|---|---|
| Memory | HP code flash | MRAM |
| Block size under the slots | 32 KB (region 1, `0x10000+`; region 0 is 8 KB) | no physical erase block - MRAM's write unit is 32 B and its erase is simulated. 32 KB is FSP's `RM_MCUBOOT_MRAM_BLOCK_SIZE` layout choice, which the port mirrors |
| `FLASH_AREA_IMAGE_SECTOR_SIZE` | `0x8000` | `0x8000` |

Both parts restate `FLASH_AREA_IMAGE_SECTOR_SIZE` in `flash_layout.h`, and have to: FSP's
generated `mcuboot_config.h` defines the same macro, so it cannot be included alongside. **No
build step compares the two** - a mismatch passes everything and fails on hardware as
`BOOT_EFLASH`, so compare them by hand after a regenerate
([FSP_UPREV_CHECKLIST.md](FSP_UPREV_CHECKLIST.md) §2).

BL2 uses TF-M's MCUboot flash map and backend (`DEFAULT_MCUBOOT_FLASH_MAP` ON), with FSP's
`R_FLASH_HP` / `R_MRAM` behind `Driver_FLASH0` / `Driver_FLASH1`, as ST does for STM32Cube. The
image layout still comes from the solution: `FLASH_AREA_*_OFFSET/SIZE` derive from
`BSP_PARTITION_*`. RA8M2's BL2 SAU programming is in `bl2_boot_hal.c` (§7).

## 5. MCUboot / BL2
- Bootutil: TF-M downloads upstream MCUboot (`MCUBOOT_VERSION 6071ceb`), not the copy RASC ships,
  and no FSP MCUboot source is built (no `FSP_MODULES_S` / `FSP_MODULES_BL2` entry declares
  `rm_mcuboot_port`). Do not point `MCUBOOT_PATH` at the RASC tree: RASC strips TF-M's build glue
  and adds hooks TF-M's copy does not call.
- Signing: TF-M's default flow, `${MCUBOOT_PATH}/scripts/imgtool.py` from the MCUboot it
  downloads. FSP's `rm_mcuboot_port_sign.py` wrapper is not used; it is for standalone RASC
  MCUboot projects.
- NV rollback counters: TF-M's `bl2/src/security_cnt.c` (not provided by `rm_mcuboot_port`).

## 6. Crypto
- Hardware crypto is in place on both parts. `CRYPTO_HW_ACCELERATOR` is ON
  (`ra6m5/config.cmake:127`, `ra8m2/config.cmake:150`), with `CRYPTO_HW_ACCELERATOR_TYPE`
  `renesas/sce9` on RA6M5 and `renesas/rsip_e50d` on RA8M2. BL2 hashes on the engine too.
- Crypto is built from FSP's Mbed TLS overlay (`fsp_mbedtls.cmake` sets `MBEDCRYPTO_PATH`), with
  the ciphers reached through FSP's `*_ALT` macros. CCM stays in software
  ([KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) §2). The TRNG is the entropy source through
  `MBEDTLS_PSA_CRYPTO_EXTERNAL_RNG` (`sce_trng.c`); `MBEDTLS_ENTROPY_HARDWARE_ALT` stays off so
  the engine is not reached by two paths.
- `-DCRYPTO_HW_ACCELERATOR=OFF` selects TF-M's own mbedcrypto.

## 7. TrustZone: SAU/IDAU, veneers, NSC
Both parts attribute memory through the IDAU, from values burned at provisioning; the port
programs neither the boundaries nor, on RA6M5, the SAU. RA8M2 differs:

| | RA6M5 | RA8M2 |
|---|---|---|
| `__SAUREGION_PRESENT` | `0` | `1` |
| `BSP_FEATURE_TZ_NS_OFFSET` | `0x00000000` | `0x10000000` |
| Flash aliases | one | secure `0x02000000`, non-secure `0x12000000` |

With the SAU disabled, Armv8-M treats every address as Secure unless `SAU_CTRL.ALLNS` is 1; FSP's
`R_BSP_SecurityInit` sets ALLNS, which is why RA6M5 works with no SAU regions and why FSP's
startup must not be replaced. RA8M2 must also mark its non-secure alias NS in the SAU before
anything touches it, so BL2 calls `bl2_sau_init()` first in `boot_platform_post_init()`
(`bl2_boot_hal.c`).

Attribution itself is entirely what is burned at provisioning — see §7.1.
- Veneers/NSC: pinned at a fixed address, taken from the generated layout, using TF-M's
  own generated linker via the `region_defs.h` macros `TFM_LINKER_VENEERS_LOCATION_END` and
  `TFM_LINKER_VENEERS_START = CMSE_VENEER_REGION_START` (both `#ifndef`-overridable). No custom
  secure linker — the nordic/laird upstream pattern. Fixed rather than end-of-code so the NSC
  window is stable across firmware updates, which matters because RA TZ boundaries are set once
  at provisioning.
- Boundary values: [RA6M5_SOLUTION.md](RA6M5_SOLUTION.md) and
  [RA8M2_SOLUTION.md](RA8M2_SOLUTION.md) only. Programming them erases the part
  ([GETTING_STARTED.md](GETTING_STARTED.md) §6).

### 7.1 Boundary provisioning — the boundaries are NEVER set by our software
FSP compiles out its boundary-programming code on both parts (`BSP_FEATURE_TZ_HAS_DLM = 1`), and
the SAU only refines the IDAU. So the boundaries burned with the Renesas Device Partition
Manager are the only thing that makes the non-secure regions non-secure. An unprogrammed part faults at
the first S→NS `BLXNS` with SecureFault `INVEP` (`SCB->SFSR` bit 0).

Register granularities differ, and two are coarse. A layout is only programmable if the sums land
on them:

| Boundary | Register | Granularity |
|---|---|---|
| Code flash S → NSC | `CFSAMONB.CFS1` | 1 KB |
| Code flash NSC → NS | `CFSAMONA.CFS2` | 32 KB |
| SRAM S → NSC | `SSAMONB.SS1` | 1 KB |
| SRAM NSC → NS | `SSAMONA.SS2` | 8 KB |
| Data flash S → NS | `DFSAMON.DFS` | 1 KB |

So Code Secure + Code NSC must be a multiple of 32 KB, and SRAM Secure + SRAM NSC a multiple of
8 KB. Check this when choosing partition sizes in RASC — a layout that fails it cannot be programmed
at all and must be repartitioned, not worked around.

Program the values in KB with the Renesas Device Partition Manager (e2 studio → Run → Renesas
Debug Tools), following [GETTING_STARTED.md](GETTING_STARTED.md) §6, and verify by reading
`CFSAMONA`/`CFSAMONB` back.

### 7.2 ⚠ Disable the debugger's automatic TZ-boundary programming
e2 studio debug configurations carry:

```xml
<booleanAttribute key="com.renesas.hardwaredebug.arm.jlink.setTZBoundaries" value="false"/>
```

The e2 debugger derives TrustZone boundaries from the launched project's symbols. Launched
against BL2, which has no TrustZone knowledge, it marks everything secure, and the next S→NS jump
faults with `INVEP`. It defaults to enabled; keep it `false` in every launch
([GETTING_STARTED.md](GETTING_STARTED.md) §6 has the check).

## 8. The BL2 image: linker, runtime state, and option memory

BL2 is the one image where TF-M's startup model and FSP's expectations collide.

### 8.1 `.ram_noinit` and the FCLK / `SystemCoreClock` hazard
TF-M's `Reset_Handler` calls `SystemInit()` before the C runtime zeroes `.bss`, so clock state
that FSP leaves there (`SystemCoreClock`) is wiped and `R_FLASH_HP_Open` fails with
`FSP_ERR_FCLK`. FSP's remedy, Early BSP Initialization (`BSP_CFG_EARLY_INIT = 1`), places that
state in `.ram_noinit`. It is required in the secure and bootloader projects, which use TF-M's
startup, and a `#error` enforces it ([E2_PROJECT_REQUIREMENTS.md](E2_PROJECT_REQUIREMENTS.md)
§5); the non-secure image uses FSP's startup and does not need it. `<part>_bl2.ld` declares
`.ram_noinit` NOLOAD before `.bss` and outside the zero table; the secure image places it through
`S_DATA_EXTRA_NOINIT_SECTION_NAME` and also calls `SystemCoreClockUpdate()` once in
`tfm_hal_platform_init()`. Verify: `.ram_noinit` is NOBITS and ends where `__bss_start__` begins.

### 8.2 The forked linker scripts
Each part forks three: `<part>_bl2.ld` (GNU), `<part>_bl2.icf` and `<part>_fsp_sections.icf`
(IAR) — six files across RA6M5 and RA8M2. `<part>_bl2.ld` is a copy of TF-M's
`tfm_common_bl2.ld` plus §8.1 and §8.4; it is forked because GNU ld `INSERT` cannot augment a
`-T` main script from a second `-T` fragment. Keep them in sync with TF-M on version bumps. The
secure side uses TF-M's generated linker with the `region_defs.h` hooks (plus
`<part>_fsp_sections.icf` under IAR); only the non-secure side uses FSP's generated script.

### 8.3 BL2 lives at the base of flash
`BL2_CODE_START` derives from `BSP_PARTITION_FLASH_BL_CPU0_S_START`, not from `S_ROM_ALIAS_BASE`
(the secure image base). Verify that `__Vectors` sits at the flash base in `bl2.axf`: `0x0` on
RA6M5, `0x02000000` on RA8M2.

### 8.4 OFS (option-setting memory) — BL2 only, DISCRETE regions

OFS is emitted into the BL2 image only. Reasons: (a) the secure/NS
images are MCUboot-signed and imgtool needs a contiguous payload — OFS is non-contiguous with
code flash; (b) two images programming OFS would collide. FSP's `bsp_linker.c` gates OFS on
`#ifndef BSP_BOOTLOADED_APPLICATION` (bootloader only) for the same reason.

`bl2_option_setting.c` emits the option words from the RASC values (`BSP_CFG_OPTION_SETTING_*`)
and is linked straight into `bl2`, because nothing references it.

⚠ The critical decision is one `MEMORY` region per option group. The option-setting map is
sparse: on RA6M5, thirteen groups hold 112 bytes across a 464-byte span from `0x0100A100`;
RA8M2's option memory is in five windows. **A coalesced segment writes every byte in its span**,
including defined registers (two of them one-time) and reserved bytes the hardware manual says
must never be written.

- Correct (what FSP's generated `fsp_gen.ld` does, and what the port now does): declare one
  discrete `MEMORY` region per group — thirteen in `ra6m5_bl2.ld`, six in `ra8m2_bl2.ld` —
  each sized to its group, and assign every section with `> OPTION_SETTING_xxx`. ld
  then emits one PT_LOAD per group and physically cannot fill between them.
- Fatal, and what cost two boards: bare addressed sections with no `> REGION`
  — `.option_setting_ofs0 0x0100A100 : { ... }`. ld coalesces them all into one PT_LOAD
  spanning every group the image emits, and zero-fills the gaps. A debugger loading
  the ELF writes that whole span across config memory that should have been left alone → **the
  part is bricked**. This destroyed two EK-RA6M4 boards, and no recovery is known.

  The failing image is preserved as `bringup/bricking_evidence/bl2_BRICKED.elf.UNSAFE`; its
  analysis is in that directory's README.

**The zero fill is invisible in the srec**: it lives in the program header, not in a section. The
only valid check is:

```
arm-none-eabi-readelf -l bin/bl2.axf
```
Expect small separate LOAD segments, never one spanning the whole map. On RA6M5 that is
`FileSiz` `0x4` for the word groups and `0x10` for BPS/PBPS, in `0x0100Axxx`; on RA8M2, `0x4`
only, in the five windows below. Confirm the values match a known-good image
before flashing.

The build enforces this rather than a reminder to run it. `check_ofs.py` in the TF-M
platform directory runs after every `bl2` and `tfm_s` link and fails the build if any `PT_LOAD`
overlapping the part's option windows exceeds the per-part word limit. It is a hard error with
no opt-out switch — the failure it guards is silent, instant and unrecoverable, so a warning
that scrolls past would be worth nothing. `tfm_s` is checked too and must report CLEAN.

The windows and the limit are per part. A guard pointed at the wrong window reports a false
CLEAN, so check the table below when adding a part.

| | Windows | Limit | Where |
|---|---|---|---|
| RA6M5 | one: `0x0100A100`–`0x0100A2CF` | `--max-word 0x10`, its widest group | `ra6m5_add_ofs_check()`, passing `--ra6-default` |
| RA6E1 | the same window | `--max-word 0xC`, its widest group | `ra6e1_add_ofs_check()` |
| RA8M2 | five: `0x02C9F040`–`0x02C9F280`, `0x12C9F4C0`–`0x12C9F680`, `0x02E07600`–`0x02E07698`, `0x02E17700`–`0x02E17924`, `0x12E17780`–`0x12E17800` | `--max-word 4` | `ra8m2_add_ofs_check()`, passing five `--region` windows |

RA8M2's limit is `4` because `bl2_option_setting.c` places only 4-byte words there —
deliberately tighter than the `0x80` a BPS word would need, to be raised only if BPS/PBPS
are ever placed.
BL2 also passes `--require-segments`, so an empty result fails rather than passing.

> The limit is the part's widest defined group, and the two RA6 parts differ: `0x10` on RA6M5
> for `BPS`, `PBPS` and their mirrors, `0xC` on RA6E1 for the same groups. **Too small is not
> safe either** — a legitimately placed group then reads as spanning and fails a correct
> image.

The guard rejects the preserved bricked image
(`bringup/bricking_evidence/bl2_BRICKED.elf.UNSAFE`); keep it as the regression fixture.

One shared guard, `platform/ext/target/renesas/common/check_ofs.py`, serves every part, with the
windows passed on the command line.

A plain `objcopy -O binary` pads `bl2.bin` to about 16.8 MB and zero-fills the option memory: the
same brick, from an ELF that passes every check. Each port re-emits `bl2.bin` without the option
words (`check_ofs.py --emit-safe-bin`, by address, because IAR renames the sections) and verifies
it with `--check-flat-bin`. That runs only in a full build: building the `bl2_bin` target alone
still writes the coalesced image. The flashing rule is in [GETTING_STARTED.md](GETTING_STARTED.md) §6.

## 9. Console / logging — SEGGER RTT (switchable)
`<PART>_STDOUT_RTT` (default ON) routes TF-M and MCUboot stdout to SEGGER RTT; each image has its
own control block. OFF selects the SCI UART driver, which does not build with the shipped
projects ([CONFIGURATION.md](CONFIGURATION.md) §9). RTT use:
[GETTING_STARTED.md](GETTING_STARTED.md) §6.

## 10. Non-secure app
The non-secure image is the port's split NSPE (`ns_app`) or a `tf-m-tests` suite, built against
the non-secure e2 project as `FSP_NS_APP_DIR`. Neither uses an RTOS.

## 11. Toolchains
GNU Arm and IAR both build all three images on both parts (versions: [README.md](README.md);
results: [TEST_RESULTS.md](TEST_RESULTS.md)). Arm Compiler (armclang) is not supported.

## 12. Bring-up scripts
`bringup/` holds the RA6M4/RA6E1-era J-Link flash and RTT scripts and the preserved bricking
evidence, each with its own README. The supported parts are flashed through the e2 launch
configurations ([GETTING_STARTED.md](GETTING_STARTED.md) §6).

## 13. Production hardening

[README.md](README.md) §"Security status" lists what the shipped configuration does not do. This
section says how to address each item. The numbering matches that list.

### 13.1 Signing keys and provisioning

Two independent things have to change, and changing one without the other leaves the image
trusting sample keys.

| Step | What to do |
|---|---|
| Key material | Generate your own EC-P256 key pair. `MCUBOOT_SIGNATURE_TYPE` is `EC-P256` in every part's `config.cmake`. Changing it changes the signature size, so re-check the slot fit ([CONFIGURATION.md](CONFIGURATION.md) §6) |
| Signing | Point `MCUBOOT_KEY_S` and `MCUBOOT_KEY_NS` at your private keys. This changes what signs the image, and nothing else |
| Verification | BL2 trusts only the key arrays compiled into `bl2/ext/mcuboot/keys.c`. If they still hold the sample keys, images you sign with your own keys are rejected, and sample-signed images still boot. See below |
| Provisioning | Set `TFM_DUMMY_PROVISIONING=OFF` and supply real HUK and IAK values through a flow of your own. With it `ON`, every device shares one dummy identity |

**`MCUBOOT_GENERATE_SIGNING_KEYPAIR=ON` does not do the verification step**: it generates and
signs with new keys but leaves `keys.c` alone. `check_config.cmake` rejects it together with
`TFM_DUMMY_PROVISIONING`.

Two routes to the verification step, and the second is the one to prefer:

**Regenerate the array.** `imgtool` comes from the MCUboot checkout the build fetches, so run it
from a configured build tree:

```bat
python <build>\lib\ext\mcuboot-src\scripts\imgtool.py getpub ^
       -k my_root_s.pem --encoding lang-c -o ecdsa_pub_key_s.c
```

Paste the secure key's array over `ecdsa_pub_key[]` and the non-secure key's over
`ecdsa_pub_key_1[]` in `bl2/ext/mcuboot/keys.c` (run `getpub` once per key). `keys.c` is common
TF-M code: record the edit in [UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md).

**Or keep the arrays out of common code.** `keys.c` is compiled only when
`PLATFORM_DEFAULT_ROTPK` is `ON`. Set it `OFF` and supply the key arrays from a platform file
instead, which leaves `bl2/ext/mcuboot/` untouched and survives a TF-M uprev without a rebase.
`MCUBOOT_HW_KEY=ON` with provisioned ROTPK hashes is the same idea taken further: the hash comes
from the device rather than from the image.

**Verify it the other way round.** Sign an image with the **TF-M sample key** and confirm BL2
rejects it. Signing with a different key and watching BL2 refuse proves nothing: an unmodified
build refuses that too, because a stale `keys.c` rejects *your* images rather than accepting
everything. The sample-key test is the one that fails if the verification step was skipped.

### 13.2 Anti-rollback

`MCUBOOT_SECURITY_COUNTER_S` and `_NS` are left at the upstream default of `1`, so every release
is interchangeable with every other. Assign a counter value per release, increasing it whenever
you fix something you do not want downgraded past, and test that BL2 refuses an image carrying a
lower value.

The counters are held in emulated OTP on both parts, which means they are only as immutable as
the surrounding flash protection. Treat real anti-rollback as requiring both the counter policy
and the lifecycle work in §13.4.

### 13.3 Peripheral security attribution

RASC generates `BSP_CFG_CLOCKS_SECURE (0)`, which leaves the clock, wait-state and low-power
registers writable from the non-secure world. Setting Clocks to Secure in the Security tab does
not change the generated value; §1.1 records why.

Override the individual security attribution registers through `FSP_COMPILE_DEFS` for the
registers you need secure, and confirm on hardware that a non-secure write faults. **Do not
force `BSP_CFG_CLOCKS_SECURE=1` as a shortcut.** The generated BSP still reads `0`, so the two
disagree, and on RA8 parts the port's `BSP_TZ_CFG_MSAR=0` workaround depends on the generated
value (§1.1).

### 13.4 Secure debug and the device lifecycle

The firmware never reads the DLM state, and the lifecycle value in an attestation token comes
from emulated OTP rather than from the device. Two consequences: a debugger can attach to a
shipped device, and an attestation token's lifecycle claim does not describe the part it came
from.

Both belong to provisioning: decide the DLM transition, implement debug authentication, and make
the attested lifecycle read the real state.

### 13.5 The multi-part crypto engine lock

While a multi-part AES, GCM or CMAC operation is open it holds the SCE9 or RSIP engine, and
**`psa_generate_random` returns `PSA_ERROR_HARDWARE_FAILURE`** for every caller until that
operation completes or is aborted. That error code is the symptom to look for; nothing else in
the port returns it on a healthy part. This comes from reading the driver, not from an observed
failure, and no suite this port runs exercises the pattern.

If your application interleaves random generation with long multi-part operations, test for it
directly. Finishing or aborting each multi-part operation promptly avoids it.

### 13.6 Release build settings

For a release build use the option list in [CONFIGURATION.md](CONFIGURATION.md) §9, then
re-measure against the region as §6 there describes.

### 13.7 Re-test what you ship

Re-run `tf-m-tests` against your own build and keys before shipping.
[TEST_RESULTS.md](TEST_RESULTS.md) lists what has and has not run.

### 13.8 TF-M base version

The base is TF-M v2.2.0, which does not carry the TFMV-9 (CVE-2025-53022) fix. The shipped
configuration is unaffected because Firmware Update is off; before enabling it, move to v2.2.2 as
[UPSTREAM_CHANGES.md](UPSTREAM_CHANGES.md) §"Moving to TF-M v2.2.2" describes.
