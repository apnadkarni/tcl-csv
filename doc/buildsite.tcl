package require fileutil
foreach line [fileutil::grep AC_INIT ../configure.in] {
    if {[regexp {AC_INIT..tclcsv.,.([^\]]+)} $line -> tclcsvversion]} break
}
set target output
set adocgen_files {
    tclcsv
}

# file delete -force $target
file mkdir $target
file delete -force [file join $target images]
file copy images [file join $target images]
puts [exec [info nameofexecutable] d:/src/tcl-on-windows/tools/adocgen.tcl -outdir $target -maketoc toc.ad -unsafe -overwrite -author "Ashok P. Nadkarni" {*}$argv {*}[lmap fn $adocgen_files {append fn .adocgen}] 2>@1]
cd $target
puts [exec asciidoctor -a tclcsvversion=$tclcsvversion {*}[lmap fn $adocgen_files {append fn .ad}]]

