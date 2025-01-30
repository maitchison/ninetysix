@echo off

set VERSION=01
set BUILD_DIR=c:\dev\build\player\%VERSION%
set LATEST_DIR=c:\dev\build\player\latest
set MAIN=player

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

mkdir %BUILD_DIR%\snd
copy res\*.* %BUILD_DIR%\res
copy music\*.* %BUILD_DIR%\music
copy sample\*.* %BUILD_DIR%\sample

:: ---------------------------------
:: Update Latest and date_coded
:: ---------------------------------

deltree /y %LATEST_DIR%
mkdir %LATEST_DIR%
mkdir %LATEST_DIR%\snd
copy %BUILD_DIR%\*.* %LATEST_DIR%\*.*
copy %BUILD_DIR%\snd\*.* %LATEST_DIR%\snd\*.*

goto :end

:buildError

echo.
echo Debug build failed!
echo.
goto :end

:end
