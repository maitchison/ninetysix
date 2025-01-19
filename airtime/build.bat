@echo off

: These are used if there's an error getting the
: date and time below
set TIME=ERR
set DATE=ERR

dt.exe
call dt.bat

set VERSION=05
set BUILD_DIR=c:\dev\build\airtime\%VERSION%
set LATEST_DIR=c:\dev\build\airtime\latest
set DATE_DIR=c:\dev\build\airtime\%DATE%
set MAIN=airtime

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
copy res\*.* %BUILD_DIR%\res
:copy resources.ini %BUILD_DIR%\resources.ini
copy changes.txt %BUILD_DIR%\changes.txt
copy readme.txt %BUILD_DIR%\readme.txt


:: ---------------------------------
:: Update Latest and date_coded
:: ---------------------------------

deltree /y %LATEST_DIR%
xcopy %BUILD_DIR% %LATEST_DIR% /E /I

deltree /y %DATE_DIR%
xcopy %BUILD_DIR% %DATE_DIR% /E /I

goto :end

:buildError

echo.
echo Debug build failed!
echo.
goto :end

:end
