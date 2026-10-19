@echo off
setlocal

echo =======================================================================
echo          CNN FPGA ACCELERATOR: SIMULATION AND VERIFICATION FLOW
echo =======================================================================

set VIVADO_BIN=D:\Softwares\2025.2\Vivado\bin
set PYTHON_EXE=D:\Softwares\2025.2\tps\win64\python-3.13.0\python.exe

echo [1/3] Generating test vectors and golden models...
"%PYTHON_EXE%" python\generate_test_vectors.py
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Test vector generation failed!
    exit /b %ERRORLEVEL%
)

echo [2/3] Compiling and running SystemVerilog simulation in Vivado xsim...
call "%VIVADO_BIN%\xvlog.bat" -sv rtl\mac_unit.sv rtl\line_buffer.sv rtl\pe_array.sv rtl\relu_unit.sv rtl\maxpool_unit.sv rtl\pool_engine.sv rtl\feature_ram.sv rtl\fc_engine.sv rtl\conv_engine.sv rtl\cnn_top.sv tb\tb_cnn_top.sv
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

call "%VIVADO_BIN%\xelab.bat" tb_cnn_top -s tb_cnn_top_sim
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Elaboration failed!
    exit /b %ERRORLEVEL%
)

call "%VIVADO_BIN%\xsim.bat" tb_cnn_top_sim -R
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Simulation execution failed!
    exit /b %ERRORLEVEL%
)

echo [3/3] Running Bit-Accurate Python Verification...
"%PYTHON_EXE%" python\verify.py
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Verification failed!
    exit /b %ERRORLEVEL%
)

echo =======================================================================
echo [SUCCESS] ALL SIMULATION AND VERIFICATION STEPS COMPLETED SUCCESSFULLY!
echo =======================================================================
