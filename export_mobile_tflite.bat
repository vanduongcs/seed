@echo off
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PYTHON=python"
set "SOURCE_MODEL=%ROOT%\backend\model\best.onnx"
set "MOBILE_IMGSZ=640"
set "EXPORTED_TFLITE=%ROOT%\backend\model\best_saved_model\best_float16.tflite"
set "MOBILE_MODEL_DIR=%ROOT%\mobile\assets\models"
set "MOBILE_MODEL=%MOBILE_MODEL_DIR%\best_float16.tflite"

echo.
echo === Seed mobile TFLite export ===
echo Source: %SOURCE_MODEL%
echo Target: %MOBILE_MODEL%
echo.

if not exist "%SOURCE_MODEL%" (
  echo ERROR: Source model not found: %SOURCE_MODEL%
  echo An ONNX model is required to export a new %MOBILE_IMGSZ%x%MOBILE_IMGSZ% mobile TFLite model.
  echo Existing backend ONNX files are not overwritten by this script.
  exit /b 1
)

%PYTHON% --version >nul 2>&1
if errorlevel 1 (
  echo ERROR: Python was not found on PATH.
  exit /b 1
)

%PYTHON% -c "import tensorflow, onnx2tf, tf_keras, onnx; print('Export dependencies OK')" || (
  echo.
  echo Installing export dependencies...
  %PYTHON% -m pip install "tensorflow==2.19.0" "tf_keras<=2.19.0" onnx onnx2tf sng4onnx onnx_graphsurgeon ai-edge-litert || exit /b 1
)

echo.
echo Exporting mobile TFLite model from ONNX, imgsz=%MOBILE_IMGSZ%, float16...
if exist "%ROOT%\backend\model\best_saved_model" rmdir /S /Q "%ROOT%\backend\model\best_saved_model"
%PYTHON% -c "import numpy as np; np.save(r'%ROOT%\calibration_image_sample_data_20x128x128x3_float32.npy', np.zeros((20,128,128,3), dtype=np.float32))" || exit /b 1
onnx2tf -i "%SOURCE_MODEL%" -o "%ROOT%\backend\model\best_saved_model" -n || exit /b 1

if not exist "%EXPORTED_TFLITE%" (
  echo ERROR: Export finished but TFLite was not found: %EXPORTED_TFLITE%
  exit /b 1
)

if not exist "%MOBILE_MODEL_DIR%" mkdir "%MOBILE_MODEL_DIR%"
copy /Y "%EXPORTED_TFLITE%" "%MOBILE_MODEL%" >nul || exit /b 1

if exist "%ROOT%\backend\model\best_saved_model" rmdir /S /Q "%ROOT%\backend\model\best_saved_model"
if exist "%ROOT%\calibration_image_sample_data_20x128x128x3_float32.npy" del /Q "%ROOT%\calibration_image_sample_data_20x128x128x3_float32.npy"
if exist "%ROOT%\calibration_image_sample_data_20x128x128x3_float32.npy.zip" del /Q "%ROOT%\calibration_image_sample_data_20x128x128x3_float32.npy.zip"

echo.
echo Done.
echo Mobile model updated: %MOBILE_MODEL%
echo.
pause
