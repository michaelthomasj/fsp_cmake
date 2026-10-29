@echo off
rem  Regression suites (tf-m-tests tests_reg), IAR. RA6M5 by default, RA8M2 with the third
rem  argument.
rem
rem    reg_build_iar.bat <spe-build-dir> <ns-build-dir> [part] [irq] [level] [backend]
rem    reg_build_iar.bat C:\b\m2iflih C:\b\m2iflihns ra8m2 flih
rem    reg_build_iar.bat C:\b\m2islih C:\b\m2islihns ra8m2 slih
rem    reg_build_iar.bat C:\b\m5il3   C:\b\m5il3ns   ra6m5 flih 3 IPC
rem
rem  ISOLATION LEVEL AND BACKEND are the last two arguments, defaulting to the shipping
rem  configuration (1 / SFN). See reg_build_gcc.bat's header for why they exist, what region
rem  count to expect, and why RA8M2 will not fit above isolation 1.
rem
rem  The GCC counterpart is the configuration recorded in C:\b\m2gflih - this script states it
rem  explicitly so a rebuilt tree matches, which is the lesson of DECISIONS D084.
rem
rem  IRQ ARGUMENT. The FLIH and SLIH suites are mutually exclusive in tf-m-tests: enabling both
rem  fails configure. 'flih' (the default) sets TEST_NS_FLIH_IRQ, 'slih' sets TEST_NS_SLIH_IRQ,
rem  'none' sets neither. They need a secure timer, which on RA is the r_agt module WITH a real
rem  Interrupt Priority - Disabled emits no vector entry at all. DECISIONS D061, D101.
rem
rem  MinSizeRel IS NOT OPTIONAL on RA8M2. Debug does not fit: ~414 KB against a 293 KB secure
rem  slot. DECISIONS D059.
rem
rem  LOGGING. Unlike the PSA Arch builds, the regression build CANNOT afford the secure-side
rem  logging options - the secure slot has 960 B spare on RA8M2 against 3,785 B for
rem  TFM_PARTITION_LOG_LEVEL alone. TFM_SPM_LOG_LEVEL is set because TFM_SPM_DEBUG_TRACE is ON
rem  in the platform config and leaving the level at its SILENCE default stops configure with
rem  "INVALID CONFIG: TFM_SPM_DEBUG_TRACE AND TFM_SPM_LOG_LEVEL = ..._SILENCE".
rem
rem  IAR needs three things GCC does not (DECISIONS D046): iccarm on PATH, the ASM architecture
rem  id CMake 4.1 cannot detect, and the NS build pointed at toolchain_ns_IARARM.cmake - without
rem  the last it silently uses GNUARM and fails looking for script/fsp.ld.
rem
rem  Build directories must be SHORT, under C:\b - a deep path makes the Mbed TLS overlay clone
rem  fail with "Filename too long" on 3rdparty/everest/...

if "%IAR_BIN%"==""    set IAR_BIN=C:\iar\ewarmc-10.10.2\arm\bin
rem  Repository roots. This repository locates itself, so its directory may be named
rem  anything; the other three default to siblings of it. Set any of these in the
rem  environment to use a different layout. scripts/README.md lists every variable.
for %%I in ("%~dp0..")    do set "REPO_ROOT=%%~fI"
for %%I in ("%~dp0..\..") do set "GH_ROOT=%%~fI"
set "GH_ROOT_FWD=%GH_ROOT:\=/%"
if "%TFM_SRC%"==""    set TFM_SRC=%GH_ROOT_FWD%/trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=%GH_ROOT%\tf-m-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=%REPO_ROOT:\=/%

set PATH=%IAR_BIN%;%PATH%

set SPE=%1
set NS=%2
set PART=%3
set IRQ=%4
set LEVEL=%5
set BACKEND=%6
if "%PART%"==""    set PART=ra6m5
if "%IRQ%"==""     set IRQ=flih
if "%LEVEL%"==""   set LEVEL=1
if "%BACKEND%"=="" set BACKEND=SFN

rem  Above isolation 1 the backend is not a free choice: set_config.cmake:35 turns on
rem  CONFIG_TFM_SPM_BACKEND_IPC for TFM_ISOLATION_LEVEL > 1 regardless of this string, and the
rem  mismatch surfaces as the manifest tool rejecting TFM_SP_IPC_{SERVICE,CLIENT}_TEST. See
rem  reg_build_gcc.bat's header for the full trace.
if not "%LEVEL%"=="1" (
  if /i not "%BACKEND%"=="IPC" (
    echo [reg_build_iar] isolation %LEVEL% implies the IPC backend ^(set_config.cmake:35^); overriding %BACKEND% -^> IPC
    set BACKEND=IPC
  )
)

rem  Per-part project directory prefix. Mirrors psa_arch_spe_iar.bat - keep them in step.
if /i "%PART%"=="ra8m2" (
  set S_DIR=ra8m2_iar_CPU0_secure
  set BL_DIR=ra8m2_iar_mcuboot
  set NS_DIR=ra8m2_iar_CPU0_nonsecure
) else (
  set S_DIR=ra6m5_iar_secure
  set BL_DIR=ra6m5_iar_mcuboot
  set NS_DIR=ra6m5_iar_nonsecure
)

set IRQ_ARGS=
if /i "%IRQ%"=="flih" set IRQ_ARGS=-DTEST_NS_FLIH_IRQ=ON
if /i "%IRQ%"=="slih" set IRQ_ARGS=-DTEST_NS_SLIH_IRQ=ON

if "%SPE%"=="" echo usage: %~nx0 ^<spe-build-dir^> ^<ns-build-dir^> [part] [flih^|slih^|none] [level] [SFN^|IPC] & exit /b 2
if "%NS%"==""  echo usage: %~nx0 ^<spe-build-dir^> ^<ns-build-dir^> [part] [flih^|slih^|none] [level] [SFN^|IPC] & exit /b 2

echo [reg_build_iar] part=%PART% irq=%IRQ% isolation=%LEVEL% backend=%BACKEND%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_reg\spe -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=MinSizeRel ^
    -DCMAKE_C_COMPILER=%IAR_BIN:\=/%/iccarm.exe ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC%/toolchain_IARARM.cmake ^
    -DTFM_PLATFORM=renesas/%PART% ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/%S_DIR% ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/%BL_DIR% ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/%NS_DIR% ^
    -DTEST_S=ON ^
    -DTEST_NS=ON ^
    %IRQ_ARGS% ^
    -DTFM_ISOLATION_LEVEL=%LEVEL% ^
    -DCONFIG_TFM_SPM_BACKEND=%BACKEND% ^
    -DMCUBOOT_LOG_LEVEL=INFO ^
    -DTFM_SPM_LOG_LEVEL=TFM_SPM_LOG_LEVEL_DEBUG
  if errorlevel 1 exit /b 1
)
rem  'install' produces api_ns\, which the NS build consumes. It also runs the OFS brick guard
rem  on bl2 and tfm_s - read its output, do not just check the exit code.
cmake --build %SPE% -- install
if errorlevel 1 exit /b 1

if not exist "%NS%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_reg -B %NS% -GNinja ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_IARARM.cmake ^
    %IRQ_ARGS%
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
