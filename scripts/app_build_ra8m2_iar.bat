@echo off
rem  RA8M2 application chain (BL2 + secure + the port's NS app), IAR.
rem
rem    app_build_ra8m2_iar.bat [spe-build-dir] [ns-build-dir]
rem    app_build_ra8m2_iar.bat C:\b\m2app C:\b\m2appns
rem
rem  Debug / isolation 1 / SFN backend / SPM trace on - the application configuration. The
rem  PSA Arch builds are a different one (profile_large, isolation 3, IPC).
rem
rem  The GCC counterpart is app_build_ra8m2_gcc.bat against the ra8m2_gcc_* project set. Keep
rem  the pairing: an FSP project set is generated for one toolchain and the TF-M build must
rem  use the matching one. Crossing them mostly works (ra_gen/ and ra_cfg/ are toolchain-
rem  neutral and TF-M supplies its own linker script) but it is not the intended pairing.
rem
rem  The two sets must also agree on the device partitioning in solution.xml - they describe
rem  the SAME part and feed ONE RDPM entry. They are not in sync right now: the IAR set still
rem  has FSP's default RAM split (RAM_CPU0_C = 0x80 @ 0xE9F80) where the GCC set has the fixed
rem  1 KB NSC (0x400 @ 0xE9C00). See DECISIONS D057.
rem
rem  IAR needs iccarm on PATH (toolchain_IARARM.cmake names it without a path) and the ASM
rem  architecture id CMake 4.1 cannot detect - it fails on the SECOND configure pass, after
rem  the first has succeeded. DECISIONS D046.
rem
rem  CMAKE_BUILD_TYPE=Debug is NOT optional here. Leave it out and TFM_SPM_LOG_LEVEL defaults
rem  to SILENCE while the platform sets TFM_SPM_DEBUG_TRACE=ON, and configure stops with
rem  "INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND TFM_SPM_LOG_LEVEL = ..._SILENCE".
rem
rem  Build directories must be SHORT. Under a deep path the Mbed TLS overlay clone fails with
rem  "Filename too long" on 3rdparty/everest/..., which is why the defaults are under C:\b.

if "%IAR_BIN%"==""   set IAR_BIN=C:\iar\ewarm-10.10.2\arm\bin
if "%TFM_SRC%"==""   set TFM_SRC=C:\Users\Michael\Documents\GitHub\trusted-firmware-m
if "%FSP_CMAKE%"=="" set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set SPE=%1
set NS=%2
if "%SPE%"=="" set SPE=C:\b\m2app
if "%NS%"==""  set NS=C:\b\m2appns

set PATH=%IAR_BIN%;%PATH%
set TFM_SRC_FWD=%TFM_SRC:\=/%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_SRC% -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_C_COMPILER=%IAR_BIN:\=/%/iccarm.exe ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DTFM_PLATFORM=renesas/ra8m2 ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC_FWD%/toolchain_IARARM.cmake ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra8m2_iar_CPU0_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra8m2_iar_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra8m2_iar_CPU0_nonsecure ^
    -DTFM_ISOLATION_LEVEL=1 ^
    -DCONFIG_TFM_SPM_BACKEND=SFN
  if errorlevel 1 exit /b 1
)
rem  'install' produces api_ns/, which the NS build below consumes. It also runs the OFS
rem  brick guard on bl2 and tfm_s - read its output, do not just check the exit code.
cmake --build %SPE% -- install
if errorlevel 1 exit /b 1

if not exist "%NS%\CMakeCache.txt" (
  cmake -S %TFM_SRC%\platform\ext\target\renesas\ra8m2\ns_app -B %NS% -GNinja ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_IARARM.cmake
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
