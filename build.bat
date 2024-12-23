@echo off

: These are used if there's an error getting the
: date and time below
set DATE=ERR
set DATE=ERR

dt.exe
call dt.bat

set VERSION=01a
set BUILD_DIR=builds\%VERSION%
set MAIN=airtime

echo Build dir is '%BUILD_DIR%'

: for some reason msdos exist does not work on folders, only filenames.
IF EXIST %BUILD_DIR%\marker.txt move %BUILD_DIR% %BUILD_DIR%_%DATE%_%TIME%

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
fpc @fp.cfg -dDEBUG -B -v0 -vv -FE"_tmp" -CX -XX %MAIN%.pas
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
fpc @fp.cfg -dNORMAL -B -v0 -vv -FE"_tmp" -CX -XX %MAIN%.pas
copy fpcdebug.txt %BUILD_DIR%\build.txt
IF ERRORLEVEL 1 goto :buildError

copy _tmp\%MAIN%.exe %BUILD_DIR%\%MAIN%.exe
deltree /y _tmp

:: ---------------------------------
:: Make Folders
:: ---------------------------------

mkdir %BUILD_DIR%\res
copy res\*.* %BUILD_DIR%\res

goto :end

:buildError

echo.
echo Debug build failed!
echo.
goto :end

:end
