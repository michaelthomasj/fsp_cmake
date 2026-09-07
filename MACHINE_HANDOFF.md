# Machine Handoff — Renesas_work machine ⇄ original machine

**Why this file exists.** Work on the RA6 TF-M port is split across two machines:

| | Original machine | This machine ("Renesas_work") |
|---|---|---|
| Repo root | `C:/Users/Michael/Documents/GitHub` | `C:/Users/Michael/Renesas_work/repos` |
| In use | until ~2026-07-23; available again 2026-09-07 | **2026-08-10 → present** |
| Holds | unpushed post-07-23 work, unverified (see §2) | 34 commits (`trusted-firmware-m`) and 23 (`fsp_cmake`) past the 07-23 floor, pushed |

⚠ **§2 was rewritten on 2026-09-07 and now says the opposite of what it said on 2026-08-10.**
When this file was written, this machine had no RA6E1 work and the original machine held the only
copy. That is no longer true: the RA6E1 port was rebuilt here from scratch and is verified on
hardware. Read §2 before merging anything — following the original checklist would discard the
working port in favour of six-week-old bring-up.

---

## 1. What was done on this machine (2026-08-10)

### 1.1 Restored OFS to BL2, correctly this time
Commit `c78602fff` (2026-07-21) had deleted OFS emission entirely, concluding "option memory must
never appear in an image." **That was the wrong lesson.** The real cause of the two bricked
EK-RA6M4 boards was that the linker emitted the option words as bare addressed sections with no
`> REGION` assignment, so GNU ld coalesced them into one PT_LOAD spanning 460 bytes and zero-filled
the 368 bytes of FCU config in between — including the FSPR permanence word. FSP's own generated
linker avoids this by giving each option group its own MEMORY region.

Changed in `trusted-firmware-m` (all under `platform/ext/target/renesas/ra6m4/`):

| File | Change |
|---|---|
| `region_defs.h` | Added 13 `OPTION_SETTING_*_START/_LENGTH` macros (values from the RASC `memory_regions.ld`), with the gap arithmetic and the discrete-region rule documented |
| `ra6m4_bl2.ld` | Added 13 discrete `MEMORY` regions; the 13 `.option_setting_*` sections now each carry `> OPTION_SETTING_xxx` |
| `bl2_option_setting.c` | Restored byte-identical from `c78602fff^` (it was never the problem) |
| `CMakeLists.txt` | Re-added the source entry; rewrote both comment blocks to state the real invariant |

All three "never re-add this" warnings are gone. Full rationale is now **DESIGN.md §8.4**.

### 1.2 Verified on real artifacts
`build_ra6m4_boot` builds clean and produces all three signed images. Verification actually run:

- `readelf -l bl2.axf` → **three discrete 4-byte LOAD segments** at `0x0100A100` / `0x0100A200` /
  `0x0100A280`. No spanning segment. (Only three, not thirteen, because this RASC config defines
  only OFS0 / OFS1_SEC / OFS1_SEL; the other guards compile out.)
- OFS values **match the known-good image from commit `7b99ce397` byte-for-byte**:
  `ffffffff` / `fffdffff` / `f8f8ffff`.
- `tfm_s.axf` and `tfm_ns.axf` carry **no** option-setting sections or `0100a` segments.
- No regressions: `__Vectors` @ `0x0`, `Reset_Handler` @ `0x16b0`, `.ram_noinit` NOBITS
  `0x200004a0`+`0x70` ending exactly at `__bss_start__` `0x20000510`, `g_clock_freq` `0x200004a0`
  and `SystemCoreClock` `0x200004c8` both inside it, `Image$$ER_VENEER$$Base` = `0x4f400`.

**Update 2026-09-07.** J-Link is installed here now (§3), and the same discrete-region approach
is hardware-verified on RA6E1 — `ra6e1_bl2.ld` carries the identical 13 regions and its BL2 boots
and performs in-field upgrades. The **RA6M4** build itself still has not been flashed since this
fix, so its OFS words remain verified only statically, as described above.

