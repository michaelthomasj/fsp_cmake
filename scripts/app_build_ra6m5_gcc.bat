@echo off
rem  RA6M5 application chain (BL2 + secure + the port's NS app), GNUARM.
rem
rem    app_build_ra6m5_gcc.bat [spe-build-dir] [ns-build-dir]
rem    app_build_ra6m5_gcc.bat C:\b\m5g C:\b\m5gns
rem
rem  Debug / isolation 1 / SFN backend / SPM trace on - the application configuration. The
rem  PSA Arch builds are a different one (profile_large, isolation 3, IPC); see psa_arch_spe.bat.
rem
rem  THE DEFAULTS ARE build_ra6m5_sce9 AND build_ra6m5_sce9_ns IN THE TF-M TREE, because that is
rem  the pair the committed ra6m5_TFM_sce9_gcc launch flashes. A launch names every image by
rem  absolute path, so a script that defaulted elsewhere would leave the launch pointing at
rem  nothing. Build elsewhere by passing both arguments, then clone the launch onto the new tree
rem  with mk_level_launch.py.
rem
rem  CMAKE_BUILD_TYPE=Debug, where app_build_ra8m2_gcc.bat has to use MinSizeRel. The secure
rem  regions differ by more than 200 KB: RA8M2's is 294,400 B and GNUARM Debug comes out around
rem  414 KB there, while RA6M5's is 521,728 B and Debug uses 322,960 B of it - 61.9%, measured
rem  on a clean tree 2026-10-29. Do not read tfm_s.bin's size as the figure; imgtool pads it to
rem  the region, so it reports 521,792 B whatever the image costs. Read the linker's own
rem  "Memory region" table instead.
rem
rem  TFM_SPM_LOG_LEVEL is passed because ra6m5/config.cmake sets TFM_SPM_DEBUG_TRACE=ON and
rem  check_config.cmake rejects that against a SILENCE log level. Debug does not default to
rem  SILENCE, so it is belt and braces here - it is load-bearing in the MinSizeRel builds.
rem
rem  Quote %GCC_BIN% in every test. The default path contains "(x86)" and an unquoted
rem  "if not exist %GCC_BIN%\..." closes the block at the first paren - the body is then
rem  skipped and the script exits 0 having done nothing.

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
if "%SPE%"=="" set SPE=%TFM_SRC%\build_ra6m5_sce9
if "%NS%"==""  set NS=%TFM_SRC%\build_ra6m5_sce9_ns

set PATH=%GCC_BIN%;%PATH%
set TFM_SRC_FWD=%TFM_SRC:\=/%
set GCC_BIN_FWD=%GCC_BIN:\=/%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_SRC% -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_C_COMPILER="%GCC_BIN_FWD%/arm-none-eabi-gcc.exe" ^
    -DTFM_PLATFORM=renesas/ra6m5 ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC_FWD%/toolchain_GNUARM.cmake ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_nonsecure ^
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
  cmake -S %TFM_SRC%\platform\ext\target\renesas\ra6m5\ns_app -B %NS% -GNinja ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_GNUARM.cmake
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
