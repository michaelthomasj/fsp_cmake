# Machine Handoff — Renesas_work machine ⇄ original machine

**Why this file exists.** Work on the RA6 TF-M port is split across two machines:

| | Original machine | This machine ("Renesas_work") |
|---|---|---|
| Repo root | `C:/Users/Michael/Documents/GitHub` | `C:/Users/Michael/Renesas_work/repos` |
| In use | until ~2026-07-23, and again from ~2026-08-31 | **2026-08-10 → ~2026-08-31** |
| Holds | unpushed post-07-23 work (see §2) | today's work (see §1) |

The two lines of work **overlap** — both fix the OFS linker bug. Going back is a *reconciliation*,
not a copy. Read §2 before merging anything.

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

**Not verified on hardware** — no J-Link installed on this machine (see §3).

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

The original machine is expected to contain **unpushed work done after 2026-07-23**, described from
memory as:

1. **An OFS linker fix** — same bug, independently fixed there. **This will conflict with §1.1.**
2. **RA6E1 bring-up** — got an RA6E1 booting, hit the same `FSP_ERR_FCLK`, resolved with the
   early-init flag. There is **zero** RA6E1 code in either repo as of 2026-08-10.
3. **DESIGN.md §8.1 / §8.4** — written there, never committed. §1.3 is an independent
   reconstruction; the two will differ in wording and possibly in substance.

**Verified 2026-08-10:** no ref on any remote in either repo is newer than
`trusted-firmware-m` `d7df90820` (2026-07-23) / `fsp_cmake` `661f49d` (2026-07-13). So none of the
above was ever pushed.

### Reconciliation checklist (do this before writing any code on the old machine)
1. **Don't fast-forward or force anything.** Fetch this machine's branch into a *separate* branch
   and diff.
2. **Compare the two OFS fixes.** Both should produce discrete per-group LOAD segments. The
   decisive test is not which code looks nicer — run on each build:
   `arm-none-eabi-readelf -l bin/bl2.axf` and compare the emitted OFS words against the known-good
   values in §1.2. Keep whichever is verified; discard the other rather than merging both.
3. **Keep the RA6E1 work from the old machine** — it does not exist here, so there is nothing to
   merge, only to rebase onto whichever OFS fix wins.
4. **DESIGN.md §8** — take the union. The old machine's version may contain hardware observations
   (FAWMON reads, what RFP actually reported) that this reconstruction cannot have.
5. **Re-path** `bringup/flash_ra6m4.jlink` back to `C:/Users/Michael/Documents/GitHub/...` (the
   banner at the top of that file lists both roots) and **refresh the RTT addresses** from the
   rebuilt images — they will have moved again.

### If the old machine's work turns out to be gone
Everything in §1 is self-contained and re-derivable. The only genuinely unrecoverable items are the
RA6E1 port and any hardware observations from the July brick investigation.

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
| **SEGGER J-Link** | **NOT INSTALLED** | required for `bringup_ra6m4.sh` and all RTT/flash work |

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
