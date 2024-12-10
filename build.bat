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

:CHOICE /C:YN "Continue? "
:IF ERRORLEVEL 2 goto :end

IF EXIST %BUILD_DIR% move %BUILD_DIR% %BUILD_DIR%_%DATE%_%TIME%

mkdir %BUILD_DIR%

:: ---------------------------------
:: Builds
:: ---------------------------------

echo =======================
echo Building: debug
echo =======================
if EXIST tmp deltree tmp
mkdir tmp
fpc @fp.cfg -dDEBUG -v -FE"tmp" %MAIN%.pas
IF ERRORLEVEL 1 goto :buildError

copy tmp\%MAIN%.exe %BUILD_DIR%\%MAIN%d.exe
deltree tmp

:: ---------------------------------
:: Make Folders
:: ---------------------------------

mkdir "%BUILD_DIR%\gfx"
mkdir "%BUILD_DIR%\sfx"


goto :end

:buildError

echo.
echo Debug build failed!
echo.
goto :end

:end
