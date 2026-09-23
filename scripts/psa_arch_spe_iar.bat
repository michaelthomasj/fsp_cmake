@echo off
rem  RA6M5 PSA Arch SPE, IAR.
rem
rem    psa_arch_spe_iar.bat <build-dir> <TEST_PSA_API>
rem    psa_arch_spe_iar.bat C:\b\m5icry CRYPTO
rem
rem  Builds BL2 + the secure image and installs api_ns\ for the NS build to consume. One SPE
rem  serves all three suites - profile_large enables crypto, ITS, PS, attestation and platform,
rem  which is what they need - so the suite argument only affects the PSA_API_TEST_* defines.
rem
rem  Four things here that the GCC build does not need (DECISIONS D046):
rem    - IAR on PATH: toolchain_IARARM.cmake names "iccarm" with no path.
rem    - CMAKE_ASM_COMPILER_ARCHITECTURE_ID: CMake 4.1's IAR-ASM module cannot detect it, and
rem      fails on the RE-configure, after the first configure has already succeeded.
rem    - The outer wrapper needs CMAKE_C_COMPILER itself; it forces cross compilation and
rem      skips the compiler search.
rem    - TFM_SPM_DEBUG_TRACE=OFF: required at isolation 3 with the IPC backend.
rem
rem  Override any of the paths by setting the variable before calling.

if "%IAR_BIN%"==""    set IAR_BIN=C:\iar\ewarm-10.10.2\arm\bin
if "%TFM_SRC%"==""    set TFM_SRC=C:/Users/Michael/Documents/GitHub/trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%PSA_TESTS%"==""  set PSA_TESTS=C:/Users/Michael/Documents/GitHub/psa-arch-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set PATH=%IAR_BIN%;%PATH%

set BUILD=%1
set SUITE=%2
if "%BUILD%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2
if "%SUITE%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2

if not exist "%BUILD%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_psa_arch\spe -B %BUILD% -GNinja ^
    -DCMAKE_C_COMPILER=%IAR_BIN:\=/%/iccarm.exe ^
    -DCMAKE_ASM_COMPILER_ARCHITECTURE_ID=ARM ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC%/toolchain_IARARM.cmake ^
    -DTFM_PLATFORM=renesas/ra6m5 ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra6m5_iar_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra6m5_iar_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra6m5_iar_nonsecure ^
    -DTEST_PSA_API=%SUITE% ^
    -DTFM_PROFILE=profile_large ^
    -DTFM_ISOLATION_LEVEL=3 ^
    -DCONFIG_TFM_SPM_BACKEND=IPC ^
    -DTFM_SPM_DEBUG_TRACE=OFF ^
    -DRA6M5_RTT_BLOCKING=ON ^
    -DPSA_ARCH_TESTS_PATH=%PSA_TESTS% ^
    -DPSA_API_TEST_TARGET=renesas_ra
  if errorlevel 1 exit /b 1
)

cmake --build %BUILD% -- install
exit /b %ERRORLEVEL%
