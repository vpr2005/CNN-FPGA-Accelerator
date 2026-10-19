@echo off
setlocal

echo =======================================================================
echo          CNN FPGA ACCELERATOR: VIVADO FPGA SYNTHESIS FLOW
echo =======================================================================

set VIVADO_BIN=D:\Softwares\2025.2\Vivado\bin

echo Starting Vivado batch mode synthesis targeting Xilinx Artix-7 (xc7a100tcsg324-1)...
"%VIVADO_BIN%\vivado.bat" -mode batch -nolog -nojournal -source syn\synth.tcl

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Vivado synthesis failed!
    exit /b %ERRORLEVEL%
)

echo =======================================================================
echo Synthesis complete! Reports generated in syn\reports\
echo - Utilization: syn\reports\utilization.rpt
echo - Timing:      syn\reports\timing_summary.rpt
echo - Power:       syn\reports\power.rpt
echo =======================================================================