### 1.3 Documentation
- **DESIGN.md §8 rewritten** into §8.1–§8.4. The code cites `DESIGN.md 8.1` and `DESIGN.md 8.4`;
  those sections previously did not exist in any committed copy.
- This file.
- `TFM_RA6M4_STATUS.md` brought up to date.

### 1.4 Bring-up scripts re-pathed
- `bringup/flash_ra6m4.jlink` — paths moved to `Renesas_work/repos`; added the machine-specific
  banner and the `readelf -l` pre-flight check.
- `bringup/bringup_ra6m4.sh` — RTT control-block addresses refreshed. **They moved** (the OFS
  restore and `.ram_noinit` changes shifted all three):

| Image | Old (stale) | Current |
|---|---|---|
| BL2 | `0x20002bd0` | **`0x20002c24`** |
| Secure | `0x2000baf8` | **`0x2000bb38`** |
| NS | `0x20020854` | **`0x200208a4`** |

---

## 2. ⚠ Reconciling with the original machine

**Rewritten 2026-09-07, when the original machine became available again.** The direction of this
reconciliation has inverted since the original version of this section, which assumed the original
machine held the only RA6E1 work. Everything it listed as unique to that machine has since been
redone here, and verified on hardware:

| Expected on the original machine | Status here |
|---|---|
| An independent OFS linker fix | **Superseded.** Fixed here with discrete `MEMORY` regions and verified with `readelf -l` (§1.1/§1.2). Two EK-RA6M4 boards were destroyed learning this; do not adopt an unverified alternative. |
| RA6E1 bring-up | **Superseded, by a long way.** A full RA6E1 TF-M port exists here: dual-image MCUboot solution, split SPE/NSPE build, 13 NS smoke tests and the `tf-m-tests` NS regression suite at 5/5 suites. See `RA6E1_SOLUTION.md`. |
| `DESIGN.md` §8.1 / §8.4 | **Written here** and since expanded. |

So the merge is no longer symmetric. **This machine's branches are the trunk.** Both are pushed, so
the original machine can simply fetch them.

### Checklist (on the original machine)
1. **Fetch, do not push.** `git fetch origin` and check out this machine's branches
   (`FSPRA-5483_FSP_TFM_Cmake_framework`, `ra6m4_gen_6_1_TFM_ns_update`). Leave the local post-07-23
   commits on their own branch; do not merge them into these.
2. **Do not merge the old OFS fix.** It is redundant, and the brick hazard makes a wrong merge
   expensive. Same for the old RA6E1 bring-up.
3. **Mine the old branch for one thing only: hardware observations.** FAWMON reads, what RFP
   actually reported, anything recorded during the July brick investigation. That is the only
   category the reconstruction here cannot regenerate, and it belongs in `DESIGN.md` §8.4.
4. **Re-path** `bringup/flash_ra6m4.jlink` if you build on the original machine (the banner at the
   top lists both roots), and **refresh the RTT addresses** from the rebuilt images — they move on
   almost every build.
5. Erase data flash (`0x08000000`, 8 KB) before the first run of a build carrying a different
   `PS_NUM_ASSETS`; PS has no migration path for its object table.

### If the old machine's work turns out to be gone
It no longer matters much. Everything in §1 is re-derivable and has been re-derived. The only
genuine loss would be the July hardware observations in item 3.

---

## 3. Environment on this machine

Nothing is on the inherited `PATH` except Git and Python — the compiler, CMake and Ninja all live
inside the e2 studio bundle. `bringup/../..` scripts assume they are on `PATH`.

