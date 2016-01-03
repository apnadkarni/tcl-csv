rmdir/s/q build
@rem Form the file name based on the version we are building
@for /f %%i in ('tclsh src/version.tcl') do set FNAME=tclcsv%%i

@rem We fire off new shells so as to not change our env
cmd /c "envset x86 && cd src && tclsh build.tcl extension -target win32-ix86-cl && cd .."
cmd /c "envset x64 && cd src && tclsh build.tcl extension -target win32-x86_64-cl && cd .."
cmd /c "cd src && tclsh build.tcl tea && cd .."
move build\lib\tclcsv build\lib\%FNAME%
cd build\lib && zip -r %FNAME%.zip %FNAME% && move %FNAME%.zip .. && cd ..\..
move build\tea\tclcsv build\tea\%FNAME%
cd build\tea && tar cvf ../%FNAME%.tar %FNAME% && gzip ../%FNAME%.tar && cd ..\..

