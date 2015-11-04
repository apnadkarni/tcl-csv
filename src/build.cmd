@ECHO off
set PLATFORM=%1
IF NOT "x%PLATFORM%" == "x" goto do_setup
:ask_for_platform
set /P PLATFORM=x86 or x64?
:do_setup
IF "x%PLATFORM%" == "xx64" goto do_x64
IF "x%PLATFORM%" == "xx86" goto do_x86
goto ask_for_platform

:do_x64
envset x64 && tclsh build.tcl ext -config tclcsv.cfg -keep -target win32-dev64
goto done

:do_x86
envset x86 && tclsh build.tcl ext -config tclcsv.cfg -keep -target win32-dev32

:done
