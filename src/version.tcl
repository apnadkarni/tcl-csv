namespace eval tclcsv {
    proc version {} {return 2.2.0}
}
if {[file tail [info script]] eq [file tail [lindex $argv0 0]]} {
    puts [tclcsv::version]
}
return [tclcsv::version]
