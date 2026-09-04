@echo off
REM Simulate the Go Board wrapper before programming the board.
REM Run from the project root:  run_top.bat
if not exist sim mkdir sim

iverilog -Wall -g2001 -o sim\top.vvp tb\tb_mac_top.v rtl\mac_top.v rtl\mac.v rtl\debounce.v rtl\hex7seg.v
if errorlevel 1 (
    echo.
    echo COMPILE FAILED
    exit /b 1
)
pushd sim
vvp top.vvp
popd
