rmdir/s/q build

@rem We fire off new shells so as to not change our env
cmd /c "envset x86 && cd win && nmake /f makefile.vc INSTALLDIR=..\build TCLDIR=d:\tcl\868-vc6\x86 hose && cd .."
cmd /c "envset x86 && cd win && nmake /f makefile.vc INSTALLDIR=..\build TCLDIR=d:\tcl\868-vc6\x86 tclcsv install && cd .."
cmd /c "envset x64 && cd win && nmake /f makefile.vc INSTALLDIR=..\build TCLDIR=d:\tcl\868-vc6\x64 hose && cd .."
cmd /c "envset x64 && cd win && nmake /f makefile.vc INSTALLDIR=..\build TCLDIR=d:\tcl\868-vc6\x64 tclcsv install && cd .."

@rem Extract the version number and build the file name to use
for /f %%i in ('win\nmakehlp -V configure.in tclcsv') do set TCLCSVVER=%%i
set TCLCSVFNAME=tclcsv-%TCLCSVVER%

@rem Windows binaries
cd build && zip -r %TCLCSVFNAME%.zip tclcsv%TCLCSVVER%  && cd ..

@rem --no-decode option because we do not want \r\n in Unix distro
hg archive build\%TCLCSVFNAME%-src.tar.gz -X ".hg*" --no-decode
hg archive build\%TCLCSVFNAME%-src.zip -X ".hg*"

set TCLCSVFNAME=
