@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
set "MOBILE_DIR=%ROOT%\mobile"
set "OUT_DIR=%ROOT%\artifacts\releases"
set "KEY_PROPS=%MOBILE_DIR%\android\key.properties"
set "APK_SRC=%MOBILE_DIR%\build\app\outputs\flutter-apk\app-release.apk"
set "AAB_SRC=%MOBILE_DIR%\build\app\outputs\bundle\release\app-release.aab"

echo.
echo === SeedVision Mobile Release Export ===
echo Root   : %ROOT%
echo Mobile : %MOBILE_DIR%
echo Output : %OUT_DIR%
echo.

where flutter >nul 2>&1
if errorlevel 1 (
  echo ERROR: Flutter was not found on PATH.
  exit /b 1
)

if not exist "%KEY_PROPS%" (
  echo ERROR: Release signing config is missing: %KEY_PROPS%
  echo Create mobile\android\key.properties and keep it out of git.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$props=@{}; Get-Content -LiteralPath '%KEY_PROPS%' | Where-Object { $_ -match '^\s*[^#=]+\s*=' } | ForEach-Object { $k,$v=$_.Split('=',2); $props[$k.Trim()]=$v.Trim() }; if (-not $props.storeFile) { Write-Host 'ERROR: key.properties is missing storeFile.'; exit 2 }; $store=Join-Path (Split-Path -Parent '%KEY_PROPS%') $props.storeFile; if (-not (Test-Path -LiteralPath $store)) { Write-Host ('ERROR: Keystore file not found: ' + $store); exit 3 }"
if errorlevel 1 exit /b 1

for /f "tokens=2 delims= " %%v in ('findstr /B "version:" "%MOBILE_DIR%\pubspec.yaml"') do set "APP_VERSION=%%v"
if not defined APP_VERSION set "APP_VERSION=unknown"
set "APP_VERSION=%APP_VERSION:+=-%"

for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "BUILD_ID=%%t"

if /I "%~1"=="clean" (
  echo Running flutter clean...
  pushd "%MOBILE_DIR%"
  call flutter clean
  if errorlevel 1 (
    popd
    exit /b 1
  )
  popd
)

echo Running flutter pub get...
pushd "%MOBILE_DIR%"
call flutter pub get
if errorlevel 1 (
  popd
  exit /b 1
)

echo Building release APK for local install...
call flutter build apk --release
if errorlevel 1 (
  popd
  exit /b 1
)

echo Building release AAB for Play Console...
call flutter build appbundle --release
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if not exist "%APK_SRC%" (
  echo ERROR: APK output not found: %APK_SRC%
  exit /b 1
)
if not exist "%AAB_SRC%" (
  echo ERROR: AAB output not found: %AAB_SRC%
  exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

copy /Y "%APK_SRC%" "%OUT_DIR%\seedvision-release.apk" >nul
copy /Y "%AAB_SRC%" "%OUT_DIR%\seedvision-release.aab" >nul
copy /Y "%APK_SRC%" "%OUT_DIR%\seedvision-%APP_VERSION%-%BUILD_ID%.apk" >nul
copy /Y "%AAB_SRC%" "%OUT_DIR%\seedvision-%APP_VERSION%-%BUILD_ID%.aab" >nul

echo.
echo === Export complete ===
echo Install APK : %OUT_DIR%\seedvision-release.apk
echo Play AAB    : %OUT_DIR%\seedvision-release.aab
echo Versioned   : seedvision-%APP_VERSION%-%BUILD_ID%.apk/.aab
echo.
exit /b 0
