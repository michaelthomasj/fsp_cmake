@echo off
rem  RA6M5 application chain (BL2 + secure + the port's NS app), IAR.
rem
rem    app_build_iar.bat [spe-build-dir] [ns-build-dir]
rem    app_build_iar.bat C:\b\m5iapp C:\b\m5iappns
rem
rem  This is the GCC recipe in build_ra6m5_sce9 / build_ra6m5_sce9_ns - Debug, SFN backend,
rem  isolation 1, SPM trace on - with the IAR toolchain and projects. The PSA Arch builds are
rem  a different configuration (profile_large, isolation 3, IPC); see psa_arch_spe_iar.bat.
rem
rem  IAR needs iccarm on PATH (toolchain_IARARM.cmake names it without a path) and the ASM
rem  architecture id CMake 4.1 cannot detect. DECISIONS D046.

if "%IAR_BIN%"==""   set IAR_BIN=C:\iar\ewarm-10.10.2\arm\bin
if "%TFM_SRC%"==""   set TFM_SRC=C:\Users\Michael\Documents\GitHub\trusted-firmware-m
if "%FSP_CMAKE%"=="" set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set SPE=%1
set NS=%2
if "%SPE%"=="" set SPE=%TFM_SRC%\build_ra6m5_iar
if "%NS%"==""  set NS=%TFM_SRC%\build_ra6m5_iar_ns

set PATH=%IAR_BIN%;%PATH%
set TFM_SRC_FWD=%TFM_SRC:\=/%

if not exist "%SPE%\CMakeCache.txt" (
  cmake -S %TFM_SRC% -B %SPE% -GNinja ^
    -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DTFM_PLATFORM=renesas/ra6m5 ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC_FWD%/toolchain_IARARM.cmake ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra6m5_iar_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra6m5_iar_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra6m5_iar_nonsecure ^
    -DTFM_ISOLATION_LEVEL=1 ^
    -DCONFIG_TFM_SPM_BACKEND=SFN
  if errorlevel 1 exit /b 1
)
cmake --build %SPE% -- install
if errorlevel 1 exit /b 1

if not exist "%NS%\CMakeCache.txt" (
  cmake -S %TFM_SRC%\platform\ext\target\renesas\ra6m5\ns_app -B %NS% -GNinja ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_SPE_PATH=%SPE:\=/%/api_ns ^
    -DTFM_TOOLCHAIN_FILE=%SPE:\=/%/api_ns/cmake/toolchain_ns_IARARM.cmake
  if errorlevel 1 exit /b 1
)
cmake --build %NS%
exit /b %ERRORLEVEL%