| Tool | Version | Location |
|---|---|---|
| arm-none-eabi-gcc | 13.2.1 (13.2.rel1) | `C:\Renesas\RA\e2studio_v2026-04.2_fsp_v6.5.0\toolchains\gcc_arm\13.2.rel1\bin` |
| CMake | 3.27.6 | `...\eclipse\plugins\com.renesas.ide.exttools.cmake.win32.x86_64_3.27.6.v20231010-1103\cmake\bin` |
| Ninja | 1.11.1 | `...\eclipse\plugins\com.renesas.ide.exttools.ninja.win32.x86_64_1.11.1.v20231010-1103\n` |
| Git | 2.55.0 | `C:\Program Files\Git\cmd` |
| Python | 3.14.7 | `C:\Users\Michael\AppData\Local\Python\bin` — TF-M `tools/requirements.txt` installed |
| e2 studio / RASC | v2026-04.2, **FSP 6.5.0** | `C:\Renesas\RA\` |
| **SEGGER J-Link** | V9.66 + Ozone (installed since 2026-08-31) | `C:\Program Files\SEGGER\JLink_V966` — hardware bring-up works here |

⚠ **FSP version skew.** e2 studio here ships **FSP 6.5.0**; the port is built against the vendored
**FSP 6.1.0** snapshot. The TF-M build is unaffected (it uses the in-tree snapshot), but a project
regenerated in RASC `sc_v2026-04.2` on this machine will emit **6.5.0** sources — a different
baseline from everything else in `fsp_cmake`. Note which FSP any newly generated project came from.

### Build command that works here
```powershell
$E = "C:\Renesas\RA\e2studio_v2026-04.2_fsp_v6.5.0"
$env:ARM_TOOLCHAIN_PATH = "$E\toolchains\gcc_arm\13.2.rel1\bin"
$env:Path = "$env:ARM_TOOLCHAIN_PATH;" +
  "$E\eclipse\plugins\com.renesas.ide.exttools.cmake.win32.x86_64_3.27.6.v20231010-1103\cmake\bin;" +
  "$E\eclipse\plugins\com.renesas.ide.exttools.ninja.win32.x86_64_1.11.1.v20231010-1103\n;" +
  "C:\Users\Michael\AppData\Local\Python\bin;C:\Program Files\Git\cmd;" + $env:Path

cd C:\Users\Michael\Renesas_work\repos\trusted-firmware-m
cmake -S . -B build_ra6m4_boot -G Ninja `
  "-DTFM_PLATFORM=renesas/ra6m4" "-DTFM_TOOLCHAIN_FILE=toolchain_GNUARM.cmake" `
  "-DCMAKE_BUILD_TYPE=Debug" "-DBL2=ON" "-DMCUBOOT_LOG_LEVEL=INFO" `
  "-DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_INFO" "-DTFM_PARTITION_LOG_LEVEL=TFM_PARTITION_LOG_LEVEL_INFO" `
  "-DFSP_NS_APP_DIR=C:/Users/Michael/Renesas_work/repos/fsp_cmake/FSP_Project_ra6m4_ns_rtos"
cmake --build build_ra6m4_boot
```
**Quote every `-D` argument.** Unquoted, PowerShell splits `toolchain_GNUARM.cmake` into
`toolchain_GNUARM` + `.cmake` and the configure fails with "No CMAKE_C_COMPILER could be found".

---

## 4. Pre-flash checklist (every new build, both machines)

1. `arm-none-eabi-readelf -l bin/bl2.axf` — small discrete LOAD segments in `0x0100Axxx`,
   **never** one spanning `0x1CC`. **A clean srec does not prove this.**
2. `arm-none-eabi-objdump -s -j .option_setting_ofs0 -j .option_setting_ofs1_sec -j .option_setting_ofs1_sel bin/bl2.axf`
   — expect `ffffffff` / `fffdffff` / `f8f8ffff`.
3. Flash **`bl2.hex`**, never `bl2.bin` (~16.8 MB of padding — see DESIGN.md §8.4).
4. Refresh the RTT addresses in `bringup_ra6m4.sh` — they move on every rebuild.
5. Consider `-DRA6M4_BL2_HALT_AT_MAIN=ON` for a first flash on a new board: BL2 spins at `main()`
   so FAWMON/FSPR can be read back before MCUboot runs.
