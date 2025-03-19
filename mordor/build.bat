@echo off

set VERSION=01
set MAIN=mordor
set BUILD_DIR=c:\dev\build\%MAIN%\%VERSION%
set LATEST_DIR=c:\dev\build\%MAIN%\latest

echo Build dir is '%BUILD_DIR%'

deltree "%BUILD_DIR%"

mkdir %BUILD_DIR%
type NUL > %BUILD_DIR%\marker.txt

:: ---------------------------------
:: Builds
:: ---------------------------------

echo =======================
echo Building: debug
echo =======================
if EXIST _tmp\marker.txt deltree /y _tmp
mkdir _tmp
type NUL > _tmp\marker.txt
fpc @fp.cfg -dDEBUG -B -v0 -FE"_tmp" -CX -XX %MAIN%.pas
copy fpcdebug.txt %BUILD_DIR%\build_d.txt
IF ERRORLEVEL 1 goto :buildError

copy _tmp\%MAIN%.exe %BUILD_DIR%\%MAIN%d.exe
deltree /y _tmp

echo =======================
echo Building: normal
echo =======================
if EXIST _tmp\marker.txt deltree /y _tmp
mkdir _tmp
type NUL > _tmp\marker.txt
fpc @fp.cfg -dNORMAL -B -v0 -FE"_tmp" -CX -XX %MAIN%.pas
copy fpcdebug.txt %BUILD_DIR%\build.txt
IF ERRORLEVEL 1 goto :buildError

copy _tmp\%MAIN%.exe %BUILD_DIR%\%MAIN%.exe
deltree /y _tmp

:: ---------------------------------
:: Make Folders
:: ---------------------------------

mkdir %BUILD_DIR%\res
mkdir %BUILD_DIR%\gui
mkdir %BUILD_DIR%\sfx
mkdir %BUILD_DIR%\music

copy res\*.* %BUILD_DIR%\res
copy gui\*.* %BUILD_DIR%\gui
copy sfx\*.* %BUILD_DIR%\sfx
copy music\*.* %BUILD_DIR%\music


goto :end

:buildError

echo.
echo Debug build failed!
echo.
goto :end

:end
