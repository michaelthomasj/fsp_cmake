@echo off
rem  RA6M5 PSA Arch SPE, GCC.
rem
rem    psa_arch_spe.bat <build-dir> <TEST_PSA_API>
rem    psa_arch_spe.bat C:\b\m5cry CRYPTO
rem
rem  Builds BL2 + the secure image and installs api_ns\ for the NS build to consume. One SPE
rem  serves all three suites - profile_large enables crypto, ITS, PS, attestation and platform,
rem  which is what they need - so the suite argument only affects the PSA_API_TEST_* defines.
rem
rem  The outer wrapper needs CMAKE_C_COMPILER itself: it forces cross compilation and skips the
rem  compiler search. TFM_SPM_DEBUG_TRACE=OFF is required at isolation 3 with the IPC backend.
rem
rem  Override any of the paths by setting the variable before calling.

if "%GCC_BIN%"==""    set GCC_BIN=C:/Program Files (x86)/Arm GNU Toolchain arm-none-eabi/13.2 Rel1/bin
if "%TFM_SRC%"==""    set TFM_SRC=C:/Users/Michael/Documents/GitHub/trusted-firmware-m
if "%TFM_TESTS%"==""  set TFM_TESTS=C:\Users\Michael\Documents\GitHub\tf-m-tests
if "%PSA_TESTS%"==""  set PSA_TESTS=C:/Users/Michael/Documents/GitHub/psa-arch-tests
if "%FSP_CMAKE%"==""  set FSP_CMAKE=C:/Users/Michael/Documents/GitHub/fsp_cmake

set BUILD=%1
set SUITE=%2
if "%BUILD%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2
if "%SUITE%"=="" echo usage: %~nx0 ^<build-dir^> ^<TEST_PSA_API^> & exit /b 2

if not exist "%BUILD%\CMakeCache.txt" (
  cmake -S %TFM_TESTS%\tests_psa_arch\spe -B %BUILD% -GNinja ^
    -DCMAKE_C_COMPILER="%GCC_BIN%/arm-none-eabi-gcc.exe" ^
    -DCONFIG_TFM_SOURCE_PATH=%TFM_SRC% ^
    -DTFM_TOOLCHAIN_FILE=%TFM_SRC%/toolchain_GNUARM.cmake ^
    -DTFM_PLATFORM=renesas/ra6m5 ^
    -DFSP_S_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_secure ^
    -DFSP_BL2_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_mcuboot ^
    -DFSP_NS_APP_DIR=%FSP_CMAKE%/ra6m5_gcc_nonsecure ^
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
