@echo off
setlocal

echo =======================================================================
echo          OPENING CNN ACCELERATOR IN VIVADO GUI
echo =======================================================================

set VIVADO_BIN=D:\Softwares\2025.2\Vivado\bin
set PROJ_XPR=vivado_project\cnn_accelerator.xpr

if not exist "%PROJ_XPR%" (
    echo [INFO] Project file not found. Generating Vivado project first...
    call "%VIVADO_BIN%\vivado.bat" -mode batch -nolog -nojournal -source scripts\create_project.tcl
)

echo Launching Vivado GUI with %PROJ_XPR%...
start "" "%VIVADO_BIN%\vivado.bat" "%PROJ_XPR%"
