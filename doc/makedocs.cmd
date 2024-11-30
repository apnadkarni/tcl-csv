setlocal
set TCLLIBPATH=%TCLLIBPATH% ../build/dist/
tclsh buildsite.tcl
start output\tclcsv.html
endlocal
