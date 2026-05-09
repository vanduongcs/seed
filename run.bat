@echo off
setlocal

cd /d "%~dp0"
title Seed Launcher

if /i "%~1"=="backend" goto backend_worker

:menu
cls
echo ==========================
echo        Seed Launcher
echo ==========================
echo.
echo 1. Run web
echo 2. Run mobile app
echo 3. Run all
echo 0. Exit
echo.
set /p choice=Choose an option: 

if "%choice%"=="1" goto run_web
if "%choice%"=="2" goto run_mobile
if "%choice%"=="3" goto run_all
if "%choice%"=="0" goto end

echo.
echo Invalid option. Press any key to try again.
pause >nul
goto menu

:run_web
call :start_backend
call :start_web
goto done

:run_mobile
call :start_backend
call :start_mobile
goto done

:run_all
call :start_backend
call :start_web
call :start_mobile
goto done

:start_backend
start "Seed Backend" /D "%~dp0" cmd /k call run.bat backend
exit /b

:start_web
start "Seed Web" /D "%~dp0" cmd /k "npm run dev:web"
exit /b

:start_mobile
start "Seed Mobile" /D "%~dp0mobile" cmd /k "flutter pub get && flutter run"
exit /b

:done
echo.
echo Started selected service(s).
echo Close the opened terminal windows to stop them.
echo.
pause
goto menu

:end
endlocal
exit /b

:backend_worker
netstat -ano -p tcp | findstr /R /C:":3000 .*LISTENING" >nul
if not errorlevel 1 (
  echo Backend API is already running on http://localhost:3000.
  exit /b
)

if not exist backend\.venv\Scripts\python.exe (
  echo Creating Python virtual environment...
  python -m venv backend\.venv
  if errorlevel 1 goto backend_failed
  backend\.venv\Scripts\python.exe -m pip install -r backend\python\requirements.txt
  if errorlevel 1 goto backend_failed
)

echo Starting backend API on http://localhost:3000 ...
npm run dev:backend
exit /b

:backend_failed
echo.
echo Backend setup failed. Check Python installation and backend\python\requirements.txt.
exit /b 1
