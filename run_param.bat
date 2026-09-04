@echo off
REM Parameter sweep -- proves the design is genuinely parameterised.
REM Run from the project root:  run_param.bat
if not exist sim mkdir sim

call :one 8 32 7
call :one 4 16 3
call :one 6 24 5
call :one 12 40 9
goto :eof

:one
iverilog -g2001 -DW=%1 -DAW=%2 -DFB=%3 -o sim\p.vvp tb\tb_param.v rtl\mac.v
if errorlevel 1 (echo   W=%1 ACC=%2 FRAC=%3 : COMPILE FAILED & goto :eof)
pushd sim
vvp p.vvp
popd
goto :eof
