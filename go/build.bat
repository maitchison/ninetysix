@echo off

set BIN_DIR=c:\dev\bin

echo =======================
echo Building: debug
echo =======================
del go.exe
fpc @fp.cfg -dDEBUG -B -v0 go.pas
IF ERRORLEVEL 1 goto :buildError

copy tmp\go.exe %BIN_DIR%\god.exe
:deltree /y tmp

echo =======================
echo Building: normal
echo =======================
del go.exe
fpc @fp.cfg -dNORMAL -B -v0 go.pas
IF ERRORLEVEL 1 goto :buildError

copy go.exe %BIN_DIR%\go.exe
goto :end

:buildError

echo.
echo Build failed!
echo.
goto :end

:end
