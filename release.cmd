rmdir/s/q build
@rem Form the file name basaed on the version we are building
@for /f %%i in ('tclsh src/version.tcl') do set FNAME=tclcsv-%%i

@rem We fire off new shells so as to not change our env
cmd /c "envset x86 && cd src && tclsh build.tcl extension -target win32-ix86-cl && cd .."
cmd /c "envset x64 && cd src && tclsh build.tcl extension -target win32-x86_64-cl && cd .."
cmd /c "cd src && tclsh build.tcl tea && cd .."
cd build\lib && zip -r tclcsv.zip tclcsv && move tclcsv.zip ..\%FNAME%.zip && cd ..\..
cd build\tea && tar cvf tclcsv.tar tclcsv && gzip tclcsv.tar && move tclcsv.tar.gz ..\%FNAME%.tar.gz && cd ..\..

