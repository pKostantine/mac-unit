@echo off
REM Windows convenience script -- same thing the Makefile does.
REM Run from the project root:  run.bat
REM Add "wave" to open GTKWave afterwards:  run.bat wave

if not exist sim mkdir sim

iverilog -Wall -g2001 -o sim\sim.vvp tb\tb_mac.v rtl\mac.v
if errorlevel 1 (
    echo.
    echo COMPILE FAILED
    exit /b 1
)

pushd sim
vvp sim.vvp
popd

if "%1"=="wave" gtkwave sim\dump.vcd
