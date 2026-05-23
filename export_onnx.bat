@echo off
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
:: Use system python (must have ultralytics + torch installed).
:: If you prefer the venv, change this to: set "PYTHON=%ROOT%\backend\.venv\Scripts\python.exe"
set "PYTHON=python"
set "FASTSAM_S_PT=%ROOT%\FastSAM-s.pt"
set "FASTSAM_S_ONNX=%ROOT%\backend\model\FastSAM-s.onnx"

echo.
echo === Seed ONNX Export ===
echo.

:: Check Python venv
if not exist "%PYTHON%" (
  echo ERROR: Python venv not found at: %PYTHON%
  echo Run run.bat first to set up the backend venv.
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

:: ── Export FastSAM-s ──────────────────────────────────────────────────────────
echo [1/1] Exporting FastSAM-s.pt → FastSAM-s.onnx ...
if not exist "%FASTSAM_S_PT%" (
  echo ERROR: Source model not found: %FASTSAM_S_PT%
  echo Place FastSAM-s.pt in the project root ^(%ROOT%^).
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
