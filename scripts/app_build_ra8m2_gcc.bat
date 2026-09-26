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
rem  MinSizeRel leaves TFM_SPM_LOG_LEVEL at its default, so unlike the IAR script there is no
rem  TFM_SPM_DEBUG_TRACE conflict to work around. Pass -DTFM_SPM_LOG_LEVEL=... explicitly if
rem  you want SPM tracing here.
rem
rem  Build directories must be SHORT. Under a deep path the Mbed TLS overlay clone fails with
rem  "Filename too long" on 3rdparty/everest/..., which is why the defaults are under C:\b.
rem
rem  Quote %GCC_BIN% in every test. The default path contains "(x86)" and an unquoted
rem  "if not exist %GCC_BIN%\..." closes the block at the first paren - the body is then
rem  skipped and the script exits 0 having done nothing. That cost a debugging session once.

if "%GCC_BIN%"==""   set GCC_BIN=C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\13.2 Rel1\bin
if "%TFM_SRC%"==""   set TFM_SRC=C:\Users\Michael\Documents\GitHub\trusted-firmware-m
if "%FSP_CMAKE%"=="" set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

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
    -DCONFIG_TFM_SPM_BACKEND=SFN
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
