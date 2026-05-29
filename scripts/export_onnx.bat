@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
:: Use system python (must have ultralytics + torch installed).
:: If you prefer the venv, change this to: set "PYTHON=%ROOT%\backend\.venv\Scripts\python.exe"
set "PYTHON=python"
set "FASTSAM_S_PT=%ROOT%\artifacts\models\FastSAM-s.pt"
set "FASTSAM_S_ONNX=%ROOT%\backend\model\FastSAM-s.onnx"

echo.
echo === Seed ONNX Export ===
echo.

:: Check Python availability
"%PYTHON%" --version >nul 2>&1
if errorlevel 1 (
  echo ERROR: Python is not available via: %PYTHON%
  echo Run scripts\run.bat first to set up the backend venv if needed.
  pause
  exit /b 1
)

:: Check ultralytics available (needed for one-time export only)
"%PYTHON%" -c "import ultralytics" >nul 2>&1
if errorlevel 1 (
  echo Installing ultralytics for export ^(one-time^)...
  "%PYTHON%" -m pip install "ultralytics>=8.2" "torch>=2.4" --quiet
  if errorlevel 1 (
    echo ERROR: Failed to install export dependencies.
    pause
    exit /b 1
  )
)

:: Export FastSAM-s.
echo [1/1] Exporting FastSAM-s.pt to FastSAM-s.onnx ...
if not exist "%FASTSAM_S_PT%" (
  echo ERROR: Source model not found: %FASTSAM_S_PT%
  echo Place FastSAM-s.pt under artifacts\models.
  pause
  exit /b 1
)

"%PYTHON%" -c ^
  "from ultralytics import FastSAM; ^
   import shutil, pathlib; ^
   m = FastSAM(r'%FASTSAM_S_PT%'); ^
   out = m.export(format='onnx', imgsz=1024, opset=12, simplify=True, dynamic=False); ^
   dest = pathlib.Path(r'%FASTSAM_S_ONNX%'); ^
   dest.parent.mkdir(parents=True, exist_ok=True); ^
   shutil.copy(str(out), str(dest)); ^
   print('Saved to:', dest)"
if errorlevel 1 (
  echo ERROR: FastSAM-s.pt export failed.
  pause
  exit /b 1
)

echo.
echo === Export complete ===
echo FastSAM-s ONNX : %FASTSAM_S_ONNX%
echo.
echo You can now remove torch and ultralytics from backend\python\requirements.txt
echo ^(they are only needed for this one-time export^).
echo.
pause
