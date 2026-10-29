@echo off
rem  RA8M2 application chain (BL2 + secure + the port's NS app), GNUARM.
rem
rem    app_build_ra8m2_gcc.bat [spe-build-dir] [ns-build-dir]
rem    app_build_ra8m2_gcc.bat C:\b\m2g C:\b\m2gns
rem
rem  Isolation 1 / SFN backend - the application configuration. The PSA Arch builds are a
rem  different one (profile_large, isolation 3, IPC).
rem
rem  CMAKE_BUILD_TYPE=MinSizeRel is NOT optional on GNUARM. Debug does not fit: tfm_s comes
rem  out around 414 KB against a 293 KB secure region. IAR Debug does fit (293 KB), which is
rem  why app_build_ra8m2_iar.bat uses Debug and this one does not. DECISIONS D056.
rem
rem  MinSizeRel DOES conflict with TFM_SPM_DEBUG_TRACE, and this comment used to claim it did
rem  not. config/build_type/minsizerel.cmake:9 sets TFM_SPM_LOG_LEVEL to _SILENCE, the platform
rem  config then sets TFM_SPM_DEBUG_TRACE ON (ra8m2/config.cmake:190), and check_config.cmake:119
rem  rejects the pair:
rem      INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND TFM_SPM_LOG_LEVEL = TFM_SPM_LOG_LEVEL_SILENCE
rem  Verified 2026-10-22 by running this script on a clean tree: it stopped at configure.
rem  -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG is therefore passed below, as reg_build_gcc.bat
rem  has always done. Use -DTFM_SPM_DEBUG_TRACE=OFF instead if you want the smaller image.
rem
rem  Build directories must be SHORT. Under a deep path the Mbed TLS overlay clone fails with
rem  "Filename too long" on 3rdparty/everest/..., which is why the defaults are under C:\b.
rem
rem  Quote %GCC_BIN% in every test. The default path contains "(x86)" and an unquoted
rem  "if not exist %GCC_BIN%\..." closes the block at the first paren - the body is then
rem  skipped and the script exits 0 having done nothing. That cost a debugging session once.

if "%GCC_BIN%"==""   set GCC_BIN=C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\13.2 Rel1\bin
rem  Repository roots. This repository locates itself, so its directory may be named
rem  anything; the other three default to siblings of it. Set any of these in the
rem  environment to use a different layout. scripts/README.md lists every variable.
for %%I in ("%~dp0..")    do set "REPO_ROOT=%%~fI"
for %%I in ("%~dp0..\..") do set "GH_ROOT=%%~fI"
set "GH_ROOT_FWD=%GH_ROOT:\=/%"
if "%TFM_SRC%"==""   set TFM_SRC=%GH_ROOT%\trusted-firmware-m
if "%FSP_CMAKE%"=="" set FSP_CMAKE=%REPO_ROOT:\=/%

set SPE=%1
set NS=%2
if "%SPE%"=="" set SPE=C:\b\m2g
if "%NS%"==""  set NS=C:\b\m2gns

set PATH=%GCC_BIN%;%PATH%
set TFM_SRC_FWD=%TFM_SRC:\=/%
set GCC_BIN_FWD=%GCC_BIN:\=/%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_SRC% -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=MinSizeRel ^
    -DCMAKE_C_COMPILER="%GCC_BIN_FWD%/arm-none-eabi-gcc.exe" ^
    -DTFM_PLATFORM=renesas/ra8m2 ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC_FWD%/toolchain_GNUARM.cmake ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra8m2_gcc_CPU0_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra8m2_gcc_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra8m2_gcc_CPU0_nonsecure ^
    -DTFM_ISOLATION_LEVEL=1 ^
    -DCONFIG_TFM_SPM_BACKEND=SFN ^
    -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG
  if errorlevel 1 exit /b 1
)
rem  'install' produces api_ns/, which the NS build below consumes. It also runs the OFS
rem  brick guard on bl2 and tfm_s - read its output, do not just check the exit code.
cmake --build %SPE% -- install
if errorlevel 1 exit /b 1

if not exist "%NS%\CMakeCache.txt" (
  cmake -S %TFM_SRC%\platform\ext\target\renesas\ra8m2\ns_app -B %NS% -GNinja ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_GNUARM.cmake
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
